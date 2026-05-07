import SwiftUI
import UIKit

// MARK: - NotesListView

struct NotesListView: View {
    let item: Item
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var notesMgr = NoteGenerationManager.shared
    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var notes: [LocalNoteEntry] = []
    @State private var selected = Set<String>()
    @State private var showPrompts = false
    @State private var viewerNote: LocalNoteEntry? = nil

    // Bulk action
    enum BulkAction { case move, delete }
    @State private var pendingAction: BulkAction? = nil
    @State private var showBulkMove = false
    @State private var showDeleteConfirm = false
    @State private var showProcessConfirm = false

    // Rename overlay
    @State private var renameNote: LocalNoteEntry? = nil
    @State private var renameText = ""

    private var inSelectionMode: Bool { pendingAction != nil }
    private var selectedNotes: [LocalNoteEntry] { notes.filter { selected.contains($0.id) } }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                SubScreenBar(title: langMgr.t("automation.stage.notes"), accentColor: .stageNotes, onBack: { dismiss() })
                    .overlay(alignment: .trailing) {
                        Menu {
                            Button {
                                selected.removeAll()
                                pendingAction = .move
                            } label: {
                                Label(langMgr.t("common.move"), systemImage: "folder")
                            }
                            .disabled(notes.isEmpty)
                            Button(role: .destructive) {
                                selected.removeAll()
                                pendingAction = .delete
                            } label: {
                                Label(langMgr.t("common.delete"), systemImage: "trash")
                            }
                            .disabled(notes.isEmpty)
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
                        Rectangle().fill(Color.stageNotes.opacity(0.4)).frame(height: 1)
                    }

                // File list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(notes.enumerated()), id: \.element.id) { idx, note in
                            SwipeToDelete(onDelete: { deleteNote(note) }) {
                                LocalNoteRow(
                                    note: note,
                                    index: idx + 1,
                                    isSelected: selected.contains(note.id),
                                    isProcessing: notesMgr.processingTranscriptIds.contains(note.id),
                                    isProcessed: notesMgr.completedTranscriptIds.contains(note.id),
                                    onSelect: { toggleSelect(note.id) },
                                    onView: { viewerNote = note },
                                    onDelete: { deleteNote(note) },
                                    onRenamed: { reloadNotes() },
                                    onMoved: { reloadNotes() },
                                    onRenameRequested: { renameNote = note; renameText = note.label }
                                )
                            }
                        }
                    }
                }
                .overlay {
                    if notes.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "note.text")
                                .font(.system(size: 40))
                                .foregroundColor(.textQuaternary)
                            Text(langMgr.t("notes.noNotes"))
                                .font(.inter(16, weight: .bold))
                                .foregroundColor(.textTertiary)
                            Text(langMgr.t("notes.noNotes.hint"))
                                .font(.inter(12))
                                .foregroundColor(.textQuaternary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }
                }
                .onAppear { reloadNotes() }
                .onChange(of: notesMgr.completedItemIds) { _ in reloadNotes() }

                // Bottom bar
                VStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

                    if inSelectionMode {
                        VStack(spacing: 6) {
                            Text(pendingAction == .delete ? langMgr.t("notes.selectToDelete") : langMgr.t("notes.selectToMove"))
                                .font(.inter(12, weight: .semibold))
                                .foregroundColor(.textTertiary)
                                .padding(.top, 10)

                            HStack(spacing: 10) {
                                Button {
                                    selected.removeAll(); pendingAction = nil
                                } label: {
                                    Text(langMgr.t("common.cancel"))
                                        .font(.inter(14, weight: .semibold))
                                        .foregroundColor(.textSecondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                                        .background(Color.white.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }

                                let actionColor: Color = pendingAction == .delete ? .danger : .brandBlue
                                let actionIcon  = pendingAction == .delete ? "trash" : "folder"
                                let actionLabel = pendingAction == .delete
                                    ? langMgr.t("notes.deleteCount").replacingOccurrences(of: "%d", with: "\(selected.count)")
                                    : langMgr.t("notes.moveCount").replacingOccurrences(of: "%d", with: "\(selected.count)")

                                Button {
                                    if pendingAction == .delete { showDeleteConfirm = true }
                                    else { showBulkMove = true }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: actionIcon).font(.system(size: 13, weight: .bold))
                                        Text(actionLabel).font(.inter(14, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(actionColor.opacity(selected.isEmpty ? 0.3 : 0.8))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .disabled(selected.isEmpty)
                            }

                            Text(langMgr.t("notes.selectNotes").replacingOccurrences(of: "%d", with: "\(selected.count)"))
                                .font(.inter(11)).foregroundColor(.textQuaternary)
                        }
                        .padding(.horizontal, 18).padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        VStack(spacing: 6) {
                            Button {
                                if selected.isEmpty {
                                    notes.forEach { selected.insert($0.id) }
                                }
                                if !notes.isEmpty {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showProcessConfirm = true
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "bolt.fill").font(.system(size: 14, weight: .bold))
                                    Text(langMgr.t("notes.processNotes")).font(.inter(15, weight: .heavy))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(LinearGradient(
                                    colors: [Color.stageNotes.opacity(0.25), Color.stageNotes.opacity(0.10)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.stageNotes.opacity(0.40), lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .opacity(notes.isEmpty ? 0.35 : 1.0)
                            }
                            .disabled(notes.isEmpty)

                            Text(selected.isEmpty
                                 ? langMgr.t("media.tapToSelectAll")
                                 : langMgr.t("notes.selectNotes").replacingOccurrences(of: "%d", with: "\(selected.count)"))
                                .font(.inter(11)).foregroundColor(.textQuaternary)
                        }
                        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 28)
                    }
                }
                .background(Color.phoneBg)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: inSelectionMode)
            }

            // Rename overlay
            if renameNote != nil {
                Color.black.opacity(0.65).ignoresSafeArea()
                    .onTapGesture { renameNote = nil }
                    .zIndex(20)
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Text(langMgr.t("notes.renameNote"))
                            .font(.inter(16, weight: .heavy))
                            .foregroundColor(.textPrimary)
                        TextField("", text: $renameText)
                            .font(.inter(14))
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.stageNotes.opacity(0.35), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .autocorrectionDisabled()
                        HStack(spacing: 10) {
                            Button { renameNote = nil } label: {
                                Text(langMgr.t("common.cancel"))
                                    .font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(Color.white.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            Button {
                                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                                guard !trimmed.isEmpty, let note = renameNote else { return }
                                guard let entry = LocalNoteStore.shared.entries.first(where: { $0.id == note.id }) else { return }
                                LocalNoteStore.shared.update(LocalNoteEntry(id: entry.id, itemId: entry.itemId, label: trimmed, text: entry.text, promptType: entry.promptType, createdAt: entry.createdAt))
                                renameNote = nil
                                reloadNotes()
                            } label: {
                                Text(langMgr.t("common.rename"))
                                    .font(.inter(14, weight: .bold)).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(LinearGradient(colors: [Color.brandBlue, Color.brandCyan], startPoint: .leading, endPoint: .trailing))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(24)
                    .background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.stageNotes.opacity(0.25), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.stageNotes.opacity(0.15), radius: 20)
                    .padding(.horizontal, 24)
                    Spacer()
                }
                .zIndex(21)
            }

            // Process confirm card
            if showProcessConfirm {
                Color.black.opacity(0.65).ignoresSafeArea().zIndex(10)
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 30)).foregroundColor(.stageNotes)
                            .shadow(color: Color.stageNotes.opacity(0.7), radius: 10)
                        Text(langMgr.t("notes.processNotes"))
                            .font(.inter(16, weight: .heavy)).foregroundColor(.textPrimary)
                        Text(langMgr.t("notes.continueWith").replacingOccurrences(of: "%d", with: "\(selectedNotes.count)"))
                            .font(.inter(13)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(selectedNotes, id: \.id) { n in processFileRow(name: n.label, id: n.id) }
                            }
                        }.frame(maxHeight: 160)
                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showProcessConfirm = false }
                            } label: {
                                Text(langMgr.t("common.cancel")).font(.inter(14, weight: .semibold)).foregroundColor(.textSecondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showProcessConfirm = false }
                                showPrompts = true
                            } label: {
                                Text(langMgr.t("dashboard.record.continue")).font(.inter(14, weight: .bold)).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(LinearGradient(
                                        colors: [Color.stageNotes.opacity(0.8), Color.stageNotes.opacity(0.6)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(24).background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.stageNotes.opacity(0.35), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.stageNotes.opacity(0.15), radius: 20).padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity)).zIndex(11)
            }

            // Delete confirm card
            if showDeleteConfirm {
                Color.black.opacity(0.65).ignoresSafeArea().zIndex(12)
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "trash")
                            .font(.system(size: 30)).foregroundColor(.danger)
                            .shadow(color: Color.danger.opacity(0.7), radius: 10)
                        Text(langMgr.t("notes.deleteNotes.btn"))
                            .font(.inter(16, weight: .heavy)).foregroundColor(.textPrimary)
                        Text(langMgr.t("notes.deleteNotes").replacingOccurrences(of: "%d", with: "\(selected.count)"))
                            .font(.inter(13)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(Array(selected), id: \.self) { id in
                                    if let n = notes.first(where: { $0.id == id }) {
                                        processFileRow(name: n.label, id: n.id)
                                    }
                                }
                            }
                        }.frame(maxHeight: 160)
                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteConfirm = false }
                            } label: {
                                Text(langMgr.t("common.cancel")).font(.inter(14, weight: .semibold)).foregroundColor(.textSecondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteConfirm = false }
                                for id in selected {
                                    if let note = LocalNoteStore.shared.entries.first(where: { $0.id == id }) {
                                        let iName = LocalItemStore.shared.all().first(where: { $0.id == note.itemId })?.name ?? note.itemId
                                        TrashStore.shared.trashNote(note, itemName: iName)
                                    }
                                    LocalNoteStore.shared.delete(id: id)
                                }
                                selected.removeAll(); pendingAction = nil; reloadNotes()
                            } label: {
                                Text(langMgr.t("common.delete")).font(.inter(14, weight: .bold)).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(Color.danger.opacity(0.85)).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(24).background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.danger.opacity(0.35), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.danger.opacity(0.15), radius: 20).padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity)).zIndex(13)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showProcessConfirm)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDeleteConfirm)
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showPrompts) {
            let texts = selectedNotes.map { $0.text }
            let ids   = selectedNotes.map { $0.id }
            PromptsView(context: .generateNote(transcriptTexts: texts, itemId: item.id, transcriptIds: ids))
        }
        .fullScreenCover(item: $viewerNote) { n in
            NoteViewerEditorView(note: n) { newText in saveNoteEdit(id: n.id, newText: newText) }
        }
        .sheet(isPresented: $showBulkMove) {
            BulkMoveNoteSheet(ids: Array(selected), currentItemId: item.id) {
                selected.removeAll(); pendingAction = nil; reloadNotes()
            }
        }
    }

    // MARK: - Helpers

    private func reloadNotes() {
        notes = LocalNoteStore.shared.notes(for: item.id).sorted { $0.createdAt < $1.createdAt }
    }

    private func toggleSelect(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func deleteNote(_ note: LocalNoteEntry) {
        let iName = LocalItemStore.shared.all().first(where: { $0.id == note.itemId })?.name ?? note.itemId
        TrashStore.shared.trashNote(note, itemName: iName)
        selected.remove(note.id)
        LocalNoteStore.shared.delete(id: note.id)
        reloadNotes()
    }

    private func saveNoteEdit(id: String, newText: String) {
        guard let entry = LocalNoteStore.shared.entries.first(where: { $0.id == id }) else { return }
        LocalNoteStore.shared.update(LocalNoteEntry(
            id: entry.id, itemId: entry.itemId, label: entry.label,
            text: newText, promptType: entry.promptType, createdAt: entry.createdAt
        ))
        reloadNotes()
    }

    @ViewBuilder
    private func processFileRow(name: String, id: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 12)).foregroundColor(.stageNotes)
                .frame(width: 28, height: 28).background(Color.stageNotes.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text(name).font(.inter(12, weight: .semibold)).foregroundColor(.textPrimary).lineLimit(1)
            Spacer()
            Button { toggleSelect(id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Local note row

struct LocalNoteRow: View {
    let note: LocalNoteEntry
    let index: Int
    var isSelected: Bool
    var isProcessing: Bool = false
    var isProcessed: Bool = false
    var onSelect: () -> Void
    var onView: () -> Void
    var onDelete: () -> Void = {}
    var onDraftNote: () -> Void = {}
    var onRenamed: () -> Void = {}
    var onMoved: () -> Void = {}
    var onRenameRequested: () -> Void = {}

    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var showMoreInfo = false
    @State private var showMoveTo = false
    @State private var showDraftPrompts = false
    @State private var showShareOptions = false

    private var wordCount: String {
        let words = note.text.split(separator: " ").count
        return words == 1
            ? langMgr.t("notes.wordSingular")
            : langMgr.t("notes.wordPlural").replacingOccurrences(of: "%d", with: "\(words)")
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.stageNotes.opacity(0.5), Color.stageNotes.opacity(0.25)],
                        center: .center, startRadius: 0, endRadius: 24
                    ))
                    .frame(width: 48, height: 48)
                Image(systemName: "note.text")
                    .font(.system(size: 18)).foregroundColor(.stageNotes)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(note.label)
                    .font(.inter(13, weight: .bold)).foregroundColor(.textPrimary).lineLimit(1)
                Text(wordCount)
                    .font(.inter(10)).foregroundColor(.textQuaternary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8)

            HStack(spacing: 10) {
                // Processing state indicator
                ZStack {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.stageNotes)
                            .shadow(color: Color.stageNotes.opacity(0.6), radius: 5)
                    } else if isProcessed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundColor(.stageNotes)
                            .shadow(color: Color.stageNotes.opacity(0.5), radius: 4)
                    }
                }
                .frame(width: 20, height: 20)

                Button { onView() } label: {
                    ZStack {
                        Circle().fill(Color.stageNotes.opacity(0.18)).frame(width: 32, height: 32)
                        Image(systemName: "eye.fill").font(.system(size: 11, weight: .bold)).foregroundColor(.stageNotes)
                    }
                }.buttonStyle(.plain)

                Menu {
                    Section(langMgr.t("common.section.note")) {
                        Button { onView() } label: { Label(langMgr.t("notes.viewEdit"), systemImage: "pencil") }
                        Button { showDraftPrompts = true } label: { Label(langMgr.t("notes.draftNote"), systemImage: "note.text") }
                    }
                    Section(langMgr.t("common.section.share")) {
                        Button { showShareOptions = true } label: {
                            Label(langMgr.t("common.shareEllipsis"), systemImage: "square.and.arrow.up")
                        }
                    }
                    Section(langMgr.t("common.section.manage")) {
                        Button { onRenameRequested() } label: { Label(langMgr.t("common.rename"), systemImage: "pencil") }
                        Button { showMoveTo = true } label: { Label(langMgr.t("common.moveTo"), systemImage: "folder") }
                        Button(role: .destructive) { DeleteConfirmPresenter.show(itemName: note.label, onDelete: onDelete) } label: { Label(langMgr.t("common.delete"), systemImage: "trash") }
                    }
                    Section(langMgr.t("common.section.info")) {
                        Button { showMoreInfo = true } label: { Label(langMgr.t("common.moreInfo"), systemImage: "info.circle") }
                    }
                } label: {
                    Text("···")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.textTertiary)
                        .frame(width: 32, height: 32).background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(isSelected ? Color.stageNotes.opacity(0.08) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .sheet(isPresented: $showMoreInfo) {
            NoteMoreInfoSheet(note: note)
        }
        .sheet(isPresented: $showMoveTo) {
            BulkMoveNoteSheet(ids: [note.id], currentItemId: note.itemId) { onMoved() }
        }
        .fullScreenCover(isPresented: $showDraftPrompts) {
            PromptsView(context: .generateNote(
                transcriptTexts: [note.text],
                itemId: note.itemId,
                transcriptIds: [note.id]
            ))
        }
        .confirmationDialog(langMgr.t("common.share.note"), isPresented: $showShareOptions, titleVisibility: .visible) {
            Button(langMgr.t("common.share.asPDF")) { generateAndSharePDF() }
            Button(langMgr.t("common.share.asRawText")) { shareNoteRawText() }
            Button(langMgr.t("common.cancel"), role: .cancel) {}
        }
    }

    private func generateAndSharePDF() {
        let html = MarkdownWebView.buildPrintHTML(note.text)
        PDFExporter.makePDF(fromHTML: html, title: note.label) { url in
            guard let url else { return }
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  var top = scene.windows.first?.rootViewController else { return }
            while let presented = top.presentedViewController { top = presented }
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            top.present(vc, animated: true)
        }
    }

    private func shareNoteRawText() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var top = scene.windows.first?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let vc = UIActivityViewController(activityItems: [note.text], applicationActivities: nil)
        top.present(vc, animated: true)
    }
}

