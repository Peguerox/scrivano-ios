import SwiftUI
import UniformTypeIdentifiers

struct TextFile: Identifiable, Codable {
    let id: String
    let name: String
    let size: String
    let createdAt: String
    let content: String?
    let isMerged: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, size, content
        case createdAt = "created_at"
        case isMerged = "is_merged"
    }
}

// MARK: - TextListView

struct TextListView: View {
    let item: Item
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var notesMgr = NoteGenerationManager.shared
    @State private var transcripts: [TranscriptSummary] = []
    @State private var selected = Set<String>()
    @State private var showPrompts = false
    @State private var viewerTranscript: TranscriptSummary? = nil

    // Import
    @State private var showDocImporter = false
    @State private var isImporting = false
    @State private var importError: String? = nil

    // Merge
    @State private var showMergeToast = false
    @State private var isMerging = false

    // Process confirm
    @State private var showProcessConfirm = false

    // Bulk action selection mode
    enum BulkAction { case move, delete, merge }
    @State private var pendingAction: BulkAction? = nil
    @State private var showBulkMove = false
    @State private var showDeleteConfirm = false

    private var inSelectionMode: Bool { pendingAction != nil }

    private var allTextIds: [String] { transcripts.map(\.id) }
    private var selectedTranscripts: [TranscriptSummary] { transcripts.filter { selected.contains($0.id) } }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                SubScreenBar(title: "Text", accentColor: .stageText, onBack: { dismiss() })
                    .overlay(alignment: .trailing) {
                        Menu {
                            Button { showDocImporter = true } label: {
                                Label("Import Document", systemImage: "doc.badge.plus")
                            }
                            Button {
                                selected.removeAll()
                                pendingAction = .merge
                            } label: {
                                Label("Merge Texts", systemImage: "text.append")
                            }
                            .disabled(transcripts.filter { !$0.isMerge }.count < 2)
                            Button {
                                selected.removeAll()
                                pendingAction = .move
                            } label: {
                                Label("Move", systemImage: "folder")
                            }
                            .disabled(transcripts.filter { !$0.isMerge }.isEmpty)
                            Button(role: .destructive) {
                                selected.removeAll()
                                pendingAction = .delete
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(transcripts.filter { !$0.isMerge }.isEmpty)
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
                        .padding(.trailing, 18)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.stageText.opacity(0.4)).frame(height: 1)
                    }

                // File list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(transcripts.enumerated()), id: \.element.id) { idx, t in
                            if t.isMerge {
                                // Merge file is not swipe-deletable
                                LocalTextRow(
                                    transcript: t,
                                    index: idx + 1,
                                    itemName: item.name,
                                    itemId: item.id,
                                    isSelected: selected.contains(t.id),
                                    isProcessing: notesMgr.processingTranscriptIds.contains(t.id),
                                    isQueued: notesMgr.queuedTranscriptIds.contains(t.id),
                                    isProcessed: notesMgr.completedTranscriptIds.contains(t.id),
                                    onSelect: { toggleSelect(t.id) },
                                    onView: { viewerTranscript = t },
                                    onDelete: {},
                                    onDraftNote: {}
                                )
                            } else {
                                SwipeToDelete(onDelete: { deleteTranscript(t) }) {
                                    LocalTextRow(
                                        transcript: t,
                                        index: idx + 1,
                                        itemName: item.name,
                                        itemId: item.id,
                                        isSelected: selected.contains(t.id),
                                        isProcessing: notesMgr.processingTranscriptIds.contains(t.id),
                                        isQueued: notesMgr.queuedTranscriptIds.contains(t.id),
                                        isProcessed: notesMgr.completedTranscriptIds.contains(t.id),
                                        onSelect: { toggleSelect(t.id) },
                                        onView: { viewerTranscript = t },
                                        onDelete: { deleteTranscript(t) },
                                        onDraftNote: {},
                                        onRenamed: { rebuildAndReload() },
                                        onMoved: { rebuildAndReload() }
                                    )
                                }
                            }
                        }
                    }
                }
                .overlay {
                    if transcripts.filter({ !$0.isMerge }).isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 40))
                                .foregroundColor(.textQuaternary)
                            Text("No text yet")
                                .font(.inter(16, weight: .bold))
                                .foregroundColor(.textTertiary)
                            Text("Transcribe audio files to generate text")
                                .font(.inter(12))
                                .foregroundColor(.textQuaternary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }
                }
                .onAppear {
                    LocalTranscriptStore.shared.rebuildMerge(for: item.id, itemName: item.name)
                    reloadTranscripts()
                }

                // Bottom bar
                VStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

                    if inSelectionMode {
                        // Selection mode bar
                        VStack(spacing: 6) {
                            Text({
                                switch pendingAction {
                                case .delete: return "Select files to delete"
                                case .merge:  return "Select files to merge"
                                default:      return "Select files to move"
                                }
                            }())
                            .font(.inter(12, weight: .semibold))
                            .foregroundColor(.textTertiary)
                            .padding(.top, 10)

                            HStack(spacing: 10) {
                                Button {
                                    selected.removeAll()
                                    pendingAction = nil
                                } label: {
                                    Text("Cancel")
                                        .font(.inter(14, weight: .semibold))
                                        .foregroundColor(.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Color.white.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }

                                let actionColor: Color = {
                                    switch pendingAction {
                                    case .delete: return .danger
                                    case .merge:  return .stageText
                                    default:      return .brandBlue
                                    }
                                }()
                                let actionIcon: String = {
                                    switch pendingAction {
                                    case .delete: return "trash"
                                    case .merge:  return "text.append"
                                    default:      return "folder"
                                    }
                                }()
                                let actionLabel: String = {
                                    switch pendingAction {
                                    case .delete: return "Delete \(selected.count)"
                                    case .merge:  return "Merge \(selected.count)"
                                    default:      return "Move \(selected.count)"
                                    }
                                }()

                                Button {
                                    switch pendingAction {
                                    case .delete: showDeleteConfirm = true
                                    case .move:   showBulkMove = true
                                    case .merge:
                                        Task { await mergeSelected() }
                                    case .none: break
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: actionIcon).font(.system(size: 13, weight: .bold))
                                        Text(actionLabel).font(.inter(14, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(actionColor.opacity(selected.count < (pendingAction == .merge ? 2 : 1) ? 0.3 : 0.8))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .disabled(selected.count < (pendingAction == .merge ? 2 : 1))
                            }

                            Text("\(selected.count) file\(selected.count == 1 ? "" : "s") selected")
                                .font(.inter(11))
                                .foregroundColor(.textQuaternary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        // Normal bar
                        if showMergeToast {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13)).foregroundColor(Color(hex: "#34d399"))
                                Text("Texts merged and saved!")
                                    .font(.inter(11)).foregroundColor(Color(hex: "#34d399"))
                            }
                            .padding(.horizontal, 18).padding(.top, 8)
                            .transition(.opacity)
                        } else if let err = importError {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13)).foregroundColor(.danger)
                                Text(err).font(.inter(11)).foregroundColor(.danger).lineLimit(1)
                            }
                            .padding(.horizontal, 18).padding(.top, 8)
                        }

                        VStack(spacing: 6) {
                            Button {
                                // Use current selection; only default to merge if nothing selected
                                if selected.isEmpty {
                                    if let merge = transcripts.first(where: { $0.isMerge }) {
                                        selected = [merge.id]
                                    }
                                }
                                if !transcripts.isEmpty {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showProcessConfirm = true
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "bolt.fill").font(.system(size: 14, weight: .bold))
                                    Text("Process Text").font(.inter(15, weight: .heavy))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(LinearGradient(
                                    colors: [Color.stageText.opacity(0.25), Color.stageText.opacity(0.10)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.stageText.opacity(0.40), lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .opacity(allTextIds.isEmpty ? 0.35 : 1.0)
                            }
                            .disabled(allTextIds.isEmpty)

                            Text(selected.isEmpty
                                 ? "Tap to select all and process"
                                 : "\(selected.count) file\(selected.count == 1 ? "" : "s") selected")
                                .font(.inter(11))
                                .foregroundColor(.textQuaternary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                }
                .background(Color.phoneBg)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: inSelectionMode)
            }

            // Process confirm card
            if showProcessConfirm {
                Color.black.opacity(0.65).ignoresSafeArea().zIndex(10)
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.stageText)
                            .shadow(color: Color.stageText.opacity(0.7), radius: 10)

                        Text("Process Text")
                            .font(.inter(16, weight: .heavy))
                            .foregroundColor(.textPrimary)

                        Text("Continue with \(selected.count) selected file\(selected.count == 1 ? "" : "s")?")
                            .font(.inter(13))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(selectedTranscripts, id: \.id) { t in
                                    processFileRow(name: t.label, id: t.id)
                                }
                            }
                        }
                        .frame(maxHeight: 160)

                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showProcessConfirm = false
                                }
                            } label: {
                                Text("Cancel")
                                    .font(.inter(14, weight: .semibold))
                                    .foregroundColor(.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.white.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showProcessConfirm = false
                                }
                                showPrompts = true
                            } label: {
                                Text("Continue")
                                    .font(.inter(14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.stageText.opacity(0.8), Color.stageText.opacity(0.6)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(24)
                    .background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.stageText.opacity(0.35), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.stageText.opacity(0.15), radius: 20)
                    .padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(11)
            }

            // Delete confirm card
            if showDeleteConfirm {
                Color.black.opacity(0.65).ignoresSafeArea().zIndex(12)
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "trash")
                            .font(.system(size: 30))
                            .foregroundColor(.danger)
                            .shadow(color: Color.danger.opacity(0.7), radius: 10)

                        Text("Delete Files")
                            .font(.inter(16, weight: .heavy))
                            .foregroundColor(.textPrimary)

                        Text("Permanently delete \(selected.count) file\(selected.count == 1 ? "" : "s")?")
                            .font(.inter(13))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(Array(selected), id: \.self) { id in
                                    if let t = transcripts.first(where: { $0.id == id }) {
                                        processFileRow(name: t.label, id: t.id)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 160)

                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteConfirm = false }
                            } label: {
                                Text("Cancel")
                                    .font(.inter(14, weight: .semibold))
                                    .foregroundColor(.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.white.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteConfirm = false }
                                for id in selected {
                                    if let entry = LocalTranscriptStore.shared.entries.first(where: { $0.id == id }) {
                                        let iName = LocalItemStore.shared.all().first(where: { $0.id == entry.itemId })?.name ?? entry.itemId
                                        TrashStore.shared.trashTranscript(entry, itemName: iName)
                                    }
                                    LocalTranscriptStore.shared.delete(id: id)
                                }
                                selected.removeAll()
                                pendingAction = nil
                                rebuildAndReload()
                            } label: {
                                Text("Delete")
                                    .font(.inter(14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.danger.opacity(0.85))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(24)
                    .background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.danger.opacity(0.35), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.danger.opacity(0.15), radius: 20)
                    .padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(13)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showProcessConfirm)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDeleteConfirm)
        .animation(.easeInOut(duration: 0.3), value: showMergeToast)
        .navigationBarHidden(true)
        .fileImporter(
            isPresented: $showDocImporter,
            allowedContentTypes: [
                .pdf,
                .plainText,                                          // txt
                .rtf,
                .html,
                UTType(filenameExtension: "doc")  ?? .data,
                UTType(filenameExtension: "docx") ?? .data,
                UTType(filenameExtension: "xlsx") ?? .data,
                UTType(filenameExtension: "csv")  ?? .data,
                UTType(filenameExtension: "odt")  ?? .data,
            ],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleDocumentImport(result: result) }
        }
        .fullScreenCover(isPresented: $showPrompts) {
            let texts = selectedTranscripts.map { $0.text }
            let ids   = selectedTranscripts.map { $0.id }
            PromptsView(context: .applyToText(transcriptTexts: texts, itemId: item.id, transcriptIds: ids))
        }
        .fullScreenCover(item: $viewerTranscript) { t in
            TranscriptViewerView(transcript: t) { newText in
                saveTranscriptEdit(id: t.id, newText: newText)
            }
        }
        .sheet(isPresented: $showBulkMove) {
            BulkMoveTranscriptSheet(
                ids: Array(selected.filter { id in transcripts.first(where: { $0.id == id })?.isMerge == false }),
                currentItemId: item.id
            ) {
                selected.removeAll()
                pendingAction = nil
                rebuildAndReload()
            }
        }
    }

    // MARK: - Helpers

    private func reloadTranscripts() {
        let entries = LocalTranscriptStore.shared.transcripts(for: item.id)
        // Regular files oldest→newest (01 at top), merge always last
        let sorted = entries.sorted { a, b in
            if a.isMerge != b.isMerge { return !a.isMerge }
            return a.createdAt < b.createdAt
        }
        transcripts = sorted.map { $0.summary }
    }

    private func rebuildAndReload() {
        LocalTranscriptStore.shared.rebuildMerge(for: item.id, itemName: item.name)
        reloadTranscripts()
    }

    private func toggleSelect(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func deleteTranscript(_ t: TranscriptSummary) {
        if let entry = LocalTranscriptStore.shared.entries.first(where: { $0.id == t.id }) {
            let iName = LocalItemStore.shared.all().first(where: { $0.id == entry.itemId })?.name ?? entry.itemId
            TrashStore.shared.trashTranscript(entry, itemName: iName)
        }
        selected.remove(t.id)
        LocalTranscriptStore.shared.delete(id: t.id)
        rebuildAndReload()
    }

    private func saveTranscriptEdit(id: String, newText: String) {
        guard let entry = LocalTranscriptStore.shared.entries.first(where: { $0.id == id }) else { return }
        LocalTranscriptStore.shared.update(LocalTranscriptEntry(
            id: entry.id, itemId: entry.itemId, label: entry.label,
            text: newText, durationSeconds: entry.durationSeconds,
            createdAt: entry.createdAt, isMerge: entry.isMerge
        ))
        rebuildAndReload()
    }

    @ViewBuilder
    private func processFileRow(name: String, id: String) -> some View {
        let isMergeRow = name.hasPrefix("Merge-")
        let rowColor: Color = isMergeRow ? .brandCyan : .stageText
        let icon = isMergeRow ? "doc.on.doc.fill" : "doc.text.fill"
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(rowColor)
                .frame(width: 28, height: 28)
                .background(rowColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text(name)
                .font(.inter(12, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
            Spacer()
            Button { toggleSelect(id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - Document import

    private func handleDocumentImport(result: Result<[URL], Error>) async {
        isImporting = true
        importError = nil
        defer { isImporting = false }

        switch result {
        case .failure(let err):
            importError = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try await APIClient.shared.uploadDocument(fileURL: url)
                let idx = LocalTranscriptStore.shared.count(for: item.id)
                LocalTranscriptStore.shared.add(LocalTranscriptEntry(
                    id: UUID().uuidString,
                    itemId: item.id,
                    label: "transcript-\(item.name)-\(String(format: "%02d", idx + 1)).txt",
                    text: text,
                    durationSeconds: nil,
                    createdAt: Date()
                ))
                rebuildAndReload()
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    // MARK: - Merge selected

    private func mergeSelected() async {
        isMerging = true
        defer { isMerging = false }

        // Preserve display order (transcripts array is already sorted oldest→newest)
        let toMerge = transcripts
            .filter { !$0.isMerge && selected.contains($0.id) }
        guard toMerge.count >= 2 else { return }

        let mergedText = toMerge.map { $0.text }.joined(separator: "\n")

        // Create a new numbered file: Merge-{itemName}-01.txt, -02.txt, etc.
        let idx = LocalTranscriptStore.shared.count(for: item.id) + 1
        LocalTranscriptStore.shared.add(LocalTranscriptEntry(
            id: UUID().uuidString,
            itemId: item.id,
            label: "Merge-\(item.name)-\(String(format: "%02d", idx)).txt",
            text: mergedText,
            durationSeconds: nil,
            createdAt: Date()
        ))

        selected.removeAll()
        pendingAction = nil
        rebuildAndReload()
        withAnimation { showMergeToast = true }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        withAnimation { showMergeToast = false }
    }
}

// MARK: - Local text row

struct LocalTextRow: View {
    let transcript: TranscriptSummary
    let index: Int
    let itemName: String
    let itemId: String
    var isSelected: Bool
    var isProcessing: Bool = false
    var isQueued: Bool = false
    var isProcessed: Bool = false
    var onSelect: () -> Void
    var onView: () -> Void
    var onDelete: () -> Void = {}
    var onDraftNote: () -> Void = {}
    var onRenamed: () -> Void = {}
    var onMoved: () -> Void = {}

    @State private var showRename = false
    @State private var showMoreInfo = false
    @State private var showMoveTo = false
    @State private var showDraftPrompts = false
    @State private var hourglassFlipped = false

    private var wordCount: String {
        let words = transcript.text.split(separator: " ").count
        return words == 1 ? "1 word" : "\(words) words"
    }

    private var rowColor: Color { transcript.isMerge ? .brandCyan : .stageText }

    var body: some View {
        HStack(spacing: 14) {
            // Left icon circle
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [rowColor.opacity(0.5), rowColor.opacity(0.25)],
                        center: .center, startRadius: 0, endRadius: 24
                    ))
                    .frame(width: 48, height: 48)
                Image(systemName: transcript.isMerge ? "doc.on.doc.fill" : "doc.text.fill")
                    .font(.system(size: 18))
                    .foregroundColor(rowColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(transcript.label)
                        .font(.inter(13, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if transcript.isMerge {
                        Text("AUTO")
                            .font(.inter(8, weight: .heavy))
                            .tracking(0.5)
                            .foregroundColor(.brandCyan.opacity(0.8))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.brandCyan.opacity(0.12))
                            .overlay(Capsule().stroke(Color.brandCyan.opacity(0.25), lineWidth: 1))
                            .clipShape(Capsule())
                    }
                }
                Text(transcript.duration.isEmpty ? wordCount : "\(transcript.duration) · \(wordCount)")
                    .font(.inter(10))
                    .foregroundColor(.textQuaternary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)

            HStack(spacing: 6) {
                // Processing state indicator — colour matches the file type
                ZStack {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(rowColor)
                            .shadow(color: rowColor.opacity(0.6), radius: 5)
                    } else if isQueued {
                        Image(systemName: "hourglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.45))
                            .rotationEffect(.degrees(hourglassFlipped ? 180 : 0))
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: false), value: hourglassFlipped)
                            .onAppear { hourglassFlipped = true }
                            .onDisappear { hourglassFlipped = false }
                    } else if isProcessed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundColor(rowColor)
                            .shadow(color: rowColor.opacity(0.5), radius: 4)
                    }
                }
                .frame(width: 20, height: 20)

                // Eye button
                Button { onView() } label: {
                    ZStack {
                        Circle()
                            .fill(rowColor.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "eye.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(rowColor)
                    }
                }
                .buttonStyle(.plain)

                // Context menu
                Menu {
                    Section("Text") {
                        Button { onView() } label: { Label("View / Edit Text", systemImage: "pencil") }
                        Button { showDraftPrompts = true } label: { Label("Draft Note", systemImage: "note.text") }
                    }
                    Section("Share") {
                        ShareLink(item: transcript.text) { Label("Share…", systemImage: "square.and.arrow.up") }
                    }
                    if !transcript.isMerge {
                        Section("Manage") {
                            Button { showRename = true } label: { Label("Rename", systemImage: "pencil") }
                            Button { showMoveTo = true } label: { Label("Move to…", systemImage: "folder") }
                            Button(role: .destructive) { DeleteConfirmPresenter.show(itemName: transcript.label, onDelete: onDelete) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    Section("Info") {
                        Button { showMoreInfo = true } label: { Label("More Info", systemImage: "info.circle") }
                    }
                } label: {
                    Text("···")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(isSelected ? rowColor.opacity(0.08) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .sheet(isPresented: $showRename) {
            RenameRecordingSheet(currentName: transcript.label, title: "Rename Text") { newName in
                LocalTranscriptStore.shared.rename(id: transcript.id, newLabel: newName)
                onRenamed()
            }
        }
        .sheet(isPresented: $showMoreInfo) {
            TextMoreInfoSheet(transcript: transcript)
        }
        .sheet(isPresented: $showMoveTo) {
            BulkMoveTranscriptSheet(ids: [transcript.id], currentItemId: itemId) { onMoved() }
        }
        .fullScreenCover(isPresented: $showDraftPrompts) {
            PromptsView(context: .applyToText(
                transcriptTexts: [transcript.text],
                itemId: itemId,
                transcriptIds: [transcript.id]
            ))
        }
    }
}

// MARK: - Transcript viewer / editor

struct TranscriptViewerView: View {
    let transcript: TranscriptSummary
    var onSaved: ((String) -> Void)? = nil
    @Environment(\.dismiss) var dismiss

    @State private var editedText: String
    @State private var showSaveCard = false

    init(transcript: TranscriptSummary, onSaved: ((String) -> Void)? = nil) {
        self.transcript = transcript
        self.onSaved = onSaved
        self._editedText = State(initialValue: transcript.text)
    }

    private var hasChanges: Bool { editedText != transcript.text }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: transcript.label, accentColor: .stageText, onBack: {
                    if hasChanges {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showSaveCard = true }
                    } else {
                        dismiss()
                    }
                }, trailingIcon: nil)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.stageText.opacity(0.4)).frame(height: 1)
                }

                TextEditor(text: $editedText)
                    .font(.inter(14))
                    .foregroundColor(.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.phoneBg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }

            // Save / Discard card
            if showSaveCard {
                Color.black.opacity(0.65).ignoresSafeArea().zIndex(10)
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.stageText)
                            .shadow(color: Color.stageText.opacity(0.7), radius: 10)

                        Text("Save Changes?")
                            .font(.inter(16, weight: .heavy))
                            .foregroundColor(.textPrimary)

                        Text("Do you want to save your edits to this file?")
                            .font(.inter(13))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showSaveCard = false }
                                dismiss()
                            } label: {
                                Text("Discard")
                                    .font(.inter(14, weight: .semibold))
                                    .foregroundColor(.danger)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.danger.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showSaveCard = false }
                                onSaved?(editedText)
                                dismiss()
                            } label: {
                                Text("Save")
                                    .font(.inter(14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(LinearGradient(
                                        colors: [Color.stageText.opacity(0.8), Color.stageText.opacity(0.6)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(24)
                    .background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.stageText.opacity(0.35), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.stageText.opacity(0.15), radius: 20)
                    .padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(11)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSaveCard)
        .navigationBarHidden(true)
    }
}

// MARK: - Text more info sheet

struct TextMoreInfoSheet: View {
    let transcript: TranscriptSummary
    @Environment(\.dismiss) var dismiss

    private var wordCount: Int { transcript.text.split(separator: " ").count }
    private var charCount: Int { transcript.text.count }
    private var created: String {
        let entry = LocalTranscriptStore.shared.entries.first(where: { $0.id == transcript.id })
        guard let date = entry?.createdAt else { return "—" }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        return df.string(from: date)
    }

    var body: some View {
        ZStack {
            Color(hex: "#081221").ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("More Info")
                        .font(.inter(17, weight: .heavy)).foregroundColor(.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .foregroundColor(.textTertiary).frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.07)).clipShape(Circle())
                    }
                }
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)

                VStack(spacing: 1) {
                    infoRow("Name",       transcript.label)
                    infoRow("Words",      "\(wordCount)")
                    infoRow("Characters", "\(charCount)")
                    infoRow("Duration",   transcript.duration.isEmpty ? "—" : transcript.duration)
                    infoRow("Created",    created)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.inter(13, weight: .semibold)).foregroundColor(.textTertiary)
            Spacer()
            Text(value).font(.inter(13)).foregroundColor(.textPrimary).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
    }
}

// MARK: - Bulk move transcript sheet

struct BulkMoveTranscriptSheet: View {
    let ids: [String]
    let currentItemId: String
    var onMoved: () -> Void
    @Environment(\.dismiss) var dismiss

    @State private var expanded = Set<String>()
    private let allItems     = LocalItemStore.shared.all()
    private let collections  = LocalCollectionStore.shared.all()

    private func items(forCollectionId id: String?) -> [LocalStoredItem] {
        guard let id else { return allItems.filter { $0.collectionId == nil || ($0.collectionId?.isEmpty ?? true) } }
        return allItems.filter { $0.collectionId == id }
    }

    var body: some View {
        ZStack {
            Color(hex: "#081221").ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 36, height: 4).padding(.top, 12)
                HStack {
                    Text("Move \(ids.count) file\(ids.count == 1 ? "" : "s") to…")
                        .font(.inter(17, weight: .heavy)).foregroundColor(.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .foregroundColor(.textTertiary).frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.07)).clipShape(Circle())
                    }
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        collectionBlock(name: "My Collection", id: nil)
                        ForEach(collections) { col in
                            collectionBlock(name: col.name, id: col.id)
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 32)
                }
            }
        }
    }

    @ViewBuilder
    private func collectionBlock(name: String, id: String?) -> some View {
        let key = id ?? "__default"
        let blockItems = items(forCollectionId: id).filter { $0.id != currentItemId }
        if !blockItems.isEmpty {
            VStack(spacing: 0) {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
                }} label: {
                    HStack(spacing: 10) {
                        Image(systemName: expanded.contains(key) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.textTertiary).frame(width: 16)
                        Image(systemName: "tray.fill").font(.system(size: 13)).foregroundColor(.brandCyan)
                        Text(name).font(.inter(14, weight: .bold)).foregroundColor(.textPrimary)
                        Spacer()
                        Text("\(blockItems.count)").font(.inter(11, weight: .semibold)).foregroundColor(.textQuaternary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if expanded.contains(key) {
                    VStack(spacing: 0) {
                        ForEach(blockItems) { target in
                            Button { moveHere(target) } label: {
                                HStack(spacing: 10) {
                                    Rectangle().fill(Color.brandCyan.opacity(0.4)).frame(width: 2, height: 22).padding(.leading, 14)
                                    ZStack {
                                        Circle().fill(Color.stageText.opacity(0.15)).frame(width: 26, height: 26)
                                        Image(systemName: "doc.text").font(.system(size: 11, weight: .semibold)).foregroundColor(.stageText)
                                    }
                                    Text(target.name).font(.inter(13, weight: .semibold)).foregroundColor(.textSecondary).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 15)).foregroundColor(.brandCyan.opacity(0.7))
                                }
                                .padding(.vertical, 10).padding(.trailing, 14).background(Color.white.opacity(0.03))
                            }
                            .buttonStyle(.plain)
                            if target.id != blockItems.last?.id {
                                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1).padding(.leading, 32)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 2).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func moveHere(_ target: LocalStoredItem) {
        for id in ids {
            guard let entry = LocalTranscriptStore.shared.entries.first(where: { $0.id == id }) else { continue }
            LocalTranscriptStore.shared.delete(id: id)
            LocalTranscriptStore.shared.add(LocalTranscriptEntry(
                id: UUID().uuidString, itemId: target.id, label: entry.label,
                text: entry.text, durationSeconds: entry.durationSeconds, createdAt: entry.createdAt
            ))
        }
        onMoved()
        dismiss()
    }
}
