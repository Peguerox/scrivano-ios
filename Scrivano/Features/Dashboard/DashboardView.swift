import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers
import Vision

struct DashboardView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var langMgr: LanguageManager
    @StateObject private var vm = DashboardViewModel()
    @ObservedObject private var transcriptionMgr = TranscriptionManager.shared
    @ObservedObject private var recorder = AudioRecorderManager.shared
    @ObservedObject private var notesMgr = NoteGenerationManager.shared
    @ObservedObject private var taskQueue = TaskQueueManager.shared
    @State private var showSettings = false
    @State private var showCollections = false
    @State private var showNewItem = false
    @State private var recordAfterNewItem = false
    @State private var selectedItem: Item? = nil
    @State private var viewMode: ViewMode = .card
    @State private var showRecorder = false
    @State private var showRecordCard = false
    @State private var fabPulse = false
    @State private var sessionWarmTask: Task<Void, Never>? = nil


    @AppStorage("showMyCollection") private var showMyCollection: Bool = true

    // Collection alerts / cards
    @State private var showCollectionMinOne = false
    @State private var showCollectionActiveError = false
    @State private var showCollectionDuplicate = false
    @State private var showCollectionNew = false
    @State private var newCollectionName = ""

    // Task 9: Submit collection
    @State private var showSubmitCard = false
    @State private var submitSuccess = false
    @State private var submitMessage: String? = nil
    @State private var isSubmitting = false
    @AppStorage("auto_upload") private var autoUpload = false

    // Task 10: Create list from image
    @State private var showCreateListCard = false
    @State private var showCreateListCamera = false
    @State private var showCreateListLibrary = false
    @State private var isCreatingList = false
    @State private var createListResult: String? = nil
    @State private var createListError: String? = nil
    @State private var pendingListImage: UIImage? = nil

    // Process Items mode
    enum ProcessType { case audio, text }
    @State private var showProcessItemsMode = false
    @State private var processType: ProcessType = .audio
    @State private var processItemsSelected = Set<String>()
    @State private var showProcessItemsPrompts = false

    // Rename / Delete collection
    @State private var showDeleteCollectionCard    = false
    @State private var showRenameCollectionCard    = false
    @State private var renameCollectionText        = ""

    // Rename item overlay
    @State private var renameItem: Item? = nil
    @State private var renameItemText = ""

    // New item overlay
    @State private var newItemName = ""
    @State private var newItemDuplicateError = false
    @FocusState private var newItemFocused: Bool

    // Clear confirm overlay
    @State private var clearConfirmItem: Item? = nil

    // Prompt database
    @State private var showPromptDatabase          = false

    enum ViewMode { case card, list }
    enum SortOrder { case insertion, az, za }
    @State private var sortOrder: SortOrder = .insertion

    private var displayedItems: [Item] {
        switch sortOrder {
        case .insertion: return vm.items
        case .az:        return vm.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .za:        return vm.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        }
    }

    var body: some View {
        withDialogs
            .task { await vm.load(); TranscriptionManager.shared.resumePendingTasks() }
            .onReceive(NotificationCenter.default.publisher(for: TrashStore.didRestoreNotification)) { _ in
                vm.refreshFromLocalStores()
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrivanoBackupRestored)) { _ in
                vm.refreshFromLocalStores()
            }
    }

    private var withSheets: some View {
        AnyView(
            navStack
                .fullScreenCover(isPresented: $showSettings, onDismiss: { vm.refreshFromLocalStores() }) { SettingsView() }
                .fullScreenCover(isPresented: $showRecorder) {
                    if let item = selectedItem {
                        RecordingView(item: item,
                            onRename: { newName in
                                if let idx = vm.items.firstIndex(where: { $0.id == item.id }) {
                                    vm.items[idx] = vm.items[idx].renamed(to: newName)
                                }
                            },
                            onRecordingSaved: { vm.recordingSaved(itemId: item.id) })
                    }
                }
                .sheet(isPresented: $showCreateListCamera) {
                    ImagePickerView(sourceType: .camera) { image in
                        pendingListImage = image
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCreateListCard = true }
                    }
                }
                .sheet(isPresented: $showCreateListLibrary) {
                    ImagePickerView(sourceType: .photoLibrary) { image in
                        pendingListImage = image
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCreateListCard = true }
                    }
                }
                .fullScreenCover(isPresented: $showPromptDatabase) {
                    PromptsView(context: .browse)
                }
                .fullScreenCover(isPresented: $showProcessItemsPrompts, onDismiss: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showProcessItemsMode = false
                        processItemsSelected.removeAll()
                    }
                }) {
                    let mergeEntries: [(text: String, id: String, itemId: String)] = displayedItems
                        .filter { processItemsSelected.contains($0.id) }
                        .compactMap { item in
                        let iid = item.id
                        // Try merge entry first; fall back to combining all non-merge transcripts
                        if let merge = LocalTranscriptStore.shared.entries.first(where: { $0.itemId == iid && $0.isMerge && !$0.text.isEmpty }) {
                            return (text: merge.text, id: merge.id, itemId: iid)
                        }
                        let parts = LocalTranscriptStore.shared.entries.filter { $0.itemId == iid && !$0.isMerge && !$0.text.isEmpty }
                        guard !parts.isEmpty else { return nil }
                        let combined = parts.map { $0.text }.joined(separator: "\n")
                        return (text: combined, id: parts[0].id, itemId: iid)
                    }
                    let texts   = mergeEntries.map { $0.text }
                    let ids     = mergeEntries.map { $0.id }
                    let firstId = mergeEntries.first?.itemId ?? processItemsSelected.first ?? ""
                    if mergeEntries.count == 1 {
                        PromptsView(context: .applyToText(transcriptTexts: texts, itemId: firstId, transcriptIds: ids))
                    } else if mergeEntries.count > 1 {
                        let groups = mergeEntries.map { entry in
                            (texts: [entry.text], itemId: entry.itemId, transcriptIds: [entry.id])
                        }
                        PromptsView(context: .applyToItems(items: groups))
                    } else {
                        // Fallback: nothing to process — show an empty prompts browse view
                        PromptsView(context: .browse)
                    }
                }
        )
    }

    private var withDialogs: some View {
        withSheets
    }

    private var innerZStack: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            VStack(spacing: 0) {
                dashBar
                actionRow
                queueStatusRow
                sortRow
                itemsList
                bottomBar
            }
            .onAppear { withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { fabPulse = true } }
            .onChange(of: recorder.lastSavedItemId) { _ in vm.refreshLocalCounts() }
            .onChange(of: notesMgr.completedItemIds) { newIds in
                vm.refreshFromLocalStores()
                if autoUpload && !newIds.isEmpty { Task { await submitCollection() } }
            }
            saveToast
            if vm.isLoading || isSubmitting { LoadingOverlay() }
            recordCard
            collectionsOverlay
            collectionCards
            processBar
            submitResultCard
            createListCard
            renameCollectionCard
            deleteCollectionCard
            renameItemCard
            newItemCard
            clearConfirmCard
        }
        .onChange(of: showNewItem) { showing in
            if showing {
                newItemName = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { newItemFocused = true }
            }
        }
    }

    @ViewBuilder
    private var submitResultCard: some View {
        if showSubmitCard {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showSubmitCard = false }
                }
                .zIndex(40)
            VStack {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: submitSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(submitSuccess ? .stageNotes : .danger)
                        .shadow(color: (submitSuccess ? Color.stageNotes : Color.danger).opacity(0.7), radius: 10)
                    Text(submitSuccess ? langMgr.t("dashboard.submitted") : langMgr.t("dashboard.submitFailed"))
                        .font(.inter(16, weight: .heavy)).foregroundColor(.textPrimary)
                    Text(submitMessage ?? "")
                        .font(.inter(13)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                    if submitSuccess {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 11, weight: .semibold))
                            Text(langMgr.t("recorder.publishedTo"))
                                .font(.inter(12)) +
                            Text(langMgr.t("misc.appDomain"))
                                .font(.inter(12, weight: .bold))
                        }
                        .foregroundColor(Color.stageNotes)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.stageNotes.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.stageNotes.opacity(0.3), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showSubmitCard = false }
                    } label: {
                        Text(langMgr.t("common.ok"))
                            .font(.inter(14, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(LinearGradient(
                                colors: [Color.stageNotes.opacity(0.8), Color.stageNotes.opacity(0.6)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(24).background(Color(hex: "#081221"))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(
                    (submitSuccess ? Color.stageNotes : Color.danger).opacity(0.35), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.stageNotes.opacity(0.15), radius: 20).padding(.horizontal, 24)
                Spacer()
            }
            .transition(.scale(scale: 0.92).combined(with: .opacity)).zIndex(41)
        }
    }

    @ViewBuilder
    private var createListCard: some View {
        if showCreateListCard {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture {
                    guard !isCreatingList else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCreateListCard = false }
                }
                .zIndex(42)

            VStack {
                Spacer()
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color.brandBlue.opacity(0.25), Color.brandCyan.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 56, height: 56)
                            Image(systemName: "list.bullet.rectangle.portrait.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.brandCyan)
                        }
                        Text(langMgr.t("prompts.createList"))
                            .font(.inter(17, weight: .heavy)).foregroundColor(.textPrimary)
                        Text(isCreatingList
                             ? langMgr.t("dashboard.analyzing")
                             : createListResult != nil || createListError != nil
                               ? (createListError != nil ? langMgr.t("dashboard.somethingWrong") : langMgr.t("dashboard.itemsCreated"))
                               : pendingListImage != nil
                                 ? langMgr.t("dashboard.howProcess")
                                 : langMgr.t("dashboard.takeOrUpload"))
                            .font(.inter(12)).foregroundColor(.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24).padding(.bottom, 20).padding(.horizontal, 24)

                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

                    if isCreatingList {
                        // Processing state
                        VStack(spacing: 12) {
                            ProgressView().tint(.brandCyan).scaleEffect(1.2)
                            Text(langMgr.t("media.imageProcessing"))
                                .font(.inter(12)).foregroundColor(.textQuaternary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)

                    } else if let err = createListError {
                        // Error state
                        VStack(spacing: 16) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28)).foregroundColor(.danger)
                            Text(err)
                                .font(.inter(13)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCreateListCard = false }
                            } label: {
                                Text(langMgr.t("common.dismiss"))
                                    .font(.inter(14, weight: .bold)).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding(24)

                    } else if let result = createListResult {
                        // Success state
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.stageNotes)
                                .shadow(color: Color.stageNotes.opacity(0.5), radius: 8)
                            Text(result)
                                .font(.inter(13)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCreateListCard = false }
                            } label: {
                                Text(langMgr.t("common.done"))
                                    .font(.inter(14, weight: .bold)).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(LinearGradient(
                                        colors: [Color.stageNotes.opacity(0.8), Color.stageNotes.opacity(0.6)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding(24)

                    } else if pendingListImage == nil {
                        // Step 1: pick image source
                        VStack(spacing: 8) {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCreateListCard = false }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showCreateListCamera = true }
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle().fill(Color.brandBlue.opacity(0.18)).frame(width: 36, height: 36)
                                            Image(systemName: "camera.fill").font(.system(size: 14, weight: .semibold)).foregroundColor(.brandCyan)
                                        }
                                        Text(langMgr.t("media.takePhoto")).font(.inter(14, weight: .bold)).foregroundColor(.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.textQuaternary)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandCyan.opacity(0.2), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCreateListCard = false }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showCreateListLibrary = true }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.brandBlue.opacity(0.18)).frame(width: 36, height: 36)
                                        Image(systemName: "photo.on.rectangle").font(.system(size: 14, weight: .semibold)).foregroundColor(.brandCyan)
                                    }
                                    Text(langMgr.t("media.chooseLibrary")).font(.inter(14, weight: .bold)).foregroundColor(.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.textQuaternary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandCyan.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCreateListCard = false }
                            } label: {
                                Text(langMgr.t("common.cancel")).font(.inter(13, weight: .semibold)).foregroundColor(.textQuaternary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 16)

                    } else {
                        // Step 2: pick processing algorithm
                        VStack(spacing: 8) {
                            Text(langMgr.t("automation.selectAlgorithm"))
                                .font(.inter(11, weight: .bold)).foregroundColor(.textQuaternary)
                                .tracking(0.5).textCase(.uppercase)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)

                            Button {
                                let img = pendingListImage!
                                pendingListImage = nil
                                Task { await createListFromImage(img, useAI: true) }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.brandBlue.opacity(0.18)).frame(width: 36, height: 36)
                                        Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundColor(.brandCyan)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(langMgr.t("media.imagePrompt")).font(.inter(14, weight: .bold)).foregroundColor(.textPrimary)
                                        Text(langMgr.t("prompts.aiReads")).font(.inter(11)).foregroundColor(.textQuaternary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.textQuaternary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandCyan.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Button {
                                let img = pendingListImage!
                                pendingListImage = nil
                                Task { await createListFromImage(img, useAI: false) }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.brandBlue.opacity(0.18)).frame(width: 36, height: 36)
                                        Image(systemName: "doc.viewfinder").font(.system(size: 14, weight: .semibold)).foregroundColor(.brandCyan)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(langMgr.t("automation.ocr")).font(.inter(14, weight: .bold)).foregroundColor(.textPrimary)
                                        Text(langMgr.t("automation.fast")).font(.inter(11)).foregroundColor(.textQuaternary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.textQuaternary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandCyan.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Button {
                                pendingListImage = nil
                            } label: {
                                Text(langMgr.t("dashboard.back")).font(.inter(13, weight: .semibold)).foregroundColor(.textQuaternary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 16)
                    }
                }
                .background(Color(hex: "#081221"))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.brandCyan.opacity(0.2), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.brandBlue.opacity(0.2), radius: 24)
                .padding(.horizontal, 24)
                Spacer()
            }
            .transition(.scale(scale: 0.92).combined(with: .opacity)).zIndex(43)
        }
    }

    private var animatedContent: some View {
        AnyView(
            innerZStack
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showCollectionNew)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showCollectionMinOne)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showCollectionDuplicate)
                .animation(.spring(response: 0.3,  dampingFraction: 0.85), value: showCollections)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showRecordCard)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSubmitCard)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showCreateListCard)
        )
    }

    private var contentWithNavigation: some View {
        animatedContent
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $vm.navigateToMedia) {
                if let item = vm.navigationItem {
                    MediaListView(item: item,
                                  triggerAudioImport: vm.triggerMediaAudioImport,
                                  triggerImageImport: vm.triggerMediaImageImport)
                        .onDisappear { vm.triggerMediaAudioImport = false; vm.triggerMediaImageImport = false }
                }
            }
            .navigationDestination(isPresented: $vm.navigateToText) {
                if let item = vm.navigationItem {
                    TextListView(item: item, triggerDocImport: vm.triggerTextDocImport)
                        .onDisappear { vm.triggerTextDocImport = false }
                }
            }
            .navigationDestination(isPresented: $vm.navigateToNotes) {
                if let item = vm.navigationItem { NotesListView(item: item) }
            }
    }

    private var navStack: some View {
        NavigationStack {
            contentWithNavigation
        }
        .onChange(of: vm.navigateToMedia) { open in if !open { vm.refreshFromLocalStores() } }
        .onChange(of: vm.navigateToText)  { open in if !open { vm.refreshFromLocalStores() } }
        .onChange(of: vm.navigateToNotes) { open in if !open { vm.refreshFromLocalStores() } }
        .onChange(of: transcriptionMgr.lastSavedItemId) { _ in vm.refreshFromLocalStores() }
        .onChange(of: transcriptionMgr.transcriptSaveCounter) { _ in vm.refreshLocalCounts() }
        .onChange(of: vm.activeCollection?.id) { _ in
            if let sel = selectedItem, !vm.items.contains(where: { $0.id == sel.id }) { selectedItem = nil }
        }
    }

    // MARK: - Process Items bar

    @ViewBuilder
    private var processBar: some View {
        if showProcessItemsMode {
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: processType == .audio ? "waveform" : "text.alignleft")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(processType == .audio ? .stageMedia : .stageText)
                        Text(processItemsSelected.isEmpty
                             ? (processType == .audio ? langMgr.t("dashboard.selectWithRecordings") : langMgr.t("dashboard.selectWithTranscripts"))
                             : langMgr.t("dashboard.selectedCount").replacingOccurrences(of: "%d", with: "\(processItemsSelected.count)"))
                            .font(.inter(12, weight: .semibold))
                            .foregroundColor(.textQuaternary)
                    }
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                processItemsSelected.removeAll()
                                showProcessItemsMode = false
                            }
                        } label: {
                            Text(langMgr.t("common.cancel"))
                                .font(.inter(14, weight: .semibold)).foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            guard !processItemsSelected.isEmpty else { return }
                            if processType == .audio {
                                transcribeProcessSelected()
                            } else {
                                showProcessItemsPrompts = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: processType == .audio ? "waveform" : "sparkles")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(processItemsSelected.isEmpty
                                     ? (processType == .audio ? langMgr.t("dashboard.transcribe") : langMgr.t("dashboard.generateNotes"))
                                     : (processType == .audio
                                        ? langMgr.t("dashboard.transcribeCount").replacingOccurrences(of: "%d", with: "\(processItemsSelected.count)")
                                        : langMgr.t("dashboard.notesForCount").replacingOccurrences(of: "%d", with: "\(processItemsSelected.count)")))
                                    .font(.inter(14, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(LinearGradient(
                                colors: processType == .audio
                                    ? [Color.stageMedia.opacity(0.85), Color.stageMedia.opacity(0.55)]
                                    : [Color.brandBlue.opacity(0.8), Color.brandNavy.opacity(0.6)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .opacity(processItemsSelected.isEmpty ? 0.4 : 1.0)
                        }
                        .disabled(processItemsSelected.isEmpty)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 14).padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1), alignment: .top)
            }
            .zIndex(30)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func transcribeProcessSelected() {
        let selected = displayedItems.filter { processItemsSelected.contains($0.id) }
        let pairs: [(item: Item, results: [AudioValidationResult], recordings: [LocalRecordingEntry])] = selected.compactMap { item in
            let recs = LocalRecordingStore.shared.recordings(for: item.id)
            guard !recs.isEmpty else { return nil }
            let results = recs.enumerated().map { idx, entry -> AudioValidationResult in
                let ext = entry.fileURL.pathExtension.isEmpty ? "m4a" : entry.fileURL.pathExtension
                return AudioProcessor.validate(entry: entry, displayName: "Audio-\(item.name)-\(String(format: "%02d", idx + 1)).\(ext)")
            }
            return (item, results, recs)
        }
        if pairs.count == 1 {
            let p = pairs[0]
            TranscriptionManager.shared.transcribeRecordings(item: p.item, preparationResults: p.results, recordings: p.recordings)
        } else if pairs.count > 1 {
            TranscriptionManager.shared.transcribeQueue(pairs.map { ($0.item, $0.results, $0.recordings) })
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            processItemsSelected.removeAll()
            showProcessItemsMode = false
        }
    }

    // MARK: - Rename collection card

    @ViewBuilder
    private var renameCollectionCard: some View {
        if showRenameCollectionCard {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showRenameCollectionCard = false }
                }
                .zIndex(50)
            VStack {
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: "pencil")
                        .font(.system(size: 28))
                        .foregroundColor(.brandCyan)
                        .shadow(color: Color.brandCyan.opacity(0.6), radius: 10)

                    Text(langMgr.t("dashboard.renameCollection"))
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)

                    TextField(langMgr.t("dashboard.collectionPlaceholder"), text: $renameCollectionText)
                        .font(.inter(14))
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandCyan.opacity(0.30), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .autocorrectionDisabled()

                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showRenameCollectionCard = false }
                        } label: {
                            Text(langMgr.t("common.cancel"))
                                .font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            let trimmed = renameCollectionText.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty, let active = vm.activeCollection else { return }
                            // Check duplicate
                            if vm.collections.contains(where: { $0.id != active.id && $0.name.lowercased() == trimmed.lowercased() }) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showRenameCollectionCard = false
                                    showCollectionDuplicate = true
                                }
                                return
                            }
                            let renamed = ScrivanoCollection(id: active.id, name: trimmed)
                            LocalCollectionStore.shared.save(renamed)
                            vm.activeCollection = renamed
                            if let idx = vm.collections.firstIndex(where: { $0.id == active.id }) {
                                vm.collections[idx] = renamed
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showRenameCollectionCard = false }
                        } label: {
                            Text(langMgr.t("common.save"))
                                .font(.inter(14, weight: .heavy)).foregroundColor(.brandCyan)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(LinearGradient(colors: [Color.brandBlue.opacity(0.28), Color.brandNavy.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandBlue.opacity(0.5), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(renameCollectionText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(24).background(Color(hex: "#081221"))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.brandCyan.opacity(0.35), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.brandCyan.opacity(0.15), radius: 20)
                .padding(.horizontal, 32)
                Spacer()
            }
            .transition(.scale(scale: 0.92).combined(with: .opacity)).zIndex(51)
        }
    }

    // MARK: - Rename item card

    @ViewBuilder
    private var renameItemCard: some View {
        if renameItem != nil {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture { renameItem = nil }
                .zIndex(50)
            VStack {
                Spacer()
                VStack(spacing: 16) {
                    Text(langMgr.t("dashboard.renameItem"))
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    TextField("", text: $renameItemText)
                        .font(.inter(14))
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandCyan.opacity(0.35), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .autocorrectionDisabled()
                    HStack(spacing: 10) {
                        Button { renameItem = nil } label: {
                            Text(langMgr.t("common.cancel"))
                                .font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            let trimmed = renameItemText.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty, let item = renameItem else { return }
                            let stored = LocalStoredItem(id: item.id, name: trimmed, collection: item.collection, collectionId: item.collectionId, createdAt: item.createdAt)
                            LocalItemStore.shared.save(stored)
                            if let idx = vm.items.firstIndex(where: { $0.id == item.id }) {
                                vm.items[idx] = vm.items[idx].renamed(to: trimmed)
                            }
                            renameItem = nil
                        } label: {
                            Text(langMgr.t("common.rename"))
                                .font(.inter(14, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(LinearGradient(colors: [Color.brandBlue, Color.brandCyan], startPoint: .leading, endPoint: .trailing))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(renameItemText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(24)
                .background(Color(hex: "#081221"))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.brandCyan.opacity(0.25), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.brandCyan.opacity(0.15), radius: 20)
                .padding(.horizontal, 24)
                Spacer()
            }
            .zIndex(51)
        }
    }

    // MARK: - New item card

    @ViewBuilder
    private var newItemCard: some View {
        if showNewItem {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture { showNewItem = false; newItemName = ""; newItemDuplicateError = false }
                .zIndex(20)
            VStack {
                Spacer()
                VStack(spacing: 20) {
                    HStack {
                        Text(langMgr.t("dashboard.newItem"))
                            .font(.inter(16, weight: .heavy))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Button { showNewItem = false; newItemName = ""; newItemDuplicateError = false } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.textTertiary)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(langMgr.t("dashboard.newItem.namePlaceholder"), text: $newItemName)
                            .font(.inter(14))
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(newItemDuplicateError ? Color.red.opacity(0.7) : Color.brandCyan.opacity(0.35), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .autocorrectionDisabled()
                            .focused($newItemFocused)
                            .onChange(of: newItemName) { _ in newItemDuplicateError = false }
                            .onSubmit {
                                let t = newItemName.trimmingCharacters(in: .whitespaces)
                                guard !t.isEmpty else { return }
                                if vm.items.contains(where: { $0.name.localizedCaseInsensitiveCompare(t) == .orderedSame }) {
                                    newItemDuplicateError = true; return
                                }
                                let item = vm.createItem(name: t)
                                selectedItem = item
                                showNewItem = false; newItemName = ""; newItemDuplicateError = false
                                if recordAfterNewItem { recordAfterNewItem = false; showRecorder = true }
                            }
                        if newItemDuplicateError {
                            Text(langMgr.t("dashboard.newItem.duplicate"))
                                .font(.inter(12))
                                .foregroundColor(.red.opacity(0.85))
                                .padding(.horizontal, 4)
                        }
                    }
                    Button {
                        let t = newItemName.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        if vm.items.contains(where: { $0.name.localizedCaseInsensitiveCompare(t) == .orderedSame }) {
                            newItemDuplicateError = true; return
                        }
                        let item = vm.createItem(name: t)
                        selectedItem = item
                        showNewItem = false; newItemName = ""; newItemDuplicateError = false
                        if recordAfterNewItem { recordAfterNewItem = false; showRecorder = true }
                    } label: {
                        Text(langMgr.t("dashboard.newItem.create"))
                            .font(.inter(15, weight: .heavy))
                            .foregroundColor(newItemName.trimmingCharacters(in: .whitespaces).isEmpty ? .textQuaternary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                newItemName.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color(hex: "#1e8ae0"), Color(hex: "#1060b0"), Color(hex: "#0a4d8e")], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: newItemName.trimmingCharacters(in: .whitespaces).isEmpty ? .clear : Color.brandBlue.opacity(0.5), radius: 12, y: 6)
                    }
                    .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(24)
                .background(Color(hex: "#081221"))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.brandCyan.opacity(0.25), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.brandCyan.opacity(0.15), radius: 20)
                .padding(.horizontal, 24)
                Spacer()
            }
            .zIndex(21)
        }
    }

    // MARK: - Clear confirm card

    @ViewBuilder
    private var clearConfirmCard: some View {
        if let item = clearConfirmItem {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture { clearConfirmItem = nil }
                .zIndex(20)
            VStack {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 30)).foregroundColor(.danger)
                        .shadow(color: Color.danger.opacity(0.7), radius: 10)
                    Text(langMgr.t("dashboard.clearContent"))
                        .font(.inter(16, weight: .heavy)).foregroundColor(.textPrimary)
                    Text(langMgr.t("dashboard.clearContentMsg").replacingOccurrences(of: "%@", with: item.name))
                        .font(.inter(13)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Button { clearConfirmItem = nil } label: {
                            Text(langMgr.t("common.cancel")).font(.inter(14, weight: .semibold)).foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            clearConfirmItem = nil
                            LocalRecordingStore.shared.deleteAll(for: item.id)
                            LocalTranscriptStore.shared.deleteAll(for: item.id)
                            LocalNoteStore.shared.deleteAll(for: item.id)
                            vm.refreshLocalCounts()
                        } label: {
                            Text(langMgr.t("dashboard.clearAll")).font(.inter(14, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Color.danger.opacity(0.85)).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(24)
                .background(Color(hex: "#081221"))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.danger.opacity(0.35), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 24)
                Spacer()
            }
            .zIndex(21)
        }
    }

    // MARK: - Delete collection card

    @ViewBuilder
    private var deleteCollectionCard: some View {
        if showDeleteCollectionCard {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteCollectionCard = false }
                }
                .zIndex(50)
            VStack {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color(hex: "#ef4444"))
                        .shadow(color: Color(hex: "#ef4444").opacity(0.5), radius: 10)

                    Text(langMgr.t("dashboard.deleteCollection").replacingOccurrences(of: "%@", with: vm.activeCollection?.name ?? ""))
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(langMgr.t("dashboard.deleteItemHint"))
                        .font(.inter(13))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteCollectionCard = false }
                        } label: {
                            Text(langMgr.t("common.cancel"))
                                .font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteCollectionCard = false }
                            deleteActiveCollection()
                        } label: {
                            Text(langMgr.t("common.delete"))
                                .font(.inter(14, weight: .heavy)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Color(hex: "#ef4444").opacity(0.80))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(24).background(Color(hex: "#081221"))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(hex: "#ef4444").opacity(0.35), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color(hex: "#ef4444").opacity(0.15), radius: 20)
                .padding(.horizontal, 32)
                Spacer()
            }
            .transition(.scale(scale: 0.92).combined(with: .opacity)).zIndex(51)
        }
    }

    // MARK: - Delete active collection

    private func deleteActiveCollection() {
        guard let active = vm.activeCollection else { return }
        TrashStore.shared.trashCollection(active)
        LocalCollectionStore.shared.delete(active.id)
        LocalItemStore.shared.clearCollection(active.id)   // unlink items so they don't become orphans
        vm.collections.removeAll { $0.id == active.id }
        vm.activeCollection = vm.collections.first
        if let next = vm.activeCollection {
            UserDefaults.standard.set(next.id, forKey: "activeCollectionId")
        } else {
            UserDefaults.standard.removeObject(forKey: "activeCollectionId")
        }
        vm.refreshFromLocalStores()
    }

    // MARK: - Extracted overlay computed vars

    private func isEligible(_ item: Item) -> Bool {
        switch processType {
        case .audio:
            return (vm.localAudioCounts[item.id] ?? 0) > 0
        case .text:
            // Use the same count the card already shows — avoids false negatives when merge hasn't been built yet
            return (vm.localTextCounts[item.id] ?? 0) > 0
        }
    }

    private func itemCard(for item: Item) -> some View {
        let eligible = !showProcessItemsMode || isEligible(item)
        return ItemCardView(
            item: item,
            isSelected: selectedItem?.id == item.id,
            isCompact: viewMode == .list,
            localAudioCount: vm.localAudioCounts[item.id] ?? 0,
            localTextCount: vm.localTextCounts[item.id],
            localNoteCount: vm.localNoteCounts[item.id],
            vm: vm,
            onTap: {
                if showProcessItemsMode {
                    guard eligible else { return }
                    if processItemsSelected.contains(item.id) { processItemsSelected.remove(item.id) }
                    else { processItemsSelected.insert(item.id) }
                } else {
                    selectedItem = item
                }
            },
            onStageTap: { stage in
                guard !showProcessItemsMode else { return }
                selectedItem = item; vm.navigateTo(stage: stage, item: item)
            },
            onImportAudioTapped: {
                vm.triggerMediaAudioImport = true
                vm.navigateTo(stage: .media, item: item)
            },
            onImportImageTapped: {
                vm.triggerMediaImageImport = true
                vm.navigateTo(stage: .media, item: item)
            },
            onImportDocTapped: {
                vm.triggerTextDocImport = true
                vm.navigateTo(stage: .text, item: item)
            },
            isInProcessMode: showProcessItemsMode,
            isProcessSelected: processItemsSelected.contains(item.id),
            onRenameRequested: { renameItem = item; renameItemText = item.name },
            onClearAllRequested: { clearConfirmItem = item }
        )
        .opacity(showProcessItemsMode && !eligible ? 0.35 : 1.0)
    }

    private var itemsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(displayedItems) { item in
                    SwipeToDelete(onDelete: { vm.deleteItem(item) }, isCompact: viewMode == .list) {
                        itemCard(for: item)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8).padding(.bottom, 16)
        }
        .overlay { if vm.items.isEmpty && !vm.isLoading { emptyState } }
    }

    private var saveToast: some View {
        VStack {
            Spacer()
            if let msg = recorder.saveMessage {
                HStack(spacing: 10) {
                    Image(systemName: msg.hasPrefix("Saving") ? "waveform" : "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(msg.hasPrefix("Saving") ? .brandCyan : Color(hex: "#34d399"))
                    Text(msg).font(.inter(13, weight: .semibold)).foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 90)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: recorder.saveMessage)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var recordCard: some View {
        if showRecordCard {
            Color.black.opacity(0.65).ignoresSafeArea().onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showRecordCard = false }
            }.zIndex(20)
            VStack {
                Spacer()
                VStack(spacing: 18) {
                    Image(systemName: "mic.circle.fill").font(.system(size: 36))
                        .foregroundColor(.brandCyan).shadow(color: Color.brandCyan.opacity(0.6), radius: 10)
                    Text(langMgr.t("dashboard.record")).font(.inter(16, weight: .heavy)).foregroundColor(.textPrimary)
                    if let item = selectedItem, vm.items.contains(where: { $0.id == item.id }) {
                        Text(langMgr.t("dashboard.record.continueOn").replacingOccurrences(of: "%@", with: item.name))
                            .font(.inter(13)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                    }
                    VStack(spacing: 10) {
                        if selectedItem != nil && vm.items.contains(where: { $0.id == selectedItem?.id }) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showRecordCard = false }
                                Task { await sessionWarmTask?.value; showRecorder = true }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "waveform").font(.system(size: 13, weight: .semibold))
                                    Text(langMgr.t("dashboard.record.continue")).font(.inter(14, weight: .bold))
                                }
                                .foregroundColor(.brandCyan).frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(LinearGradient(colors: [Color.brandBlue.opacity(0.28), Color.brandNavy.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandBlue.opacity(0.5), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showRecordCard = false }
                            recordAfterNewItem = true; showNewItem = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle").font(.system(size: 13, weight: .semibold))
                                Text(langMgr.t("dashboard.record.newItem")).font(.inter(14, weight: .bold))
                            }
                            .foregroundColor(.textSecondary).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Color.white.opacity(0.07))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showRecordCard = false }
                        } label: {
                            Text(langMgr.t("common.cancel")).font(.inter(14, weight: .semibold)).foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(24).background(Color(hex: "#081221"))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.brandCyan.opacity(0.35), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.brandCyan.opacity(0.15), radius: 20).padding(.horizontal, 32)
                Spacer()
            }
            .transition(.scale(scale: 0.92).combined(with: .opacity)).zIndex(21)
        }
    }

    @ViewBuilder
    private var collectionsOverlay: some View {
        if showCollections {
            Color.black.opacity(0.65).ignoresSafeArea().onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showCollections = false }
            }.zIndex(10)
            VStack {
                CollectionTopPanel(
                    vm: vm,
                    onDismiss: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showCollections = false } },
                    onMinOneError: { showCollectionMinOne = true },
                    onActiveError: { showCollectionActiveError = true },
                    onDuplicateError: { showCollectionDuplicate = true },
                    onRequestNewCollection: { prefilled in
                        newCollectionName = prefilled
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCollectionNew = true }
                    }
                )
                Spacer()
            }
            .transition(.move(edge: .top)).zIndex(11)
        }
    }

    @ViewBuilder
    private var collectionCards: some View {
        if showCollectionNew {
            Color.black.opacity(0.65).ignoresSafeArea().zIndex(20)
            VStack {
                Spacer()
                VStack(spacing: 18) {
                    Image(systemName: "tray.full").font(.system(size: 32))
                        .foregroundColor(.brandCyan).shadow(color: Color.brandCyan.opacity(0.6), radius: 10)
                    Text(langMgr.t("dashboard.newCollection")).font(.inter(16, weight: .heavy)).foregroundColor(.textPrimary)
                    TextField(langMgr.t("dashboard.collectionPlaceholder"), text: $newCollectionName)
                        .font(.inter(14)).foregroundColor(.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.white.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandBlue.opacity(0.4), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCollectionNew = false }
                            newCollectionName = ""
                        } label: {
                            Text(langMgr.t("common.cancel")).font(.inter(14, weight: .semibold)).foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            let isDup = name.lowercased() == "my collection" || vm.collections.contains { $0.name.lowercased() == name.lowercased() }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCollectionNew = false }
                            newCollectionName = ""
                            if isDup {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCollectionDuplicate = true }
                                }
                            } else {
                                let c = ScrivanoCollection(id: UUID().uuidString, name: name)
                                LocalCollectionStore.shared.save(c); vm.collections.append(c)
                            }
                        } label: {
                            Text(langMgr.t("common.create")).font(.inter(14, weight: .bold)).foregroundColor(.brandCyan)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(LinearGradient(colors: [Color.brandBlue.opacity(0.28), Color.brandNavy.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandBlue.opacity(0.5), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(24).background(Color(hex: "#081221"))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.brandCyan.opacity(0.35), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.brandCyan.opacity(0.15), radius: 20).padding(.horizontal, 32)
                Spacer()
            }
            .transition(.scale(scale: 0.92).combined(with: .opacity)).zIndex(21)
        }
        if showCollectionMinOne {
            Color.black.opacity(0.65).ignoresSafeArea().zIndex(20)
            collectionErrorCard(icon: "tray.2.fill", title: langMgr.t("dashboard.cannotDelete"), message: langMgr.t("dashboard.minOneMsg"), accent: .brandCyan) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCollectionMinOne = false }
            }
        }
        if showCollectionActiveError {
            Color.black.opacity(0.65).ignoresSafeArea().zIndex(20)
            collectionErrorCard(icon: "pin.fill", title: langMgr.t("dashboard.cannotDeleteActive"), message: langMgr.t("dashboard.activeErrorMsg"), accent: .brandCyan) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCollectionActiveError = false }
            }
        }
        if showCollectionDuplicate {
            Color.black.opacity(0.65).ignoresSafeArea().zIndex(20)
            collectionErrorCard(icon: "exclamationmark.triangle.fill", title: langMgr.t("dashboard.duplicateName"), message: langMgr.t("dashboard.duplicateMsg"), accent: .stageText) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCollectionDuplicate = false }
            }
        }
    }

    @ViewBuilder
    private func collectionErrorCard(icon: String, title: String, message: String, accent: Color, onDismiss: @escaping () -> Void) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 32))
                    .foregroundColor(accent).shadow(color: accent.opacity(0.6), radius: 10)
                Text(title).font(.inter(16, weight: .heavy)).foregroundColor(.textPrimary)
                Text(message).font(.inter(13)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                Button { onDismiss() } label: {
                    Text(langMgr.t("recorder.gotIt")).font(.inter(14, weight: .bold)).foregroundColor(.brandCyan)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(LinearGradient(colors: [Color.brandBlue.opacity(0.28), Color.brandNavy.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandBlue.opacity(0.5), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(24).background(Color(hex: "#081221"))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(accent.opacity(0.35), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: accent.opacity(0.15), radius: 20).padding(.horizontal, 32)
            Spacer()
        }
        .transition(.scale(scale: 0.92).combined(with: .opacity)).zIndex(21)
    }

    // MARK: - Sub-views

    private var dashBar: some View {
        HStack {
            // Settings — gray rounded bubble
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17))
                    .foregroundColor(Color.white.opacity(0.75))
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer()

            // Collection pill — blue gradient
            Button { showCollections = true } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(LinearGradient(colors: [Color.brandCyan, Color.brandBlue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 8, height: 8)
                        .shadow(color: Color.brandCyan.opacity(0.9), radius: 6)
                    Text(vm.activeCollection?.name ?? (showMyCollection ? "My Collection" : (vm.collections.first?.name ?? "Collections")))
                        .font(.inter(14, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.brandCyan.opacity(0.7))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [Color.brandBlue.opacity(0.24), Color.brandNavy.opacity(0.18)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(Capsule().stroke(Color.brandBlue.opacity(0.45), lineWidth: 1))
                .clipShape(Capsule())
                .shadow(color: Color.brandBlue.opacity(0.1), radius: 16)
            }

            Spacer()

            // Dots — gray rounded bubble dropdown
            Menu {
                Section(langMgr.t("dashboard.section.process")) {
                    Button {
                        processType = .text
                        processItemsSelected.removeAll()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showProcessItemsMode = true }
                    } label: { Label(langMgr.t("dashboard.process.text"), systemImage: "text.alignleft") }
                    Button {
                        processType = .audio
                        processItemsSelected.removeAll()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showProcessItemsMode = true }
                    } label: { Label(langMgr.t("dashboard.processAudio"), systemImage: "mic.fill") }
                }
                Section(langMgr.t("dashboard.section.collection")) {
                    Button { showCollectionNew = true } label: { Label(langMgr.t("dashboard.newCollection"), systemImage: "folder.badge.plus") }
                    Button {
                        renameCollectionText = vm.activeCollection?.name ?? ""
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showRenameCollectionCard = true }
                    } label: { Label(langMgr.t("dashboard.renameCollection"), systemImage: "pencil") }
                    Button(role: .destructive) {
                        guard vm.activeCollection != nil else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCollectionActiveError = true }
                            return
                        }
                        guard vm.collections.count > 1 else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCollectionMinOne = true }
                            return
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteCollectionCard = true }
                    } label: { Label(langMgr.t("dashboard.deleteCollectionMenu"), systemImage: "trash") }
                }
                Section(langMgr.t("dashboard.section.utilities")) {
                    Button { showPromptDatabase = true } label: { Label(langMgr.t("settings.promptDatabase.title"), systemImage: "cylinder.split.1x2") }
                    Button {
                        createListResult = nil; createListError = nil; pendingListImage = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCreateListCard = true }
                        }
                    } label: { Label(langMgr.t("prompts.createList"), systemImage: "list.bullet.rectangle") }
                }
            } label: {
                Text("···")
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(Color.white.opacity(0.75))
                    .tracking(1)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .padding(.top, 6)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            if recorder.isMinimized && (recorder.isRecording || recorder.isPaused) {
                // ── Mini recording controls ──
                HStack(alignment: .center, spacing: 0) {
                    // Pause / Play (left)
                    Button { recorder.togglePause() } label: {
                        Image(recorder.isRecording && !recorder.isPaused ? "recorderPause" : "recorderPlay")
                            .resizable().scaledToFit()
                            .frame(width: 52, height: 52)
                    }
                    .frame(width: 72)

                    // Center: maximize arrow + timer + "Recording · name"
                    VStack(spacing: 3) {
                        Button {
                            recorder.isMinimized = false
                            showRecorder = true
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.brandCyan)
                                .frame(width: 24, height: 24)
                                .background(Color.white.opacity(0.07))
                                .clipShape(Circle())
                        }
                        Text(recorder.formattedTime)
                            .font(.system(size: 18, weight: .thin, design: .monospaced))
                            .foregroundColor(Color(hex: "#E6E6E6"))
                        HStack(spacing: 5) {
                            Text(recorder.isPaused ? langMgr.t("dashboard.paused") : langMgr.t("dashboard.recording"))
                                .foregroundColor(recorder.isPaused ? .textQuaternary : Color(hex: "#ef4444"))
                            Text(recorder.currentItemName)
                                .foregroundColor(.textSecondary)
                                .lineLimit(1)
                        }
                        .font(.inter(11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)

                    // Stop (right)
                    Button { recorder.stopAndSave() } label: {
                        Image("recorderStop")
                            .resizable().scaledToFit()
                            .frame(width: 52, height: 52)
                    }
                    .frame(width: 72)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            } else {
                // ── Normal FAB ──
                HStack {
                    Spacer()
                    Button {
                        sessionWarmTask = Task.detached(priority: .userInitiated) {
                            let s = AVAudioSession.sharedInstance()
                            try? s.setCategory(.record, mode: .default)
                            try? s.setActive(true)
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showRecordCard = true
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color(hex: "#081526"), Color(hex: "#030c1a")],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 66, height: 66)
                                .overlay(Circle().stroke(Color.brandCyan.opacity(0.45), lineWidth: 2))
                                .shadow(color: Color.brandCyan.opacity(0.5), radius: 10)
                            Image("ScrivanoLogo")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 66, height: 66)
                                .clipShape(Circle())
                                .shadow(color: Color.brandCyan.opacity(0.8), radius: 6)
                        }
                        .frame(width: 66, height: 66)
                    }
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.bottom, 6)
            }
        }
        .background(Color(hex: "#060e1e").opacity(0.97).ignoresSafeArea(edges: .bottom))
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            // New Item — primary blue style
            Button { recordAfterNewItem = false; showNewItem = true } label: {
                Text(langMgr.t("misc.newItemShort"))
                    .font(.inter(12, weight: .bold))
                    .foregroundColor(.brandCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: [Color.brandBlue.opacity(0.28), Color.brandNavy.opacity(0.20)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandBlue.opacity(0.5), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Clear Task — shows queue depth when jobs are waiting
            Button {
                TranscriptionManager.shared.cancelAll()
            } label: {
                HStack(spacing: 5) {
                    Text(langMgr.t("dashboard.clearTask"))
                    if taskQueue.pendingCount > 0 {
                        Text("+\(taskQueue.pendingCount)")
                            .font(.inter(10, weight: .heavy))
                            .foregroundColor(Color(hex: "#f59e0b"))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(hex: "#f59e0b").opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .font(.inter(12, weight: .bold))
                .foregroundColor(Color.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Submit — gray style
            Button { Task { await submitCollection() } } label: {
                Text(langMgr.t("dashboard.submit"))
                .font(.inter(12, weight: .bold))
                .foregroundColor(Color.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Queue status strip
    @ViewBuilder
    private var queueStatusRow: some View {
        if taskQueue.isProcessing && !showProcessItemsMode {
            HStack(spacing: 8) {
                // Animated activity dot
                Circle()
                    .fill(Color.brandCyan)
                    .frame(width: 6, height: 6)
                    .opacity(fabPulse ? 1.0 : 0.3)

                // What's running now
                if let name = transcriptionMgr.transcribingItemName {
                    Text(transcriptionMgr.transcribingStatus.isEmpty
                         ? langMgr.t("dashboard.processingItem").replacingOccurrences(of: "%@", with: name)
                         : transcriptionMgr.transcribingStatus)
                        .lineLimit(1)
                } else if let noteId = notesMgr.processingItemId {
                    let noteName = vm.items.first { $0.id == noteId }?.name ?? noteId
                    Text(langMgr.t("dashboard.generatingNote").replacingOccurrences(of: "%@", with: noteName))
                        .lineLimit(1)
                } else {
                    Text(langMgr.t("common.processing"))
                }

                Spacer()

                // How many are waiting behind
                if taskQueue.pendingCount > 0 {
                    Text("+\(taskQueue.pendingCount) \(langMgr.t("misc.pendingQueue"))")
                        .font(.inter(10, weight: .heavy))
                        .foregroundColor(Color(hex: "#f59e0b"))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: "#f59e0b").opacity(0.12))
                        .overlay(Capsule().stroke(Color(hex: "#f59e0b").opacity(0.25), lineWidth: 1))
                        .clipShape(Capsule())
                }
            }
            .font(.inter(11, weight: .semibold))
            .foregroundColor(.textTertiary)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(Color.brandBlue.opacity(0.07))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.brandCyan.opacity(0.10)).frame(height: 1)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: taskQueue.isProcessing)
        }
    }

    private var sortRow: some View {
        HStack {
            // Items count + current sort label
            HStack(spacing: 0) {
                Text("\(vm.items.count)")
                    .font(.inter(13, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.82))
                Text(sortOrder == .insertion
                     ? " \(langMgr.t("dashboard.itemCount"))"
                     : sortOrder == .az
                       ? " \(langMgr.t("dashboard.itemCount"))\(langMgr.t("dashboard.sortAZSuffix"))"
                       : " \(langMgr.t("dashboard.itemCount"))\(langMgr.t("dashboard.sortZASuffix"))")
                    .font(.inter(13, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.5))
            }

            Spacer()

            HStack(spacing: 8) {
                // Sort button — cycles insertion → A-Z → Z-A → insertion
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        switch sortOrder {
                        case .insertion: sortOrder = .az
                        case .az:        sortOrder = .za
                        case .za:        sortOrder = .insertion
                        }
                    }
                } label: {
                    Text(langMgr.t("dashboard.sortBy"))
                        .font(.inter(11, weight: .bold))
                        .foregroundColor(sortOrder == .insertion ? .brandCyan : .white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(sortOrder == .insertion ? Color.clear : Color.brandBlue.opacity(0.25))
                        .overlay(Capsule().stroke(sortOrder == .insertion ? Color.clear : Color.brandCyan.opacity(0.4), lineWidth: 1))
                        .clipShape(Capsule())
                }

                // View toggle
                HStack(spacing: 0) {
                    ForEach([ViewMode.card, .list], id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { viewMode = mode }
                        } label: {
                            Text(mode == .card ? "▤" : "≡")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(viewMode == mode ? .brandCyan : .textTertiary)
                                .frame(width: 28, height: 26)
                                .background(viewMode == mode ? Color.brandBlue.opacity(0.22) : .clear)
                        }
                    }
                }
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.textQuaternary)
            Text(langMgr.t("dashboard.noItems"))
                .font(.inter(16, weight: .bold))
                .foregroundColor(.textTertiary)
            Text(langMgr.t("dashboard.noItems.hint"))
                .font(.inter(12))
                .foregroundColor(.textQuaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - Task 9: Submit collection
    private func submitCollection() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let collName = vm.activeCollection?.name ?? "All Items"
        let isoDate = ISO8601DateFormatter().string(from: Date())

        let uploadItems = vm.items.map { item in
            CollectionUploadItem(
                itemname: item.name,
                transcriptions: (item.transcripts ?? []).map { t in
                    CollectionUploadTranscription(
                        transcriptionname: t.label,
                        transcriptiontext: t.text,
                        notes: []
                    )
                },
                notes: (item.notes ?? []).map { n in
                    CollectionUploadNote(notename: n.label, notetext: n.text)
                }
            )
        }

        let payload = CollectionUploadPayload(
            dictionaryname: collName,
            dictionarytime: isoDate,
            items: uploadItems
        )

        do {
            try await APIClient.shared.submitCollection(payload: payload)
            submitMessage = langMgr.t("dashboard.submitSuccess").replacingOccurrences(of: "%@", with: collName)
            submitSuccess = true
        } catch {
            submitMessage = error.localizedDescription
            submitSuccess = false
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showSubmitCard = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showSubmitCard = false }
        }
    }

    // MARK: - Task 10: Create list from image
    private func createListFromImage(_ image: UIImage, useAI: Bool) async {
        createListResult = nil
        createListError = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isCreatingList = true }
        defer { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isCreatingList = false } }

        let names: [String]

        if useAI {
            // Step 1: OCR the image locally
            guard let cgImage = image.cgImage else {
                createListError = "Failed to read image."; return
            }
            let ocrText = await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                return (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
            }.value

            guard !ocrText.isEmpty else {
                createListError = "Could not read any text from the image."; return
            }

            // Step 2: Find "Image list" prompt
            let prompts: [Prompt]
            do {
                let res = try await APIClient.shared.request(path: "/api/prompts", responseType: PromptsResponse.self)
                prompts = res.success ? res.data : []
            } catch { prompts = [] }

            guard let prompt = prompts.first(where: { $0.name.lowercased() == "image list" }) else {
                createListError = "\"Image list\" prompt not found in your prompt database."
                return
            }

            // Step 3: Send OCR text to /api/notes/generate with the Image list prompt
            struct NoteBody: Encodable {
                let transcript: String
                let promptId: String
                enum CodingKeys: String, CodingKey { case transcript; case promptId = "prompt_id" }
            }
            struct NoteRes: Decodable {
                let success: Bool
                let taskId: String?
                enum CodingKeys: String, CodingKey { case success; case taskId = "task_id" }
            }
            do {
                let res = try await APIClient.shared.request(
                    path: "/api/notes/generate", method: "POST",
                    body: NoteBody(transcript: ocrText, promptId: prompt.id),
                    responseType: NoteRes.self
                )
                guard let taskId = res.taskId else {
                    createListError = "Failed to start note generation."; return
                }
                // Step 4: Poll for result
                var resultText: String? = nil
                for _ in 0..<60 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if let poll = try? await APIClient.shared.pollNoteResult(taskId: taskId) {
                        if poll.status == "completed" { resultText = poll.note; break }
                        if poll.status == "failed" { createListError = "Processing failed."; return }
                    }
                }
                guard let raw = resultText, !raw.isEmpty else { createListError = "Timed out waiting for result."; return }
                // Step 5: Parse comma-separated result
                names = raw
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } catch {
                createListError = error.localizedDescription; return
            }
        } else {
            // Vision OCR — fully local
            guard let cgImage = image.cgImage else {
                createListError = "Failed to read image."; return
            }
            names = await Task.detached(priority: .userInitiated) {
                var lines: [String] = []
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                guard let observations = request.results else { return [] }
                for obs in observations {
                    if let top = obs.topCandidates(1).first {
                        let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty { lines.append(text) }
                    }
                }
                return lines.flatMap { line in
                    line.contains(",")
                        ? line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        : [line]
                }
            }.value
        }

        if names.isEmpty { createListError = "No items found. Try a clearer photo."; return }
        for name in names { _ = vm.createItem(name: name) }
        createListResult = "Created \(names.count) item\(names.count == 1 ? "" : "s") in \(vm.activeCollection?.name ?? "My Collection")."
    }
}

