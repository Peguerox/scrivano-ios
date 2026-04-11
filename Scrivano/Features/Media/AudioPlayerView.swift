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
                            ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { speed in
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

    func load(url: URL?, autoPlay: Bool = false) {
        guard let url = url else { return }
        // Init + prepareToPlay off main thread — eliminates first-play lag
        Task {
            let p = await AudioPlayerManager.preparePlayer(url: url)
            self.player = p
            self.duration = p?.duration ?? 0
            if autoPlay { self.play() }
        }
    }

    nonisolated static func preparePlayer(url: URL) async -> AVAudioPlayer? {
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.enableRate = true   // required for any rate != 1.0 to take effect
        p?.prepareToPlay()
        return p
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
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
        if isPlaying { player?.rate = r }
        else { player?.rate = r }  // stored for when play() is called
    }
}

// MARK: - Audio File Processor (split / trim)

import CoreMedia

struct AudioFileProcessor {

    /// Splits `sourceURL` at `splitTime` seconds into two new m4a files.
    /// Returns URLs of (firstHalf, secondHalf).
    static func split(sourceURL: URL, at splitTime: TimeInterval, itemId: String) async throws -> (URL, URL) {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration).seconds
        let url1 = LocalRecordingStore.newFileURL(itemId: itemId)
        let url2 = LocalRecordingStore.newFileURL(itemId: itemId)
        try await export(asset: asset, from: 0,         to: splitTime, outputURL: url1)
        try await export(asset: asset, from: splitTime, to: duration,  outputURL: url2)
        return (url1, url2)
    }

    /// Trims `sourceURL` keeping only the region from `startTime` to `endTime`.
    static func trim(sourceURL: URL, from startTime: TimeInterval, to endTime: TimeInterval, itemId: String) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let url = LocalRecordingStore.newFileURL(itemId: itemId)
        try await export(asset: asset, from: startTime, to: endTime, outputURL: url)
        return url
    }

    private static func export(asset: AVAsset, from start: TimeInterval, to end: TimeInterval, outputURL: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "AudioFileProcessor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create export session"])
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(
            start:    CMTime(seconds: start,       preferredTimescale: 44100),
            duration: CMTime(seconds: end - start, preferredTimescale: 44100)
        )
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                if session.status == .completed {
                    cont.resume()
                } else {
                    cont.resume(throwing: session.error ??
                        NSError(domain: "AudioFileProcessor", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Export failed"]))
                }
            }
        }
    }
}
