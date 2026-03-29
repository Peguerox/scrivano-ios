import SwiftUI
import AVFoundation

struct AudioPlayerView: View {
    let file: MediaFile
    @Environment(\.dismiss) var dismiss
    @StateObject private var player = AudioPlayerManager()

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(
                    title: "Audio",
                    accentColor: .stageMedia,
                    onBack: { dismiss() },
                    trailingIcon: "···",
                    onTrailing: {}
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.stageMedia.opacity(0.4)).frame(height: 1)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Waveform display
                        HStack(spacing: 2) {
                            ForEach(0..<50, id: \.self) { i in
                                let progress = player.duration > 0 ? player.currentTime / player.duration : 0
                                let isPlayed = Double(i) / 50.0 < progress
                                Capsule()
                                    .fill(isPlayed ? Color.stageMedia.opacity(0.85) : Color.white.opacity(0.12))
                                    .frame(width: 4, height: CGFloat.random(in: 10...40))
                            }
                        }
                        .frame(height: 50)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)

                        // File info
                        VStack(spacing: 4) {
                            Text(file.name)
                                .font(.inter(14, weight: .bold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(file.createdAt.prefix(10) + " · m4a")
                                .font(.inter(11))
                                .foregroundColor(.textQuaternary)
                        }
                        .padding(.horizontal, 24)

                        // Progress
                        VStack(spacing: 6) {
                            Slider(value: Binding(
                                get: { player.duration > 0 ? player.currentTime / player.duration : 0 },
                                set: { player.seek(to: $0 * player.duration) }
                            ))
                            .accentColor(.stageMedia)
                            .padding(.horizontal, 18)

                            HStack {
                                Text(formatTime(player.currentTime))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.textTertiary)
                                Spacer()
                                Text(formatTime(player.duration))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.textQuaternary)
                            }
                            .padding(.horizontal, 18)
                        }

                        // Controls
                        HStack(spacing: 36) {
                            VStack(spacing: 4) {
                                Button { player.skip(-15) } label: {
                                    Image(systemName: "gobackward.15")
                                        .font(.system(size: 28, weight: .medium))
                                        .foregroundColor(.textSecondary)
                                }
                                Text("15")
                                    .font(.inter(9, weight: .bold))
                                    .foregroundColor(.textQuaternary)
                            }

                            Button { player.togglePlay() } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 70, height: 70)
                                    .background(
                                        LinearGradient(colors: [Color.stageMedia, Color.stageMedia.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                                    )
                                    .clipShape(Circle())
                                    .shadow(color: Color.stageMedia.opacity(0.5), radius: 14, y: 6)
                            }

                            VStack(spacing: 4) {
                                Button { player.skip(15) } label: {
                                    Image(systemName: "goforward.15")
                                        .font(.system(size: 28, weight: .medium))
                                        .foregroundColor(.textSecondary)
                                }
                                Text("15")
                                    .font(.inter(9, weight: .bold))
                                    .foregroundColor(.textQuaternary)
                            }
                        }

                        // Speed
                        HStack(spacing: 6) {
                            ForEach([0.75, 1.0, 1.25, 1.5], id: \.self) { speed in
                                Button {
                                    player.setRate(Float(speed))
                                } label: {
                                    Text("\(speed, specifier: speed == 1.0 ? "%.0f×" : "%.2g×")")
                                        .font(.inter(12, weight: .bold))
                                        .foregroundColor(player.rate == Float(speed) ? .brandCyan : .textTertiary)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(player.rate == Float(speed) ? Color.brandBlue.opacity(0.2) : Color.white.opacity(0.05))
                                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(player.rate == Float(speed) ? Color.brandCyan.opacity(0.4) : Color.clear, lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                }
                            }
                        }

                        // Stats
                        HStack(spacing: 8) {
                            ForEach([("Format", "m4a"), ("Quality", "Med"), ("Depth", "16bit"), ("Size", file.size)], id: \.0) { s in
                                VStack(spacing: 4) {
                                    Text(s.0).font(.inter(9, weight: .bold)).foregroundColor(.textQuaternary).tracking(0.5).textCase(.uppercase)
                                    Text(s.1).font(.inter(12, weight: .bold)).foregroundColor(.textSecondary)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
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
        .onAppear { player.load(url: nil) } // would use actual URL in real impl
        .onDisappear { player.stop() }
    }

    private func formatTime(_ t: Double) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

@MainActor
final class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var rate: Float = 1.0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL?) {
        guard let url = url else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        player?.rate = rate
        player?.play()
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = self?.player?.currentTime ?? 0
                if self?.player?.isPlaying == false { self?.isPlaying = false; self?.timer?.invalidate() }
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func stop() {
        player?.stop()
        isPlaying = false
        timer?.invalidate()
    }

    func seek(to time: Double) {
        player?.currentTime = time
        currentTime = time
    }

    func skip(_ seconds: Double) {
        let t = max(0, min(duration, currentTime + seconds))
        seek(to: t)
    }

    func setRate(_ r: Float) {
        rate = r
        player?.rate = r
    }
}
