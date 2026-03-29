import SwiftUI

struct MediaFile: Identifiable, Codable {
    let id: String
    let name: String
    let duration: String
    let size: String
    let createdAt: String
    let transcriptionId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, duration, size
        case createdAt = "created_at"
        case transcriptionId = "transcription_id"
    }
}

struct MediaListView: View {
    let item: Item
    @Environment(\.dismiss) var dismiss
    @State private var files: [MediaFile] = []
    @State private var selected = Set<String>()
    @State private var isLoading = false
    @State private var isTranscribing = false
    @State private var taskId: String? = nil
    @State private var error: String? = nil
    @State private var showRecorder = false
    @State private var showFilePicker = false
    @State private var menuTarget: MediaFile? = nil
    @State private var showFileMenu = false
    @State private var showPlayer: MediaFile? = nil

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(
                    title: "Media",
                    accentColor: .stageMedia,
                    onBack: { dismiss() },
                    trailingIcon: "···",
                    onTrailing: {}
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.stageMedia.opacity(0.4)).frame(height: 1)
                }

                // File list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(files) { file in
                            MediaFileRow(
                                file: file,
                                isSelected: selected.contains(file.id),
                                onTap: { toggleSelect(file.id) },
                                onMenu: { menuTarget = file; showFileMenu = true },
                                onPlay: { showPlayer = file }
                            )
                        }
                        if files.isEmpty && !isLoading {
                            VStack(spacing: 14) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 36)).foregroundColor(.textQuaternary)
                                Text("No audio files")
                                    .font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                                Text("Record or import audio to get started")
                                    .font(.inter(12)).foregroundColor(.textQuaternary)
                            }
                            .padding(.top, 60)
                        }
                    }
                }

                // Footer
                if isLoading { ProgressView().tint(.brandCyan).padding() }

                VStack(spacing: 7) {
                    Divider().background(Color.white.opacity(0.07))

                    if let err = error {
                        Text(err).font(.inter(11)).foregroundColor(.danger).padding(.horizontal, 18)
                    }

                    HStack(spacing: 10) {
                        Button { showRecorder = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "record.circle")
                                Text("Record")
                            }
                            .font(.inter(13, weight: .bold))
                            .foregroundColor(.stageMedia)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(Color.stageMedia.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.stageMedia.opacity(0.3), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button { showFilePicker = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import")
                            }
                            .font(.inter(13, weight: .bold))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(Color.white.opacity(0.07))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Spacer()

                        Button {
                            Task { await transcribeSelected() }
                        } label: {
                            HStack(spacing: 6) {
                                if isTranscribing { ProgressView().tint(.white).scaleEffect(0.7) }
                                Text(isTranscribing ? "Processing…" : "Process Media")
                            }
                            .font(.inter(13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(
                                Group {
                                    if selected.isEmpty {
                                        Color.white.opacity(0.09)
                                    } else {
                                        LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .leading, endPoint: .trailing)
                                    }
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(selected.isEmpty || isTranscribing)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .background(Color.phoneBg)
            }

            if isLoading { LoadingOverlay(message: "Loading files…") }
        }
        .navigationBarHidden(true)
        .task { await loadFiles() }
        .sheet(isPresented: $showRecorder) { RecordingView(item: item) }
        .sheet(isPresented: $showFilePicker) { Text("File picker coming soon").padding() }
        .sheet(item: $showPlayer) { file in AudioPlayerView(file: file) }
        .sheet(isPresented: $showFileMenu) {
            if let f = menuTarget { MediaFileMenuView(file: f, onDelete: { deleteFile(f) }) }
        }
    }

    // MARK: -
    private func toggleSelect(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func loadFiles() async {
        isLoading = true
        defer { isLoading = false }
        struct Res: Decodable { let success: Bool; let files: [MediaFile] }
        do {
            let res = try await APIClient.shared.request(
                path: "/api/items/\(item.id)/media",
                responseType: Res.self
            )
            if res.success { files = res.files }
        } catch { self.error = error.localizedDescription }
    }

    private func transcribeSelected() async {
        guard !selected.isEmpty else { return }
        isTranscribing = true
        defer { isTranscribing = false }

        for fileId in selected {
            guard let file = files.first(where: { $0.id == fileId }) else { continue }
            struct Body: Encodable { let fileId: String; enum CodingKeys: String, CodingKey { case fileId = "file_id" } }
            struct Res: Decodable { let success: Bool; let taskId: String?; enum CodingKeys: String, CodingKey { case success; case taskId = "task_id" } }
            do {
                let res = try await APIClient.shared.request(
                    path: "/api/audio/transcribe",
                    method: "POST",
                    body: Body(fileId: fileId),
                    responseType: Res.self
                )
                if let tid = res.taskId { taskId = tid }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func deleteFile(_ file: MediaFile) {
        files.removeAll { $0.id == file.id }
        selected.remove(file.id)
    }
}

// MARK: - Row
struct MediaFileRow: View {
    let file: MediaFile
    var isSelected: Bool
    var onTap: () -> Void
    var onMenu: () -> Void
    var onPlay: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onPlay) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color.stageMedia.opacity(0.5), Color.stageMedia.opacity(0.25)], center: .center, startRadius: 0, endRadius: 24))
                        .frame(width: 48, height: 48)
                    // Mini waveform icon
                    HStack(spacing: 2) {
                        ForEach([0.4, 0.7, 1.0, 0.6, 0.85, 0.5, 0.75], id: \.self) { h in
                            Capsule()
                                .fill(Color.stageMedia.opacity(0.9))
                                .frame(width: 2.5, height: 20 * h)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.inter(14, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text(file.duration)
                        .font(.inter(11)).foregroundColor(.textQuaternary)
                    Text(file.createdAt.prefix(10))
                        .font(.inter(11)).foregroundColor(.textQuaternary)
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(isSelected ? Color.brandBlue.opacity(0.08) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isSelected ? Color.brandCyan.opacity(0.12) : Color.white.opacity(0.05))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct MediaFileMenuView: View {
    let file: MediaFile
    var onDelete: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.sheetBg.ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.15)).frame(width: 36, height: 4).padding(.vertical, 12)
                Text(file.name).font(.inter(13, weight: .bold)).foregroundColor(.textPrimary).padding(.bottom, 8)
                Divider().background(Color.white.opacity(0.07))

                menuBtn("square.and.arrow.up", color: .brandCyan, title: "Share") {}
                menuBtn("mic.fill", color: .brandBlue, title: "Transcribe") {}
                menuBtn("trash.fill", color: .danger, title: "Delete", isDanger: true) { onDelete(); dismiss() }
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
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }.buttonStyle(.plain)
    }
}
