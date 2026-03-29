import SwiftUI

struct NoteFile: Identifiable, Codable {
    let id: String
    let name: String
    let size: String
    let createdAt: String
    let content: String?
    let promptLabel: String?

    enum CodingKeys: String, CodingKey {
        case id, name, size, content
        case createdAt = "created_at"
        case promptLabel = "prompt_label"
    }
}

struct NotesListView: View {
    let item: Item
    @Environment(\.dismiss) var dismiss
    @State private var notes: [NoteFile] = []
    @State private var selected = Set<String>()
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var showPrompts = false
    @State private var viewerNote: NoteFile? = nil
    @State private var menuTarget: NoteFile? = nil
    @State private var showFileMenu = false
    @State private var error: String? = nil

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(
                    title: "Notes",
                    accentColor: .stageNotes,
                    onBack: { dismiss() },
                    trailingIcon: "···",
                    onTrailing: {}
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.stageNotes.opacity(0.4)).frame(height: 1)
                }

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(notes) { note in
                            NoteFileRow(
                                note: note,
                                isSelected: selected.contains(note.id),
                                onTap: { toggleSelect(note.id) },
                                onOpen: { viewerNote = note },
                                onMenu: { menuTarget = note; showFileMenu = true }
                            )
                        }
                        if notes.isEmpty && !isLoading {
                            VStack(spacing: 14) {
                                Image(systemName: "note.text").font(.system(size: 36)).foregroundColor(.textQuaternary)
                                Text("No notes yet").font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                                Text("Apply a prompt to text files to generate notes").font(.inter(12)).foregroundColor(.textQuaternary).multilineTextAlignment(.center).padding(.horizontal, 32)
                            }.padding(.top, 60)
                        }
                    }
                }

                VStack(spacing: 7) {
                    Divider().background(Color.white.opacity(0.07))

                    if let err = error { Text(err).font(.inter(11)).foregroundColor(.danger).padding(.horizontal, 18) }

                    HStack {
                        Spacer()
                        Button {
                            showPrompts = true
                        } label: {
                            HStack(spacing: 6) {
                                if isGenerating { ProgressView().tint(.white).scaleEffect(0.7) }
                                Image(systemName: "sparkles")
                                Text(isGenerating ? "Generating…" : "Process Notes")
                            }
                            .font(.inter(13, weight: .bold))
                            .foregroundColor(selected.isEmpty ? .textTertiary : .white)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(
                                Group {
                                    if selected.isEmpty {
                                        Color.white.opacity(0.09)
                                    } else {
                                        LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .leading, endPoint: .trailing)
                                    }
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(selected.isEmpty || isGenerating)
                    }
                    .padding(.horizontal, 18)

                    Text("Select a prompt and apply it to the selected notes")
                        .font(.inter(11)).foregroundColor(.textQuaternary)
                        .padding(.bottom, 28)
                }
                .background(Color.phoneBg)
            }

            if isLoading { LoadingOverlay() }
        }
        .navigationBarHidden(true)
        .task { await loadNotes() }
        .sheet(isPresented: $showPrompts) {
            PromptsView(context: .generateNote(selectedTextIds: Array(selected), itemId: item.id))
        }
        .sheet(item: $viewerNote) { note in
            TextViewerView(
                file: TextFile(id: note.id, name: note.name, size: note.size, createdAt: note.createdAt, content: note.content, isMerged: false),
                type: .note
            )
        }
        .sheet(isPresented: $showFileMenu) {
            if let n = menuTarget {
                NoteFileMenuView(note: n)
            }
        }
    }

    private func toggleSelect(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func loadNotes() async {
        isLoading = true
        defer { isLoading = false }
        struct Res: Decodable { let success: Bool; let notes: [NoteFile] }
        do {
            let res = try await APIClient.shared.request(path: "/api/items/\(item.id)/notes", responseType: Res.self)
            if res.success { notes = res.notes }
        } catch { self.error = error.localizedDescription }
    }
}

struct NoteFileRow: View {
    let note: NoteFile
    var isSelected: Bool
    var onTap: () -> Void
    var onOpen: () -> Void
    var onMenu: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color.stageNotes.opacity(0.5), Color.stageNotes.opacity(0.25)], center: .center, startRadius: 0, endRadius: 24))
                        .frame(width: 48, height: 48)
                    Image(systemName: "note.text")
                        .font(.system(size: 18))
                        .foregroundColor(.stageNotes)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(note.name).font(.inter(14, weight: .bold)).foregroundColor(.textPrimary).lineLimit(1)
                HStack(spacing: 10) {
                    if let label = note.promptLabel {
                        Text(label).font(.inter(10, weight: .bold)).foregroundColor(Color(hex: "#a78bfa"))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: "#a78bfa").opacity(0.1))
                            .clipShape(Capsule())
                    }
                    Text(note.size).font(.inter(11)).foregroundColor(.textQuaternary)
                    Text(note.createdAt.prefix(10)).font(.inter(11)).foregroundColor(.textQuaternary)
                }
            }

            Spacer()

            Button(action: onMenu) {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundColor(.textTertiary)
                    .rotationEffect(.degrees(90)).padding(8)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(isSelected ? Color.brandBlue.opacity(0.08) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct NoteFileMenuView: View {
    let note: NoteFile
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.sheetBg.ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.15)).frame(width: 36, height: 4).padding(.vertical, 12)
                Text(note.name).font(.inter(13, weight: .bold)).foregroundColor(.textPrimary).padding(.bottom, 8)
                Divider().background(Color.white.opacity(0.07))
                menuBtn("square.and.arrow.up", color: .brandCyan, title: "Share") {}
                menuBtn("sparkles", color: Color(hex: "#a78bfa"), title: "Apply Prompt") {}
                menuBtn("trash.fill", color: .danger, title: "Delete Note", isDanger: true) {}
                Spacer().frame(height: 24)
            }
        }
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }

    private func menuBtn(_ icon: String, color: Color, title: String, isDanger: Bool = false, action: @escaping () -> Void) -> some View {
        Button { action(); dismiss() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(color).frame(width: 32)
                Text(title).font(.inter(14, weight: .semibold)).foregroundColor(isDanger ? .danger : .textPrimary)
                Spacer()
            }.padding(.horizontal, 20).padding(.vertical, 14)
        }.buttonStyle(.plain)
    }
}
