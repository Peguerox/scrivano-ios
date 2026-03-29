import SwiftUI
import AVFoundation

struct RecordingView: View {
    let item: Item
    @Environment(\.dismiss) var dismiss
    @StateObject private var recorder = AudioRecorderManager()
    @StateObject private var transcriptionMgr = TranscriptionManager.shared
    @State private var showConfirmStop = false
    @State private var isUploading = false
    @State private var uploadError: String? = nil

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            LinearGradient(
                colors: [Color.stageMedia.opacity(0.12), .clear],
                startPoint: .top, endPoint: .center
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                // Bar
                SubScreenBar(
                    title: "Recording",
                    accentColor: .stageMedia,
                    onBack: {
                        if recorder.isRecording { showConfirmStop = true } else { dismiss() }
                    },
                    trailingIcon: nil
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.stageMedia.opacity(0.3)).frame(height: 1)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Context card
                        HStack(spacing: 10) {
                            Text("📁")
                            Text(item.name)
                                .font(.inter(13, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            if recorder.isRecording {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.danger)
                                        .frame(width: 7, height: 7)
                                        .scaleEffect(recorder.isRecording ? 1.0 : 0.5)
                                        .animation(.easeInOut(duration: 0.7).repeatForever(), value: recorder.isRecording)
                                    Text("LIVE")
                                        .font(.inter(10, weight: .heavy))
                                        .foregroundColor(.danger)
                                        .tracking(1)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 18)
                        .padding(.top, 16)

                        // Waveform
                        WaveformView(levels: recorder.audioLevels, isActive: recorder.isRecording)
                            .frame(height: 80)
                            .padding(.horizontal, 18)

                        // Timer
                        VStack(spacing: 8) {
                            Text(recorder.formattedTime)
                                .font(.system(size: 52, weight: .heavy, design: .monospaced))
                                .foregroundColor(.textPrimary)

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(recorder.isRecording ? Color.danger : Color.textQuaternary)
                                    .frame(width: 7, height: 7)
                                Text(recorder.isRecording ? "Recording in progress" : (recorder.isPaused ? "Paused" : "Ready"))
                                    .font(.inter(12, weight: .medium))
                                    .foregroundColor(.textTertiary)
                            }
                        }

                        // Controls
                        HStack(spacing: 32) {
                            // Undo/restart
                            Button {
                                recorder.restart()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.textTertiary)
                                    .frame(width: 52, height: 52)
                                    .background(Color.white.opacity(0.07))
                                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                    .clipShape(Circle())
                            }

                            // Stop
                            Button {
                                let duration = Double(recorder.elapsedSeconds)
                                let url = recorder.recordedFileURL
                                recorder.stop()
                                if let url = url, duration > 0 {
                                    Task {
                                        await transcriptionMgr.transcribe(
                                            audioURL: url,
                                            durationSeconds: duration,
                                            itemId: item.id
                                        ) { _ in }
                                    }
                                }
                                dismiss()
                            } label: {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 70, height: 70)
                                    .background(
                                        LinearGradient(colors: [Color.stageMedia, Color.stageMedia.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                                    )
                                    .clipShape(Circle())
                                    .shadow(color: Color.stageMedia.opacity(0.5), radius: 14, y: 6)
                            }

                            // Pause
                            Button {
                                recorder.togglePause()
                            } label: {
                                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.textTertiary)
                                    .frame(width: 52, height: 52)
                                    .background(Color.white.opacity(0.07))
                                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                    .clipShape(Circle())
                            }
                        }

                        // Stats
                        HStack(spacing: 8) {
                            ForEach([
                                ("Depth", "16bit"),
                                ("Format", "m4a"),
                                ("Quality", "Med"),
                                ("Size", recorder.formattedSize)
                            ], id: \.0) { stat in
                                VStack(spacing: 4) {
                                    Text(stat.0)
                                        .font(.inter(9, weight: .bold))
                                        .foregroundColor(.textQuaternary)
                                        .tracking(0.5)
                                        .textCase(.uppercase)
                                    Text(stat.1)
                                        .font(.inter(12, weight: .bold))
                                        .foregroundColor(.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.07), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { recorder.requestPermissionAndStart() }
        .confirmationDialog("Stop recording?", isPresented: $showConfirmStop) {
            Button("Stop & Discard", role: .destructive) { recorder.stop(); dismiss() }
            Button("Keep Recording", role: .cancel) {}
        }
    }
}

// MARK: - Waveform
struct WaveformView: View {
    let levels: [Float]
    var isActive: Bool

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<40, id: \.self) { i in
                    let level = i < levels.count ? CGFloat(levels[i]) : CGFloat.random(in: 0.05...0.15)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.stageMedia.opacity(0.9), Color.stageMedia.opacity(0.4)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: (geo.size.width - 40*3) / 40, height: max(4, level * geo.size.height))
                        .animation(.spring(response: 0.15), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - AudioRecorderManager
@MainActor
final class AudioRecorderManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var elapsedSeconds: Int = 0
    @Published var audioLevels: [Float] = Array(repeating: 0.1, count: 40)
    @Published var fileSize: Int64 = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var outputURL: URL?

    var formattedTime: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var formattedSize: String {
        if fileSize < 1024 { return "\(fileSize)B" }
        if fileSize < 1048576 { return String(format: "%.1fKB", Double(fileSize)/1024) }
        return String(format: "%.1fMB", Double(fileSize)/1048576)
    }

    func requestPermissionAndStart() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted { self?.start() }
            }
        }
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .default)
        try? session.setActive(true)

        let dir = FileManager.default.temporaryDirectory
        let name = "scrivano_\(Date().timeIntervalSince1970).m4a"
        outputURL = dir.appendingPathComponent(name)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        guard let url = outputURL,
              let rec = try? AVAudioRecorder(url: url, settings: settings) else { return }
        rec.isMeteringEnabled = true
        rec.record()
        self.recorder = rec
        isRecording = true
        isPaused = false
        startTimer()
    }

    func togglePause() {
        guard let rec = recorder else { return }
        if isPaused { rec.record(); isPaused = false; startTimer() }
        else { rec.pause(); isPaused = true; timer?.invalidate() }
    }

    func stop() {
        recorder?.stop()
        timer?.invalidate()
        isRecording = false
        isPaused = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func restart() {
        stop()
        elapsedSeconds = 0
        fileSize = 0
        audioLevels = Array(repeating: 0.1, count: 40)
        start()
    }

    var recordedFileURL: URL? { outputURL }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedSeconds = Int(self.recorder?.currentTime ?? 0)
                self.recorder?.updateMeters()
                let level = self.recorder?.averagePower(forChannel: 0) ?? -60
                let normalized = max(0, min(1, (level + 60) / 60))
                self.audioLevels = self.audioLevels.dropFirst() + [Float(normalized)]
                if let url = self.outputURL,
                   let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                    self.fileSize = attrs[.size] as? Int64 ?? 0
                }
            }
        }
    }
}