// MARK: - Note viewer / editor

struct NoteViewerEditorView: View {
    let note: LocalNoteEntry
    var onSaved: ((String) -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var editedText: String
    @State private var showSaveCard = false
    @State private var showMarkdown = true
    @State private var isGeneratingPDF = false
    @State private var showViewerShareOptions = false

    init(note: LocalNoteEntry, onSaved: ((String) -> Void)? = nil) {
        self.note = note
        self.onSaved = onSaved
        self._editedText = State(initialValue: note.text)
    }

    private var hasChanges: Bool { editedText != note.text }

    @MainActor
    private func generatePDF() {
        isGeneratingPDF = true
        let html = MarkdownWebView.buildPrintHTML(editedText)
        PDFExporter.makePDF(fromHTML: html, title: note.label) { url in
            isGeneratingPDF = false
            guard let url else { return }
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  var top = scene.windows.first?.rootViewController else { return }
            while let presented = top.presentedViewController { top = presented }
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            top.present(vc, animated: true)
        }
    }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: note.label, accentColor: .stageNotes, onBack: {
                    if hasChanges {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showSaveCard = true }
                    } else { dismiss() }
                }, trailingIcon: nil)
                .padding(.trailing, showMarkdown ? 44 : 0)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.stageNotes.opacity(0.4)).frame(height: 1)
                }
                .overlay(alignment: .trailing) {
                    HStack(spacing: 8) {
                        if showMarkdown {
                            Button { showViewerShareOptions = true } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14))
                                    .foregroundColor(.stageNotes)
                                    .frame(width: 36, height: 36)
                                    .background(Color.stageNotes.opacity(0.12))
                                    .overlay(Circle().stroke(Color.stageNotes.opacity(0.3), lineWidth: 1))
                                    .clipShape(Circle())
                            }
                        }
                        Button { withAnimation(.easeInOut(duration: 0.2)) { showMarkdown.toggle() } } label: {
                            Image(systemName: showMarkdown ? "doc.richtext.fill" : "doc.richtext")
                                .font(.system(size: 15))
                                .foregroundColor(showMarkdown ? .stageNotes : .textSecondary)
                                .frame(width: 36, height: 36)
                                .background(showMarkdown ? Color.stageNotes.opacity(0.15) : Color.white.opacity(0.07))
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.trailing, 18)
                }

                if showMarkdown {
                    MarkdownWebView(markdown: editedText, theme: .light)
                } else {
                    TextEditor(text: $editedText)
                        .font(.inter(14)).foregroundColor(.textPrimary)
                        .scrollContentBackground(.hidden).background(Color.phoneBg)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }
            }

            if isGeneratingPDF {
                Color.black.opacity(0.55).ignoresSafeArea().zIndex(20)
                VStack(spacing: 18) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.stageNotes)
                        .scaleEffect(1.4)
                    Text(langMgr.t("notes.buildingPDF"))
                        .font(.inter(15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 32)
                .background(Color.phoneBg.opacity(0.97))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.3), radius: 20)
                .zIndex(21)
            }

            if showSaveCard {
                Color.black.opacity(0.65).ignoresSafeArea().zIndex(10)
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 30)).foregroundColor(.stageNotes)
                            .shadow(color: Color.stageNotes.opacity(0.7), radius: 10)
                        Text(langMgr.t("common.save_changes")).font(.inter(16, weight: .heavy)).foregroundColor(.textPrimary)
                        Text(langMgr.t("notes.doYouWantSave"))
                            .font(.inter(13)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showSaveCard = false }
                                dismiss()
                            } label: {
                                Text(langMgr.t("common.discard")).font(.inter(14, weight: .semibold)).foregroundColor(.danger)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(Color.danger.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showSaveCard = false }
                                onSaved?(editedText); dismiss()
                            } label: {
                                Text(langMgr.t("common.save")).font(.inter(14, weight: .bold)).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(LinearGradient(
                                        colors: [Color.stageNotes.opacity(0.8), Color.stageNotes.opacity(0.6)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(24).background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.stageNotes.opacity(0.35), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.stageNotes.opacity(0.15), radius: 20).padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity)).zIndex(11)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSaveCard)
        .navigationBarHidden(true)
        .confirmationDialog(langMgr.t("common.share.note"), isPresented: $showViewerShareOptions, titleVisibility: .visible) {
            Button(langMgr.t("common.share.asPDF")) { generatePDF() }
            Button(langMgr.t("common.share.asRawText")) { shareViewerRawText() }
            Button(langMgr.t("common.cancel"), role: .cancel) {}
        }
    }

    private func shareViewerRawText() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var top = scene.windows.first?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let vc = UIActivityViewController(activityItems: [editedText], applicationActivities: nil)
        top.present(vc, animated: true)
    }
}