// MARK: - ViewModel
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var collections: [ScrivanoCollection] = []
    @Published var activeCollection: ScrivanoCollection?
    @Published var isLoading = false
    @Published var error: String?
    /// Local recording counts per itemId — updated instantly when a recording is saved.
    @Published var localAudioCounts: [String: Int] = [:]
    /// Local transcript counts per itemId — excludes the auto-merge file.
    @Published var localTextCounts: [String: Int] = [:]
    /// Local note counts per itemId — updated after generation completes.
    @Published var localNoteCounts: [String: Int] = [:]

    // Navigation
    @Published var navigateToMedia = false
    @Published var navigateToText = false
    @Published var navigateToNotes = false
    @Published var navigationItem: Item?
    @Published var triggerMediaAudioImport = false
    @Published var triggerMediaImageImport = false
    @Published var triggerTextDocImport = false

    enum Stage { case media, text, notes }

    let api = APIClient.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await loadItems()
    }

    func loadItems() async {
        refreshFromLocalStores()
    }

    func refreshFromLocalStores() {
        loadCollections()
        restoreActiveCollectionIfNeeded()
        let all = LocalItemStore.shared.all().map { buildLocalItem($0) }
        if let collId = activeCollection?.id {
            items = all.filter { $0.collectionId == collId }
        } else {
            items = all.filter { $0.collectionId == nil }
        }
        refreshLocalCounts()
    }

    /// Ensures an active collection is always set. Restores the last saved one,
    /// or falls back to My Collection (if visible) or the first real collection.
    private func restoreActiveCollectionIfNeeded() {
        let showMyColl = UserDefaults.standard.object(forKey: "showMyCollection") as? Bool ?? true
        // If already have a valid active collection, keep it
        if let active = activeCollection {
            if collections.contains(where: { $0.id == active.id }) { return }
            // Active collection was deleted — fall through to re-select
        }
        // Try to restore the last persisted selection
        if let savedId = UserDefaults.standard.string(forKey: "activeCollectionId"),
           let found = collections.first(where: { $0.id == savedId }) {
            activeCollection = found
            return
        }
        // My Collection was the last active (savedId == nil or not found) — keep nil if it's visible
        if showMyColl && UserDefaults.standard.object(forKey: "activeCollectionId") == nil {
            return  // nil = My Collection, and it's visible
        }
        // Otherwise pick first real collection
        activeCollection = collections.first
    }

    func buildLocalItem(_ stored: LocalStoredItem) -> Item {
        let transcripts = LocalTranscriptStore.shared.transcripts(for: stored.id).map { $0.summary }
        let notes = LocalNoteStore.shared.notes(for: stored.id).map { $0.summary }
        return Item(
            id: stored.id,
            name: stored.name,
            collection: stored.collection,
            collectionId: stored.collectionId,
            createdAt: stored.createdAt,
            transcripts: transcripts,
            notes: notes
        )
    }

    func loadCollections() {
        collections = LocalCollectionStore.shared.all().sorted { $0.name < $1.name }
    }

    func navigateTo(stage: DashboardViewModel.Stage, item: Item) {
        navigationItem = item
        switch stage {
        case .media:  navigateToMedia = true
        case .text:   navigateToText = true
        case .notes:  navigateToNotes = true
        }
    }

    /// Called after a recording is saved — increments the media count instantly.
    func recordingSaved(itemId: String) {
        localAudioCounts[itemId, default: 0] += 1
    }

    /// Reloads all local counts from the store (called on load and after any change).
    func refreshLocalCounts() {
        for item in items {
            let audio = LocalRecordingStore.shared.count(for: item.id)
            let images = LocalImageStore.shared.count(for: item.id)
            localAudioCounts[item.id] = audio + images
            localTextCounts[item.id] = LocalTranscriptStore.shared.count(for: item.id)
            localNoteCounts[item.id] = LocalNoteStore.shared.count(for: item.id)
        }
    }

    func createCollection() {}

    func selectCollection(_ c: ScrivanoCollection?) {
        activeCollection = c
        if let c {
            UserDefaults.standard.set(c.id, forKey: "activeCollectionId")
        } else {
            UserDefaults.standard.removeObject(forKey: "activeCollectionId")
        }
        refreshFromLocalStores()
    }
}

