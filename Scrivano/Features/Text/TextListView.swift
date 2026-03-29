import SwiftUI

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

struct TextListView: View {
    let item: Item
    @Environment(\.dismiss) var dismiss
    @State private var files: [TextFile] = []
    @State private var selected = Set<String>()
    @State private var isLoading = false
    @State private var showPrompts = false
    @State private var viewerFile: TextFile? = nil
    @State private var menuTarget: TextFile? = nil
    @State private var showFileMenu = false
    @State private var error: String? = nil

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(
                    title: "Text",
                    accentColor: .stageText,
                    onBack: { dismiss() },
                    trailingIcon: "···",
                    onTrailing: {}
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.stageText.opacity(0.4)).frame(height: 1)
                }

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(files) { file in
                            TextFileRow(
                                file: file,
                                isSelected: selected.contains(file.id),
                                onTap: { toggleSelect(file.id) },
                                onOpen: { viewerFile = file },
                                onMenu: { menuTarget = file; showFileMenu = true }
                            )
                        }
                        if files.isEmpty && !isLoading {
                            VStack(spacing: 14) {
                                Image(systemName: "doc.text").font(.system(size: 36)).foregroundColor(.textQuaternary)
                                Text("No text files").font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                                Text("Transcribe audio files to generate text").font(.inter(12)).foregroundColor(.textQuaternary)
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
                                Image(systemName: "sparkles")
                                Text("Process Text")
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
                        .disabled(selected.isEmpty)
                    }
                    .padding(.horizontal, 18)

                    Text("Select a prompt and apply it to the selected texts")
                        .font(.inter(11)).foregroundColor(.textQuaternary)
                        .padding(.bottom, 28)
                }
                .background(Color.phoneBg)
            }

            if isLoading { LoadingOverlay() }
        }
        .navigationBarHidden(true)
        .task { await loadFiles() }
        .sheet(isPresented: $showPrompts) { PromptsView(context: .applyToText(selectedIds: Array(selected), itemId: item.id)) }
        .sheet(item: $viewerFile) { file in TextViewerView(file: file, type: .text) }
        .sheet(isPresented: $showFileMenu) {
            if let f = menuTarget { TextFileMenuView(file: f) }
        }
    }

    private func toggleSelect(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func loadFiles() async {
        isLoading = true
        defer { isLoading = false }
        struct Res: Decodable { let success: Bool; let files: [TextFile] }
        do {
            let res = try await APIClient.shared.request(path: "/api/items/\(item.id)/text", responseType: Res.self)
            if res.success { files = res.files }
        } catch { self.error = error.localizedDescription }
    }
}

struct TextFileRow: View {
    let file: TextFile
    var isSelected: Bool
    var onTap: () -> Void
    var onOpen: () -> Void
    var onMenu: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                ZStack {
                    Circle()
                        .fill(
                            file.isMerged
                                ? RadialGradient(colors: [Color.brandCyan.opacity(0.5), Color.brandBlue.opacity(0.25)], center: .center, startRadius: 0, endRadius: 24)
                                : RadialGradient(colors: [Color.stageText.opacity(0.5), Color.stageText.opacity(0.25)], center: .center, startRadius: 0, endRadius: 24)
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18))
                        .foregroundColor(file.isMerged ? .brandCyan : .stageText)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name).font(.inter(14, weight: .bold)).foregroundColor(.textPrimary).lineLimit(1)
                HStack(spacing: 10) {
                    Text(file.size).font(.inter(11)).foregroundColor(.textQuaternary)
                    Text(file.createdAt.prefix(10)).font(.inter(11)).foregroundColor(.textQuaternary)
                }
            }

            Spacer()

            Button(action: onMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .rotationEffect(.degrees(90))
                    .padding(8)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(isSelected ? Color.brandBlue.opacity(0.08) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct TextFileMenuView: View {
    let file: TextFile
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.sheetBg.ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.15)).frame(width: 36, height: 4).padding(.vertical, 12)
                Text(file.name).font(.inter(13, weight: .bold)).foregroundColor(.textPrimary).padding(.bottom, 8)
                Divider().background(Color.white.opacity(0.07))
                menuBtn("square.and.arrow.up", color: .brandCyan, title: "Share") {}
                menuBtn("sparkles", color: Color(hex: "#a78bfa"), title: "Apply Prompt") {}
                menuBtn("trash.fill", color: .danger, title: "Delete File", isDanger: true) {}
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