// MARK: - Note more info sheet

struct NoteMoreInfoSheet: View {
    let note: LocalNoteEntry
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langMgr = LanguageManager.shared

    private var wordCount: Int { note.text.split(separator: " ").count }
    private var charCount: Int { note.text.count }
    private var created: String {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        return df.string(from: note.createdAt)
    }

    var body: some View {
        ZStack {
            Color(hex: "#081221").ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(langMgr.t("common.moreInfo"))
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
                    infoRow(langMgr.t("info.name"),       note.label)
                    infoRow(langMgr.t("info.words"),      "\(wordCount)")
                    infoRow(langMgr.t("info.characters"), "\(charCount)")
                    infoRow(langMgr.t("info.prompt"),     note.promptType.isEmpty ? "—" : note.promptType)
                    infoRow(langMgr.t("info.created"),    created)
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

// MARK: - Bulk move note sheet

struct BulkMoveNoteSheet: View {
    let ids: [String]
    let currentItemId: String
    var onMoved: () -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langMgr = LanguageManager.shared

    @State private var expanded = Set<String>()
    private let allItems    = LocalItemStore.shared.all()
    private let collections = LocalCollectionStore.shared.all()

    private func items(forCollectionId id: String?) -> [LocalStoredItem] {
        guard let id else {
            return allItems.filter { $0.collectionId == nil || ($0.collectionId?.isEmpty ?? true) }
        }
        return allItems.filter { $0.collectionId == id }
    }

    var body: some View {
        ZStack {
            Color(hex: "#081221").ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 36, height: 4).padding(.top, 12)
                HStack {
                    Text(langMgr.t("notes.moveTo").replacingOccurrences(of: "%d", with: "\(ids.count)"))
                        .font(.inter(17, weight: .heavy)).foregroundColor(.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .foregroundColor(.textTertiary).frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.07)).clipShape(Circle())
                    }
                }.padding(.horizontal, 20).padding(.vertical, 14)
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        let myItems = items(forCollectionId: nil).filter { $0.id != currentItemId }
                        if !myItems.isEmpty {
                            collectionHeader("My Collection", id: "my")
                            if expanded.contains("my") {
                                ForEach(myItems, id: \.id) { dest in itemRow(dest) }
                            }
                        }
                        ForEach(collections, id: \.id) { coll in
                            let collItems = items(forCollectionId: coll.id).filter { $0.id != currentItemId }
                            if !collItems.isEmpty {
                                collectionHeader(coll.name, id: coll.id)
                                if expanded.contains(coll.id) {
                                    ForEach(collItems, id: \.id) { dest in itemRow(dest) }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func collectionHeader(_ name: String, id: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
            }
        } label: {
            HStack {
                Image(systemName: "folder.fill").foregroundColor(.brandCyan).font(.system(size: 14))
                Text(name).font(.inter(13, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Image(systemName: expanded.contains(id) ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.textQuaternary)
            }
            .padding(.horizontal, 20).padding(.vertical, 12).background(Color.white.opacity(0.04))
        }.buttonStyle(.plain)
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    @ViewBuilder
    private func itemRow(_ dest: LocalStoredItem) -> some View {
        Button {
            for id in ids {
                guard let entry = LocalNoteStore.shared.entries.first(where: { $0.id == id }) else { continue }
                LocalNoteStore.shared.update(LocalNoteEntry(
                    id: entry.id, itemId: dest.id, label: entry.label,
                    text: entry.text, promptType: entry.promptType, createdAt: entry.createdAt
                ))
            }
            dismiss(); onMoved()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill").foregroundColor(.textTertiary).font(.system(size: 13))
                Text(dest.name).font(.inter(13)).foregroundColor(.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.textQuaternary)
            }
            .padding(.horizontal, 28).padding(.vertical, 11)
        }.buttonStyle(.plain)
        Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1).padding(.leading, 52)
    }
}


