import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - AudioProcessor (validation, conversion, splitting)

struct AudioValidationResult {
    enum Issue: Equatable {
        case wrongFormat(ext: String)
        case tooLong(seconds: Double)
        case tooLarge(bytes: Int64)
    }
    let recordingId: String
    let displayName: String
    let fileURL: URL
    let durationSeconds: Double
    let fileSizeBytes: Int64
    let issues: [Issue]
    var isReady: Bool { issues.isEmpty }
    var needsConversion: Bool { issues.contains { if case .wrongFormat = $0 { return true }; return false } }
    var needsSplit: Bool { issues.contains {
        if case .tooLong = $0 { return true }
        if case .tooLarge = $0 { return true }
        return false
    }}
    var splitPartCount: Int {
        guard needsSplit else { return 1 }
        let byDuration = Int(ceil(durationSeconds / AudioProcessor.maxDurationSeconds))
        let bySize = fileSizeBytes > 0
            ? Int(ceil(Double(fileSizeBytes) / Double(AudioProcessor.maxFileSizeBytes))) : 1
        return max(byDuration, bySize, 2)
    }
}

enum AudioProcessorError: Error, LocalizedError {
    case fileNotFound, noExportSession, exportFailed(String)
    var errorDescription: String? {
        switch self {
        case .fileNotFound:        return "Audio file not found."
        case .noExportSession:     return "Could not create export session."
        case .exportFailed(let m): return "Export failed: \(m)"
        }
    }
}

final class AudioProcessor {
    static let maxDurationSeconds: Double = 300        // 5:00 — hard cap per chunk regardless of recording interval
    static let maxFileSizeBytes:   Int64  =  4_500_000 // 4.5 MB — Vercel upload limit

    static func validate(entry: LocalRecordingEntry, displayName: String) -> AudioValidationResult {
        var issues: [AudioValidationResult.Issue] = []
        let ext = entry.fileURL.pathExtension.lowercased()
        if ext != "m4a" && ext != "mp3" { issues.append(.wrongFormat(ext: ext)) }
        if entry.durationSeconds > maxDurationSeconds { issues.append(.tooLong(seconds: entry.durationSeconds)) }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: entry.fileURL.path)[.size] as? Int64) ?? 0
        if fileSize > maxFileSizeBytes { issues.append(.tooLarge(bytes: fileSize)) }
        return AudioValidationResult(recordingId: entry.id, displayName: displayName,
                                     fileURL: entry.fileURL, durationSeconds: entry.durationSeconds,
                                     fileSizeBytes: fileSize, issues: issues)
    }

    static func convertToM4A(sourceURL: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { throw AudioProcessorError.fileNotFound }
        let outputURL = sourceURL.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: outputURL)
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioProcessorError.noExportSession
        }
        session.outputURL = outputURL; session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else {
            throw AudioProcessorError.exportFailed(session.error?.localizedDescription ?? "Unknown")
        }
        return outputURL
    }

    static func split(sourceURL: URL, maxDuration: Double = maxDurationSeconds) async throws -> [URL] {
        let asset = AVURLAsset(url: sourceURL)
        let totalSeconds = CMTimeGetSeconds(try await asset.load(.duration))
        guard totalSeconds > maxDuration else { return [sourceURL] }
        // Split into N equal-sized chunks so no single chunk is near the limit
        let numChunks = Int(ceil(totalSeconds / maxDuration))
        let chunkSecs = totalSeconds / Double(numChunks)
        var chunks: [URL] = []
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let dir = sourceURL.deletingLastPathComponent()
        for i in 0..<numChunks {
            let startSecs = Double(i) * chunkSecs
            let endSecs   = i == numChunks - 1 ? totalSeconds : Double(i + 1) * chunkSecs
            let chunkURL  = dir.appendingPathComponent("\(baseName)_part\(i + 1).m4a")
            try? FileManager.default.removeItem(at: chunkURL)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { continue }
            session.outputURL  = chunkURL
            session.outputFileType = .m4a
            session.timeRange  = CMTimeRange(start: CMTime(seconds: startSecs, preferredTimescale: 600),
                                             end:   CMTime(seconds: endSecs,   preferredTimescale: 600))
            await session.export()
            if session.status == .completed { chunks.append(chunkURL) }
        }
        return chunks
    }

    // MARK: - Compression options (speed, mono, silence removal)

    static func applyCompressionOptions(sourceURL: URL) async -> URL {
        let speed   = UserDefaults.standard.integer(forKey: "compression_speed")   // 0=off 1=1.5x 2=2x
        let mono    = UserDefaults.standard.bool(forKey: "compression_mono")
        let silence = UserDefaults.standard.bool(forKey: "compression_silence")
        guard speed > 0 || mono || silence else { return sourceURL }
        var url = sourceURL
        if silence  { url = (try? await stripSilence(from: url)) ?? url }
        let factor: Double = speed == 2 ? 2.0 : speed == 1 ? 1.5 : 1.0
        if factor > 1.0 || mono { url = (try? await reencodeAudio(sourceURL: url, speedFactor: factor, forceMono: mono)) ?? url }
        return url
    }

    private static func reencodeAudio(sourceURL: URL, speedFactor: Double, forceMono: Bool) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let srcTrack = audioTracks.first else { return sourceURL }

        // Build a composition — scale time range for speed change
        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return sourceURL }
        try compTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: srcTrack, at: .zero)
        if speedFactor > 1.0 {
            let scaled = CMTime(seconds: CMTimeGetSeconds(duration) / speedFactor, preferredTimescale: 600)
            compTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: duration), toDuration: scaled)
        }

        let tag = [speedFactor > 1.0 ? "spd" : nil, forceMono ? "mono" : nil].compactMap { $0 }.joined(separator: "_")
        let outputURL = sourceURL.deletingPathExtension().appendingPathExtension("\(tag).m4a")
        try? FileManager.default.removeItem(at: outputURL)

        if forceMono {
            let compTracks = try await composition.loadTracks(withMediaType: .audio)
            guard let compAudioTrack = compTracks.first else { return sourceURL }
            let reader = try AVAssetReader(asset: composition)
            let readerOut = AVAssetReaderTrackOutput(track: compAudioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44100.0
            ])
            reader.add(readerOut)
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
            let writerIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ])
            writer.add(writerIn)
            guard reader.startReading() else { return sourceURL }
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                writerIn.requestMediaDataWhenReady(on: DispatchQueue(label: "scrivano.audio.mono")) {
                    while writerIn.isReadyForMoreMediaData {
                        guard let buf = readerOut.copyNextSampleBuffer() else {
                            writerIn.markAsFinished(); cont.resume(); return
                        }
                        writerIn.append(buf)
                    }
                }
            }
            await writer.finishWriting()
            return writer.status == .completed ? outputURL : sourceURL
        } else {
            // Speed only — export scaled composition
            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { return sourceURL }
            session.outputURL = outputURL; session.outputFileType = .m4a
            await session.export()
            return session.status == .completed ? outputURL : sourceURL
        }
    }

    private static func stripSilence(from sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else { return sourceURL }

        // Analyse audio at 16 kHz mono for speed
        let analysisRate: Double = 16000
        let reader = try AVAssetReader(asset: asset)
        let readerOut = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: analysisRate
        ])
        reader.add(readerOut)
        guard reader.startReading() else { return sourceURL }

        var samples: [Int16] = []
        samples.reserveCapacity(Int(totalSeconds * analysisRate) + 1000)
        while let buf = readerOut.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buf) else { continue }
            let len = CMBlockBufferGetDataLength(block)
            var dataPointer: UnsafeMutablePointer<CChar>? = nil
            var dataLength = 0
            var totalLength = 0
            let status = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &dataLength, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
            guard status == kCMBlockBufferNoErr, let ptr = dataPointer else { continue }
            let sampleCount = len / MemoryLayout<Int16>.size
            ptr.withMemoryRebound(to: Int16.self, capacity: sampleCount) { p16 in
                samples.append(contentsOf: UnsafeBufferPointer(start: p16, count: sampleCount))
            }
        }
        guard !samples.isEmpty else { return sourceURL }

        // 300ms windows, -46dB threshold, 150ms padding around voiced segments
        let windowSamples = Int(analysisRate * 0.3)
        let threshold: Float = 0.005
        let paddingSec: Double = 0.15

        var voiced: [(Double, Double)] = []
        var i = 0
        while i < samples.count {
            let winEnd = min(i + windowSamples, samples.count)
            let window = samples[i..<winEnd]
            let sumSq = window.reduce(Float(0)) { acc, s in let f = Float(s) / 32768.0; return acc + f * f }
            let rms = sqrt(sumSq / Float(window.count))
            if rms >= threshold {
                let startSec = max(0, Double(i) / analysisRate - paddingSec)
                var j = i + windowSamples
                while j < samples.count {
                    let e2 = min(j + windowSamples, samples.count)
                    let w2 = samples[j..<e2]
                    let s2 = w2.reduce(Float(0)) { acc, s in let f = Float(s) / 32768.0; return acc + f * f }
                    if sqrt(s2 / Float(w2.count)) < threshold { break }
                    j += windowSamples
                }
                let endSec = min(totalSeconds, Double(j) / analysisRate + paddingSec)
                if let last = voiced.last, startSec <= last.1 {
                    voiced[voiced.count - 1].1 = max(last.1, endSec)
                } else {
                    voiced.append((startSec, endSec))
                }
                i = j
            } else {
                i += winEnd - i
            }
        }

        guard !voiced.isEmpty else { return sourceURL }
        let keptSecs = voiced.reduce(0.0) { $0 + $1.1 - $1.0 }
        guard keptSecs < totalSeconds * 0.9 else { return sourceURL }  // <10% removed — not worth re-encoding

        // Rebuild composition from voiced segments
        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return sourceURL }
        var insertAt = CMTime.zero
        for (start, end) in voiced {
            let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 44100),
                                    end:   CMTime(seconds: end,   preferredTimescale: 44100))
            try? compTrack.insertTimeRange(range, of: track, at: insertAt)
            insertAt = insertAt + CMTime(seconds: end - start, preferredTimescale: 44100)
        }

        let outputURL = sourceURL.deletingPathExtension().appendingPathExtension("clean.m4a")
        try? FileManager.default.removeItem(at: outputURL)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { return sourceURL }
        session.outputURL = outputURL; session.outputFileType = .m4a
        await session.export()
        return session.status == .completed ? outputURL : sourceURL
    }

    static func prepare(entry: LocalRecordingEntry, displayName: String) async throws -> [(url: URL, duration: Double, name: String)] {
        var workingURL = entry.fileURL
        if workingURL.pathExtension.lowercased() != "m4a" {
            workingURL = try await convertToM4A(sourceURL: workingURL)
        }

        // Apply compression options (silence stripping, mono, speed) before splitting.
        // Track the pre-compression URL so we can delete the intermediate temp file if
        // compression produced a new file (avoids orphaned temps on disk).
        let preCompressionURL = workingURL
        workingURL = await applyCompressionOptions(sourceURL: workingURL)
        if workingURL != preCompressionURL && preCompressionURL != entry.fileURL {
            try? FileManager.default.removeItem(at: preCompressionURL)
        }

        let nameBase: String = {
            if let dotIdx = displayName.lastIndex(of: ".") {
                return String(displayName[displayName.startIndex..<dotIdx])
            }
            return displayName
        }()
        let correctedName = "\(nameBase).m4a"

        // Load actual duration from the (possibly compressed) file
        let actualDuration: Double = await {
            let a = AVURLAsset(url: workingURL)
            if let d = try? await a.load(.duration) { return CMTimeGetSeconds(d) }
            return entry.durationSeconds
        }()

        // Determine effective max duration — tighten if file exceeds size limit
        var effectiveMaxDuration = maxDurationSeconds
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: workingURL.path)[.size] as? Int64) ?? 0
        if fileSize > maxFileSizeBytes && actualDuration > 0 {
            let bytesPerSecond = Double(fileSize) / actualDuration
            let sizeLimitedDuration = floor(Double(maxFileSizeBytes) / bytesPerSecond)
            effectiveMaxDuration = min(effectiveMaxDuration, max(sizeLimitedDuration, 60))
        }

        let needsSplit = actualDuration > effectiveMaxDuration || fileSize > maxFileSizeBytes
        if needsSplit {
            let chunks = try await split(sourceURL: workingURL, maxDuration: effectiveMaxDuration)
            // Delete the pre-split working file — callers will delete the individual chunks after upload
            if workingURL != entry.fileURL {
                try? FileManager.default.removeItem(at: workingURL)
            }
            return chunks.enumerated().map { i, url in
                let dur = i == chunks.count - 1
                    ? max(actualDuration - Double(i) * effectiveMaxDuration, 1)
                    : effectiveMaxDuration
                return (url: url, duration: dur, name: "\(nameBase)_part\(i + 1).m4a")
            }
        }
        return [(url: workingURL, duration: actualDuration, name: correctedName)]
    }
}

extension Double {
    var formattedAsHMS: String {
        let t = Int(self), h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Local image file model (alias for persistence)
typealias ImageFile = LocalImageEntry

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

// MARK: - UIImagePickerController wrapper
struct ImagePickerView: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onPick(image) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - MediaListView
struct MediaListView: View {
    let item: Item
    var triggerAudioImport: Bool = false
    var triggerImageImport: Bool = false
    @Environment(\.dismiss) var dismiss
    @State private var selected = Set<String>()
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var showRecorder = false
    @State private var localRecordings: [LocalRecordingEntry] = []

    // Image support
    @State private var imageFiles: [ImageFile] = []
    @State private var showPhotoLibrary = false
    @State private var showAudioImporter = false
    @State private var selectedImages = Set<String>()

    // Serial audio queue
    @State private var mediaQueue: [LocalRecordingEntry] = []
    @State private var queuedIds: Set<String> = []
    @State private var activeQueueItem: LocalRecordingEntry? = nil
    @State private var queuePreparationResults: [AudioValidationResult] = []

    // Player
    @State private var playerRecording: LocalRecordingEntry? = nil
    @State private var playerTranscript: TranscriptSummary? = nil
    @State private var playerInitialEditMode: LocalAudioPlayerView.EditMode = .none

    // Process confirm
    @State private var showProcessConfirm = false

    // Preparation
    @State private var preparationResults: [AudioValidationResult] = []
    @State private var showPreparation = false

    // Observe shared transcription/image state
    @ObservedObject private var transcriptionMgr = TranscriptionManager.shared
    @ObservedObject private var imageMgr = ImageProcessingManager.shared
    @ObservedObject private var langMgr = LanguageManager.shared

    // Conversion
    @State private var convertingRecordingId: String? = nil
    @State private var convertError: String? = nil

    // Bulk action selection mode
    enum BulkAction { case move, delete }
    @State private var pendingAction: BulkAction? = nil
    @State private var showBulkMove = false
    @State private var showDeleteConfirm = false

    // Rename overlay
    @State private var renameRecording: LocalRecordingEntry? = nil
    @State private var renameImage: LocalImageEntry? = nil
    @State private var renameMediaText = ""

    private var inSelectionMode: Bool { pendingAction != nil }

    private var allAudioIds: [String] { localRecordings.map(\.id) }
    private var hasProcessableMedia: Bool { !localRecordings.isEmpty }

    private var selectedLocalRecordings: [LocalRecordingEntry] {
        localRecordings.filter { selected.contains($0.id) }
    }
    private var selectedImageFiles: [ImageFile] {
        imageFiles.filter { selectedImages.contains($0.id) }
    }

    private func displayName(for rec: LocalRecordingEntry) -> String {
        if let lbl = rec.label { return lbl }
        let idx = (localRecordings.firstIndex(where: { $0.id == rec.id }) ?? 0) + 1
        let ext = rec.fileURL.pathExtension.isEmpty ? "m4a" : rec.fileURL.pathExtension
        return "Audio-\(item.name)-\(String(format: "%02d", idx)).\(ext)"
    }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                SubScreenBar(title: langMgr.t("automation.stage.media"), accentColor: .stageMedia, onBack: { dismiss() })
                    .overlay(alignment: .trailing) {
                        Menu {
                            Button { showAudioImporter = true } label: { Label(langMgr.t("media.importAudioFile"), systemImage: "waveform") }
                            Button { showPhotoLibrary = true } label: { Label(langMgr.t("media.importImage"), systemImage: "photo") }
                            Button {
                                selected.removeAll()
                                pendingAction = .move
                            } label: {
                                Label(langMgr.t("common.move"), systemImage: "folder")
                            }
                            .disabled(allAudioIds.isEmpty)
                            Button(role: .destructive) {
                                selected.removeAll()
                                pendingAction = .delete
                            } label: {
                                Label(langMgr.t("common.delete"), systemImage: "trash")
                            }
                            .disabled(allAudioIds.isEmpty)
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
                        Rectangle().fill(Color.stageMedia.opacity(0.4)).frame(height: 1)
                    }

                // File list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        audioFileRows
                        imageFileRows
                    }
                }
                .overlay {
                    if localRecordings.isEmpty && imageFiles.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "tray")
                                .font(.system(size: 40))
                                .foregroundColor(.textQuaternary)
                            Text(langMgr.t("media.noAudio"))
                                .font(.inter(16, weight: .bold))
                                .foregroundColor(.textTertiary)
                            Text(langMgr.t("media.noAudio.hint"))
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
                    localRecordings = LocalRecordingStore.shared.recordings(for: item.id)
                    imageFiles = LocalImageStore.shared.images(for: item.id)
                }

                // Bottom bar
                VStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

                    if inSelectionMode {
                        VStack(spacing: 6) {
                            Text(pendingAction == .delete
                                 ? langMgr.t("media.selectToDelete")
                                 : langMgr.t("media.selectToMove"))
                                .font(.inter(12, weight: .semibold))
                                .foregroundColor(.textTertiary)
                                .padding(.top, 10)

                            HStack(spacing: 10) {
                                Button {
                                    selected.removeAll()
                                    pendingAction = nil
                                } label: {
                                    Text(langMgr.t("common.cancel"))
                                        .font(.inter(14, weight: .semibold))
                                        .foregroundColor(.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Color.white.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }

                                Button {
                                    if pendingAction == .delete {
                                        showDeleteConfirm = true
                                    } else {
                                        showBulkMove = true
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: pendingAction == .delete ? "trash" : "folder")
                                            .font(.system(size: 13, weight: .bold))
                                        Text(pendingAction == .delete
                                             ? langMgr.t("media.deleteCount").replacingOccurrences(of: "%d", with: "\(selected.count)")
                                             : langMgr.t("media.moveCount").replacingOccurrences(of: "%d", with: "\(selected.count)"))
                                            .font(.inter(14, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(
                                        pendingAction == .delete
                                            ? Color.danger.opacity(selected.isEmpty ? 0.3 : 0.8)
                                            : Color.brandBlue.opacity(selected.isEmpty ? 0.3 : 0.8)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .disabled(selected.isEmpty)
                            }

                            Text(langMgr.t("media.filesSelected").replacingOccurrences(of: "%d", with: "\(selected.count)"))
                                .font(.inter(11))
                                .foregroundColor(.textQuaternary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        let isThisItem = transcriptionMgr.transcribingItemName == item.name
                        if isThisItem, let err = transcriptionMgr.transcribingError {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundColor(.danger)
                                Text(err).font(.inter(11)).foregroundColor(.danger).lineLimit(1)
                            }
                            .padding(.horizontal, 18).padding(.top, 8)
                        } else if isThisItem, !transcriptionMgr.transcribingStatus.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().progressViewStyle(.circular).tint(.stageMedia).scaleEffect(0.7)
                                Text(transcriptionMgr.transcribingStatus).font(.inter(11)).foregroundColor(.textTertiary)
                            }
                            .padding(.horizontal, 18).padding(.top, 8)
                        } else if isThisItem, transcriptionMgr.transcriptionResult == true {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(Color(hex: "#34d399"))
                                Text(langMgr.t("recording.saved")).font(.inter(11)).foregroundColor(Color(hex: "#34d399"))
                            }
                            .padding(.horizontal, 18).padding(.top, 8)
                        } else if imageMgr.processingItemId == item.id {
                            if let err = imageMgr.failedError {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundColor(.danger)
                                    Text(err).font(.inter(11)).foregroundColor(.danger).lineLimit(1)
                                }
                                .padding(.horizontal, 18).padding(.top, 8)
                            } else if imageMgr.processingResult == true {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(Color(hex: "#34d399"))
                                    Text(langMgr.t("recording.imageSaved")).font(.inter(11)).foregroundColor(Color(hex: "#34d399"))
                                }
                                .padding(.horizontal, 18).padding(.top, 8)
                            }
                        } else if let err = error {
                            Text(err).font(.inter(11)).foregroundColor(.danger).padding(.horizontal, 18).padding(.top, 8)
                        }

                        VStack(spacing: 6) {
                            Button {
                                // Select all audio if nothing selected
                                if selected.isEmpty { selected = Set(allAudioIds) }
                                if hasProcessableMedia {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showProcessConfirm = true }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "bolt.fill").font(.system(size: 14, weight: .bold))
                                    Text(langMgr.t("media.processMedia")).font(.inter(15, weight: .heavy))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(LinearGradient(
                                    colors: [Color.stageMedia.opacity(0.25), Color.stageMedia.opacity(0.10)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.stageMedia.opacity(0.40), lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .opacity(hasProcessableMedia ? 1.0 : 0.35)
                            }
                            .disabled(!hasProcessableMedia)

                            Text(selected.isEmpty ? langMgr.t("media.tapToSelectAll") : langMgr.t("media.audioFilesSelected").replacingOccurrences(of: "%d", with: "\(selected.count)"))
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

            if isLoading { LoadingOverlay(message: langMgr.t("media.loadingFiles")) }

            renameMediaOverlay

            // Process confirm card
            if showProcessConfirm {
                Color.black.opacity(0.65).ignoresSafeArea().zIndex(10)
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.stageMedia)
                            .shadow(color: Color.stageMedia.opacity(0.7), radius: 10)

                        Text(langMgr.t("media.processMedia"))
                            .font(.inter(16, weight: .heavy))
                            .foregroundColor(.textPrimary)

                        Text(langMgr.t("media.continueWith").replacingOccurrences(of: "%d", with: "\(selected.count)"))
                            .font(.inter(13))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(localRecordings.filter { selected.contains($0.id) }, id: \.id) { rec in
                                    processFileRow(name: displayName(for: rec), icon: "waveform", id: rec.id)
                                }
                            }
                        }
                        .frame(maxHeight: 160)

                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showProcessConfirm = false }
                            } label: {
                                Text(langMgr.t("common.cancel"))
                                    .font(.inter(14, weight: .semibold))
                                    .foregroundColor(.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.white.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showProcessConfirm = false }
                                let audioQueue = localRecordings.filter { selected.contains($0.id) }
                                guard !audioQueue.isEmpty else { return }
                                // Validate ALL recordings upfront so the preparation card, if needed,
                                // shows once before any processing starts — not mid-queue after the first file finishes.
                                let allResults = audioQueue.map { AudioProcessor.validate(entry: $0, displayName: displayName(for: $0)) }
                                queuePreparationResults = allResults
                                preparationResults = allResults
                                queuedIds = Set(audioQueue.map(\.id))
                                mediaQueue = audioQueue
                                TranscriptionManager.shared.queuedRecordingIds.formUnion(queuedIds)
                                let hasFormatIssues = allResults.contains { $0.needsConversion }
                                let hasIssues = allResults.contains { !$0.isReady }
                                if hasIssues && hasFormatIssues {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showPreparation = true }
                                } else {
                                    processQueueNext()
                                }
                            } label: {
                                Text(langMgr.t("dashboard.record.continue"))
                                    .font(.inter(14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(LinearGradient(
                                        colors: [Color.stageMedia.opacity(0.8), Color.stageMedia.opacity(0.6)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(24)
                    .background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.stageMedia.opacity(0.35), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.stageMedia.opacity(0.15), radius: 20)
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

                        Text(langMgr.t("media.deleteFiles"))
                            .font(.inter(16, weight: .heavy))
                            .foregroundColor(.textPrimary)

                        Text(langMgr.t("media.deleteFilesMsg").replacingOccurrences(of: "%d", with: "\(selected.count)"))
                            .font(.inter(13))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(localRecordings.filter { selected.contains($0.id) }, id: \.id) { rec in
                                    processFileRow(name: displayName(for: rec), icon: "waveform", id: rec.id)
                                }
                            }
                        }
                        .frame(maxHeight: 160)

                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteConfirm = false }
                            } label: {
                                Text(langMgr.t("common.cancel"))
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
                                    if let rec = localRecordings.first(where: { $0.id == id }) {
                                        deleteRecording(rec)
                                    }
                                }
                                selected.removeAll()
                                pendingAction = nil
                            } label: {
                                Text(langMgr.t("common.delete"))
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
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDeleteConfirm)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showProcessConfirm)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showPreparation)
        // Preparation card
        .overlay {
            if showPreparation {
                ZStack {
                    Color.black.opacity(0.65).ignoresSafeArea()
                    VStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 30))
                                .foregroundColor(.stageMedia)
                                .shadow(color: Color.stageMedia.opacity(0.7), radius: 10)

                            Text(langMgr.t("media.preparationRequired"))
                                .font(.inter(16, weight: .heavy))
                                .foregroundColor(.textPrimary)

                            Text(langMgr.t("media.processMedia.hint"))
                                .font(.inter(12))
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)

                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 8) {
                                    ForEach(preparationResults, id: \.recordingId) { result in
                                        preparationRow(result: result)
                                    }
                                }
                            }
                            .frame(maxHeight: 220)

                            HStack(spacing: 10) {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showPreparation = false }
                                    // Abort the queue if the user cancels the preparation card.
                                    mediaQueue.removeAll()
                                    queuedIds.removeAll()
                                    queuePreparationResults.removeAll()
                                    activeQueueItem = nil
                                } label: {
                                    Text(langMgr.t("common.cancel"))
                                        .font(.inter(14, weight: .semibold))
                                        .foregroundColor(.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Color.white.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showPreparation = false }
                                    // Queue mode: start the pre-built queue. Single mode: transcribe directly.
                                    if !mediaQueue.isEmpty {
                                        processQueueNext()
                                    } else {
                                        startTranscription()
                                    }
                                } label: {
                                    Text(langMgr.t("dashboard.record.continue"))
                                        .font(.inter(14, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(
                                            LinearGradient(
                                                colors: [Color.stageMedia.opacity(0.85), Color.stageMedia.opacity(0.6)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            )
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                        }
                        .padding(24)
                        .background(Color(hex: "#081221"))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.stageMedia.opacity(0.35), lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: Color.stageMedia.opacity(0.15), radius: 20)
                        .padding(.horizontal, 24)
                        Spacer()
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if triggerAudioImport {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showAudioImporter = true }
            } else if triggerImageImport {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showPhotoLibrary = true }
            }
        }
        // Player sheets
        .fullScreenCover(item: $playerRecording) { rec in
            LocalAudioPlayerView(
                entry: rec,
                displayName: displayName(for: rec),
                autoPlay: true,
                initialEditMode: playerInitialEditMode,
                onRecordingsChanged: {
                    localRecordings = LocalRecordingStore.shared.recordings(for: item.id)
                }
            )
        }
        .onChange(of: playerRecording?.id) { id in if id == nil { playerInitialEditMode = .none } }
        .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio, .mpeg4Movie, .movie], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await handleAudioImport(url: url) }
            case .failure:
                break
            }
        }
        .sheet(isPresented: $showPhotoLibrary) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                let idx = LocalImageStore.shared.count(for: item.id) + 1
                let imgName = "Image-\(item.name)-\(String(format: "%02d", idx))"
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let imgDir = docs.appendingPathComponent("images/\(item.id)", isDirectory: true)
                try? FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)
                let fileName = "img_\(Int(Date().timeIntervalSince1970)).jpg"
                let destURL = imgDir.appendingPathComponent(fileName)
                if let data = image.jpegData(compressionQuality: 0.85) {
                    try? data.write(to: destURL)
                }
                let entry = LocalImageEntry(id: UUID().uuidString, itemId: item.id, name: imgName, localPath: destURL.path, createdAt: Date())
                LocalImageStore.shared.add(entry)
                imageFiles = LocalImageStore.shared.images(for: item.id)
            }
        }
        .sheet(isPresented: $showRecorder) { RecordingView(item: item) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("scrivano.pendingImportsDone"))) { _ in
            localRecordings = LocalRecordingStore.shared.recordings(for: item.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                localRecordings = LocalRecordingStore.shared.recordings(for: item.id)
            }
        }
        // Advance audio queue when transcription completes or fails
        .onChange(of: transcriptionMgr.transcriptSaveCounter) { _ in
            if let rec = activeQueueItem, transcriptionMgr.transcribedRecordingIds.contains(rec.id) {
                activeQueueItem = nil
                processQueueNext()
            }
        }
        .onChange(of: transcriptionMgr.failedRecordingIds) { ids in
            if let rec = activeQueueItem, ids.contains(rec.id) {
                activeQueueItem = nil
                processQueueNext()
            }
        }
        .alert("Conversion Failed", isPresented: .init(get: { convertError != nil }, set: { if !$0 { convertError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(convertError ?? "") }
        .sheet(isPresented: $showBulkMove) {
            BulkMoveAudioSheet(ids: Array(selected), currentItemId: item.id) {
                selected.removeAll()
                pendingAction = nil
                localRecordings = LocalRecordingStore.shared.recordings(for: item.id)
            }
        }
    }

    private func toggleSelect(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    @ViewBuilder
    private var audioFileRows: some View {
        ForEach(Array(localRecordings.enumerated()), id: \.element.id) { idx, rec in
            SwipeToDelete(onDelete: { deleteRecording(rec) }) {
                LocalAudioRow(
                    entry: rec, index: idx + 1, itemName: item.name,
                    isSelected: selected.contains(rec.id),
                    isTranscribing: transcriptionMgr.transcribingRecordingId == rec.id,
                    isTranscribed: transcriptionMgr.transcribedRecordingIds.contains(rec.id),
                    isFailed: transcriptionMgr.failedRecordingIds.contains(rec.id),
                    isQueued: transcriptionMgr.queuedRecordingIds.contains(rec.id),
                    isConverting: convertingRecordingId == rec.id,
                    onSelect: { toggleSelect(rec.id) },
                    onPlay: { playerInitialEditMode = .none; playerRecording = rec },
                    onSplit: { playerInitialEditMode = .split; playerRecording = rec },
                    onTrim:  { playerInitialEditMode = .trim;  playerRecording = rec },
                    onDelete: { deleteRecording(rec) },
                    onRenamed: { localRecordings = LocalRecordingStore.shared.recordings(for: item.id) },
                    onTranscribe: { selected = [rec.id]; validateAndProceed() },
                    onMoveTo: { localRecordings = LocalRecordingStore.shared.recordings(for: item.id) },
                    onConvert: { convertRecordingToM4A(rec) },
                    onRenameRequested: {
                        let lbl = rec.label ?? ""
                        renameRecording = rec
                        let ext = rec.fileURL.pathExtension.lowercased()
                        renameMediaText = lbl.hasSuffix(".\(ext)") ? String(lbl.dropLast(ext.count + 1)) : lbl
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var imageFileRows: some View {
        ForEach(Array(imageFiles.enumerated()), id: \.element.id) { idx, img in
            SwipeToDelete(onDelete: { deleteImage(img) }) {
                ImageFileRow(
                    imageFile: img, item: item, index: idx + 1,
                    isSelected: selectedImages.contains(img.id),
                    isQueued: imageMgr.pendingImageIds.contains(img.id),
                    onSelect: {
                        if selectedImages.contains(img.id) { selectedImages.remove(img.id) }
                        else { selectedImages.insert(img.id) }
                    },
                    onDelete: { deleteImage(img) },
                    onMoved: { imageFiles = LocalImageStore.shared.images(for: item.id) },
                    onRenamed: { imageFiles = LocalImageStore.shared.images(for: item.id) },
                    onRenameRequested: { renameImage = img; renameMediaText = img.name }
                )
            }
        }
    }

    @ViewBuilder
    private var renameMediaOverlay: some View {
        if renameRecording != nil || renameImage != nil {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture { renameRecording = nil; renameImage = nil }
                .zIndex(20)
            VStack {
                Spacer()
                renameMediaCard
                Spacer()
            }
            .zIndex(21)
        }
    }

    private var renameMediaCard: some View {
        VStack(spacing: 16) {
            Text(renameRecording != nil ? langMgr.t("media.renameAudio") : langMgr.t("media.renameImage"))
                .font(.inter(16, weight: .heavy))
                .foregroundColor(.textPrimary)
            TextField("", text: $renameMediaText)
                .font(.inter(14))
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.stageMedia.opacity(0.35), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
            HStack(spacing: 10) {
                Button { renameRecording = nil; renameImage = nil } label: {
                    Text(langMgr.t("common.cancel"))
                        .font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button {
                    let trimmed = renameMediaText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    if var rec = renameRecording {
                        let ext = rec.fileURL.pathExtension.lowercased().isEmpty ? "m4a" : rec.fileURL.pathExtension.lowercased()
                        rec.label = trimmed.hasSuffix(".\(ext)") ? trimmed : "\(trimmed).\(ext)"
                        LocalRecordingStore.shared.update(rec)
                        localRecordings = LocalRecordingStore.shared.recordings(for: item.id)
                        renameRecording = nil
                    } else if var img = renameImage {
                        img.name = trimmed
                        LocalImageStore.shared.update(img)
                        imageFiles = LocalImageStore.shared.images(for: item.id)
                        renameImage = nil
                    }
                } label: {
                    Text(langMgr.t("common.rename"))
                        .font(.inter(14, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(LinearGradient(colors: [Color.brandBlue, Color.brandCyan], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(renameMediaText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .background(Color(hex: "#081221"))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.stageMedia.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color.stageMedia.opacity(0.15), radius: 20)
        .padding(.horizontal, 24)
    }

    private func deleteRecording(_ rec: LocalRecordingEntry) {
        selected.remove(rec.id)
        TrashStore.shared.trashRecording(rec, itemName: item.name)
        localRecordings = LocalRecordingStore.shared.recordings(for: item.id)
    }

    private func convertRecordingToM4A(_ rec: LocalRecordingEntry) {
        guard convertingRecordingId == nil else { return }
        let ext = rec.fileURL.pathExtension.lowercased()
        guard ext != "m4a" && ext != "mp3" else { return }
        convertingRecordingId = rec.id
        Task {
            do {
                let originalURL = rec.fileURL
                let m4aURL = try await AudioProcessor.convertToM4A(sourceURL: originalURL)
                // Update store entry to point to new file
                var updated = rec
                updated.relativePath = LocalRecordingStore.relativePath(of: m4aURL)
                // Update label extension if it was set
                if let lbl = updated.label {
                    let base = lbl.hasSuffix(".\(ext)") ? String(lbl.dropLast(ext.count + 1)) : lbl
                    updated.label = "\(base).m4a"
                }
                LocalRecordingStore.shared.update(updated)
                // Delete original WAV file
                try? FileManager.default.removeItem(at: originalURL)
                await MainActor.run {
                    localRecordings = LocalRecordingStore.shared.recordings(for: item.id)
                    convertingRecordingId = nil
                }
            } catch {
                await MainActor.run {
                    convertError = error.localizedDescription
                    convertingRecordingId = nil
                }
            }
        }
    }

    private func deleteImage(_ img: ImageFile) {
        if let path = img.localPath { try? FileManager.default.removeItem(atPath: path) }
        LocalImageStore.shared.delete(id: img.id)
        imageFiles = LocalImageStore.shared.images(for: item.id)
    }

    @MainActor
    private func handleAudioImport(url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased().isEmpty ? "m4a" : url.pathExtension.lowercased()
        let destURL = LocalRecordingStore.newFileURL(itemId: item.id, ext: ext)
        do {
            try FileManager.default.copyItem(at: url, to: destURL)
        } catch {
            return
        }

        let asset = AVURLAsset(url: destURL)
        let duration: Double
        if let cmDur = try? await asset.load(.duration) {
            duration = CMTimeGetSeconds(cmDur)
        } else {
            duration = 0
        }

        let originalName = url.deletingPathExtension().lastPathComponent
        let entry = LocalRecordingEntry(
            id: UUID().uuidString,
            itemId: item.id,
            relativePath: LocalRecordingStore.relativePath(of: destURL),
            createdAt: Date(),
            durationSeconds: duration,
            label: "\(originalName).\(ext)"
        )
        LocalRecordingStore.shared.add(entry)
        localRecordings = LocalRecordingStore.shared.recordings(for: item.id)
    }

    // MARK: - Validation

    private func validateAndProceed() {
        appLog("validateAndProceed()")
        appLog("  selectedLocalRecordings.count: \(selectedLocalRecordings.count)")
        appLog("  selected IDs: \(selected.sorted().joined(separator: ", "))")
        appLog("  localRecordings IDs: \(localRecordings.map(\.id).joined(separator: ", "))")

        let results = selectedLocalRecordings.map { rec in
            AudioProcessor.validate(entry: rec, displayName: displayName(for: rec))
        }
        preparationResults = results

        for r in results {
            appLog("  validated: \(r.displayName) ready=\(r.isReady) issues=\(r.issues.map { "\($0)" }.joined(separator: ","))")
        }

        let hasFormatIssues = results.contains { $0.needsConversion }
        let hasIssues = results.contains { !$0.isReady }
        if hasIssues && hasFormatIssues {
            // Format conversion needed — show preparation card so the user is aware
            appLog("  → showing preparation card (format conversion required)")
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showPreparation = true }
        } else {
            // Either all ready, or only size/duration issues on m4a — auto-split handled by prepare()
            if hasIssues { appLog("  → auto-splitting (too long/large, already m4a)") }
            else { appLog("  → all ready, calling startTranscription()") }
            startTranscription()
        }
    }

    // MARK: - Transcription
    private func startTranscription() {
        appLog("startTranscription() → delegating to TranscriptionManager")
        guard !preparationResults.isEmpty else {
            appLog("  ⚠ preparationResults empty — abort", level: .warning)
            return
        }
        TranscriptionManager.shared.transcribeRecordings(
            item: item,
            preparationResults: preparationResults,
            recordings: localRecordings
        )
    }

    // MARK: - Serial audio queue
    private func processQueueNext() {
        guard !mediaQueue.isEmpty else { activeQueueItem = nil; return }
        let next = mediaQueue.removeFirst()
        queuedIds.remove(next.id)
        activeQueueItem = next
        selected = [next.id]
        // Use the pre-computed result for this recording (validated before the queue started).
        // This prevents the preparation card from appearing mid-queue for files that need conversion.
        if let precomputed = queuePreparationResults.first(where: { $0.recordingId == next.id }) {
            preparationResults = [precomputed]
            startTranscription()
        } else {
            validateAndProceed()
        }
    }

    // MARK: - Preparation row

    @ViewBuilder
    private func preparationRow(result: AudioValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: result.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(result.isReady ? .stageNotes : .stageText)
                Text(result.displayName)
                    .font(.inter(13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            if result.isReady {
                Text(langMgr.t("media.readyToTranscribe"))
                    .font(.inter(11))
                    .foregroundColor(.stageNotes)
                    .padding(.leading, 21)
            } else {
                HStack(spacing: 6) {
                    if result.needsConversion {
                        issueChip(
                            label: "Convert \(result.fileURL.pathExtension.uppercased()) → M4A",
                            color: .stageText
                        )
                    }
                    if result.needsSplit {
                        let hasSizeIssue = result.issues.contains { if case .tooLarge = $0 { return true }; return false }
                        let sizeLabel = hasSizeIssue ? " · \(result.fileSizeBytes / (1024 * 1024)) MB" : ""
                        issueChip(
                            label: "Split into \(result.splitPartCount) parts (\(result.durationSeconds.formattedAsHMS)\(sizeLabel))",
                            color: Color(hex: "#f97316")
                        )
                    }
                }
                .padding(.leading, 21)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(result.isReady ? Color.stageNotes.opacity(0.05) : Color.stageText.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(result.isReady ? Color.stageNotes.opacity(0.2) : Color.stageText.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func issueChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.inter(10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func processFileRow(name: String, icon: String, id: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.stageMedia)
                .frame(width: 28, height: 28)
                .background(Color.stageMedia.opacity(0.12))
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
}

// MARK: - Local recording row
struct LocalAudioRow: View {
    let entry: LocalRecordingEntry
    let index: Int
    let itemName: String
    var isSelected: Bool
    var isTranscribing: Bool = false
    var isTranscribed: Bool = false
    var isFailed: Bool = false
    var isQueued: Bool = false
    var isConverting: Bool = false
    var onSelect: () -> Void
    var onPlay: () -> Void
    var onSplit: () -> Void = {}
    var onTrim: () -> Void = {}
    var onDelete: () -> Void = {}
    var onRenamed: () -> Void = {}
    var onTranscribe: () -> Void = {}
    var onMoveTo: () -> Void = {}
    var onConvert: () -> Void = {}
    var onRenameRequested: () -> Void = {}

    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var showMoreInfo = false
    @State private var showMoveTo = false
    @State private var hourglassFlipped = false

    private var displayName: String {
        if let lbl = entry.label { return lbl }
        let ext = entry.fileURL.pathExtension.isEmpty ? "m4a" : entry.fileURL.pathExtension
        return "Audio-\(itemName)-\(String(format: "%02d", index)).\(ext)"
    }

    private var formattedDuration: String {
        let s = Int(entry.durationSeconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private var formattedDate: String {
        let df = DateFormatter(); df.dateFormat = "MMM d · h:mm a"
        return df.string(from: entry.createdAt)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.stageMedia.opacity(0.5), Color.stageMedia.opacity(0.25)], center: .center, startRadius: 0, endRadius: 24))
                    .frame(width: 48, height: 48)
                HStack(spacing: 2) {
                    ForEach([0.4, 0.7, 1.0, 0.6, 0.85], id: \.self) { h in
                        Capsule().fill(Color.stageMedia.opacity(0.9))
                            .frame(width: 2.5, height: CGFloat(18) * h)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName).font(.inter(13, weight: .bold)).foregroundColor(.textPrimary).lineLimit(1)
                Text("\(formattedDuration) · \(formattedDate)")
                    .font(.inter(10)).foregroundColor(.textQuaternary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)

            HStack(spacing: 10) {
                ZStack {
                    if isConverting {
                        ProgressView().progressViewStyle(.circular).tint(.stageText)
                            .shadow(color: Color.stageText.opacity(0.6), radius: 5)
                    } else if isTranscribing {
                        ProgressView().progressViewStyle(.circular).tint(.stageMedia)
                            .shadow(color: Color.stageMedia.opacity(0.6), radius: 5)
                    } else if isQueued {
                        Image(systemName: "hourglass").font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.45))
                            .rotationEffect(.degrees(hourglassFlipped ? 180 : 0))
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: false), value: hourglassFlipped)
                            .onAppear { hourglassFlipped = true }
                            .onDisappear { hourglassFlipped = false }
                    } else if isTranscribed {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 17))
                            .foregroundColor(.stageMedia).shadow(color: Color.stageMedia.opacity(0.5), radius: 4)
                    } else if isFailed {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 17))
                            .foregroundColor(Color(hex: "#f87171")).shadow(color: Color(hex: "#f87171").opacity(0.5), radius: 4)
                    }
                }
                .frame(width: 20, height: 20)

                Button { onPlay() } label: {
                    ZStack {
                        Circle().fill(Color.stageMedia.opacity(0.18)).frame(width: 32, height: 32)
                        Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                            .foregroundColor(.stageMedia).offset(x: 1)
                    }
                }
                .buttonStyle(.plain)

                Menu {
                    Section(langMgr.t("media.section.processAudio")) {
                        Button { onTranscribe() } label: { Label(langMgr.t("dashboard.transcribe"), systemImage: "waveform.badge.magnifyingglass") }
                        let fileExt = entry.fileURL.pathExtension.lowercased()
                        if fileExt != "m4a" && fileExt != "mp3" {
                            Button { onConvert() } label: { Label(langMgr.t("media.convertToM4A"), systemImage: "arrow.triangle.2.circlepath") }
                                .disabled(isConverting)
                        }
                        Button { onSplit() } label: { Label(langMgr.t("media.splitAudio"), systemImage: "scissors") }
                        Button { onTrim() }  label: { Label(langMgr.t("media.trimAudio"),  systemImage: "crop") }
                    }
                    Section(langMgr.t("common.section.share")) {
                        ShareLink(item: entry.fileURL) {
                            Label(langMgr.t("common.shareEllipsis"), systemImage: "square.and.arrow.up")
                        }
                    }
                    Section(langMgr.t("common.section.manage")) {
                        Button { onRenameRequested() } label: { Label(langMgr.t("common.rename"), systemImage: "pencil") }
                        Button { showMoveTo = true } label: { Label(langMgr.t("common.moveTo"), systemImage: "folder") }
                        Button(role: .destructive) { DeleteConfirmPresenter.show(itemName: displayName, onDelete: onDelete) } label: { Label(langMgr.t("common.delete"), systemImage: "trash") }
                    }
                    Section(langMgr.t("common.section.info")) {
                        Button { showMoreInfo = true } label: { Label(langMgr.t("common.moreInfo"), systemImage: "info.circle") }
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
        .background(isSelected ? Color.stageMedia.opacity(0.08) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .sheet(isPresented: $showMoreInfo) {
            AudioMoreInfoSheet(entry: entry, displayName: displayName)
        }
        .sheet(isPresented: $showMoveTo) {
            MoveToSheet(entry: entry, onMoved: { onMoveTo() })
        }
    }
}

// MARK: - Audio More Info Sheet
struct AudioMoreInfoSheet: View {
    let entry: LocalRecordingEntry
    let displayName: String
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langMgr = LanguageManager.shared

    struct Meta {
        var fileSize    = "—"
        var dateCreated = "—"
        var dateModified = "—"
        var sampleRate  = "—"
        var channels    = "—"
        var bitRate     = "—"
    }
    @State private var meta = Meta()

    private var format: String { entry.fileURL.pathExtension.uppercased() }
    private var duration: String {
        let s = Int(entry.durationSeconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
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

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 1) {
                        infoRow(langMgr.t("info.name"),       displayName)
                        infoRow(langMgr.t("info.format"),     format)
                        infoRow(langMgr.t("info.duration"),   duration)
                        infoRow(langMgr.t("info.fileSize"),   meta.fileSize)
                        infoRow(langMgr.t("info.sampleRate"), meta.sampleRate)
                        infoRow(langMgr.t("info.channels"),   meta.channels)
                        infoRow(langMgr.t("info.bitRate"),    meta.bitRate)
                        infoRow(langMgr.t("info.created"),    meta.dateCreated)
                        infoRow(langMgr.t("info.modified"),   meta.dateModified)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
                }
                Spacer()
            }
        }
        .task { await loadMeta() }
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

    private func loadMeta() async {
        var m = Meta()
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        m.dateCreated = df.string(from: entry.createdAt)

        if let attrs = try? FileManager.default.attributesOfItem(atPath: entry.fileURL.path) {
            if let mod = attrs[.modificationDate] as? Date { m.dateModified = df.string(from: mod) }
            if let sz = attrs[.size] as? Int64 {
                m.fileSize = ByteCountFormatter.string(fromByteCount: sz, countStyle: .file)
            }
        }
        if let af = try? AVAudioFile(forReading: entry.fileURL) {
            let fmt = af.fileFormat
            m.sampleRate = "\(Int(fmt.sampleRate)) Hz"
            m.channels   = fmt.channelCount == 1 ? "Mono (1)" : fmt.channelCount == 2 ? "Stereo (2)" : "\(fmt.channelCount) ch"
        }
        let asset = AVURLAsset(url: entry.fileURL)
        if let track = try? await asset.loadTracks(withMediaType: .audio).first,
           let br = try? await track.load(.estimatedDataRate), br > 0 {
            m.bitRate = "\(Int(br / 1000)) kbps"
        }
        await MainActor.run { meta = m }
    }
}

// MARK: - Audio player view
struct LocalAudioPlayerView: View {
    let entry: LocalRecordingEntry
    let displayName: String
    var autoPlay: Bool = false
    var initialEditMode: EditMode = .none
    var onRecordingsChanged: (() -> Void)? = nil

    @StateObject private var player = AudioPlayerManager()
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langMgr = LanguageManager.shared

    enum EditMode { case none, split, trim }
    @State private var editMode: EditMode = .none
    @State private var trimStart: Double = 0.25   // fraction 0–1
    @State private var trimEnd:   Double = 0.75
    @State private var splitFraction: Double = 0.5  // fraction 0–1, decoupled from playhead
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil

    private let barHeights: [CGFloat] = [28,44,34,66,88,54,106,76,118,90,108,72,94,58,78,112,66,48,30,46,70,86,60,40,28,52,34,24,44,22]
    private let speeds: [Float] = [0.5, 1.0, 1.5, 2.0]
    private var progress: Double { player.duration > 0 ? player.currentTime / player.duration : 0 }

    private var formattedDate: String {
        let df = DateFormatter(); df.dateFormat = "MMM d, yyyy · h:mm a"
        return df.string(from: entry.createdAt)
    }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: langMgr.t("media.audio"), accentColor: .stageMedia, backIcon: "xmark", onBack: { dismiss() })
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.stageMedia.opacity(0.4)).frame(height: 2) }

                // ── Waveform ──────────────────────────────────────────
                // Total height: 44pt scissors zone + 180pt bars zone = 224pt
                Spacer().frame(height: 24)
                GeometryReader { waveGeo in
                    ZStack(alignment: .topLeading) {

                        // ── Bars (bottom 180pt) ───────────────────────
                        HStack(alignment: .center, spacing: 4) {
                            ForEach(Array(barHeights.enumerated()), id: \.offset) { i, h in
                                let frac = Double(i) / Double(barHeights.count)
                                let played = frac < progress
                                let inTrim = frac >= trimStart && frac <= trimEnd
                                Capsule()
                                    .fill(played ? Color(hex: "#ec4899") : Color(hex: "#ec4899").opacity(0.30))
                                    .opacity(editMode == .trim ? (inTrim ? 1.0 : 0.22) : 1.0)
                                    .frame(width: 7, height: h * 1.5)
                            }
                        }
                        .frame(width: waveGeo.size.width, height: 180)
                        .offset(y: 44)
                        .animation(.linear(duration: 0.1), value: progress)

                        // ── Split: scissors in top zone + full-height line ─
                        if editMode == .split {
                            let x = waveGeo.size.width * splitFraction
                            // Full-height dividing line
                            Rectangle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 2, height: 224)
                                .offset(x: x)
                            // Scissors centered in the 44pt zone
                            Image(systemName: "scissors")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 6)
                                .frame(width: 36, height: 36)
                                .offset(x: x - 18, y: 4)
                        }

                        // ── Trim: white boundary lines over full height ───
                        if editMode == .trim {
                            Rectangle()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 2, height: 224)
                                .offset(x: waveGeo.size.width * trimStart)
                            Rectangle()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 2, height: 224)
                                .offset(x: waveGeo.size.width * trimEnd)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { v in
                                let f = max(0, min(1, v.location.x / waveGeo.size.width))
                                if editMode == .split {
                                    splitFraction = f
                                } else if editMode == .trim {
                                    if abs(f - trimStart) < abs(f - trimEnd) {
                                        trimStart = max(0, min(trimEnd - 0.04, f))
                                    } else {
                                        trimEnd = max(trimStart + 0.04, min(1, f))
                                    }
                                }
                            }
                    )
                }
                .frame(height: 224)
                .padding(.horizontal, 10)

                // ── File name + date ──────────────────────────────────
                VStack(spacing: 4) {
                    Text(displayName)
                        .font(.inter(14, weight: .bold)).foregroundColor(.textPrimary)
                        .lineLimit(1).padding(.horizontal, 24)
                    Text("\(formattedDate) · \(entry.relativePath.hasSuffix(".wav") ? "wav" : "m4a")")
                        .font(.inter(11)).foregroundColor(.textQuaternary)
                }
                .padding(.top, 12)

                // ── Progress bar ──────────────────────────────────────
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Base track
                        Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)

                        if editMode == .trim {
                            // Kept region highlight
                            Capsule()
                                .fill(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * (trimEnd - trimStart), height: 3)
                                .offset(x: geo.size.width * trimStart)
                            // Trim start handle
                            Circle()
                                .fill(Color.white)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2))
                                .shadow(color: .black.opacity(0.4), radius: 4)
                                .offset(x: geo.size.width * trimStart - 11)
                            // Trim end handle
                            Circle()
                                .fill(Color.white)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2))
                                .shadow(color: .black.opacity(0.4), radius: 4)
                                .offset(x: geo.size.width * trimEnd - 11)
                        } else {
                            // Playhead — tracks splitFraction in split mode, progress otherwise
                            let dotFrac = editMode == .split ? splitFraction : progress
                            Capsule()
                                .fill(LinearGradient(colors: [Color(hex: "#ec4899"), Color(hex: "#f472b6")], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * dotFrac, height: 3)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 14, height: 14)
                                .shadow(color: Color(hex: "#ec4899").opacity(0.6), radius: 6)
                                .offset(x: geo.size.width * dotFrac - 7)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let f = max(0, min(1, v.location.x / geo.size.width))
                        if editMode == .trim {
                            if abs(f - trimStart) < abs(f - trimEnd) {
                                trimStart = max(0, min(trimEnd - 0.04, f))
                            } else {
                                trimEnd = max(trimStart + 0.04, min(1, f))
                            }
                        } else if editMode == .split {
                            splitFraction = f
                        } else {
                            player.seek(to: f * player.duration)
                        }
                    })
                }
                .frame(height: 28).padding(.horizontal, 14).padding(.top, 24)

                // ── Time labels ───────────────────────────────────────
                HStack {
                    Text(editMode == .trim  ? formatTime(trimStart * player.duration) :
                         editMode == .split ? formatTime(splitFraction * player.duration) :
                                              formatTime(player.currentTime))
                    Spacer()
                    Text(editMode == .trim  ? formatTime(trimEnd * player.duration) :
                         editMode == .split ? formatTime((1 - splitFraction) * player.duration) :
                                              formatTime(player.duration))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.38))
                .padding(.horizontal, 14).padding(.top, 6)

                // ── Playback controls ─────────────────────────────────
                HStack(spacing: 36) {
                    skipButton(direction: -1)
                    Button { player.togglePlay() } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color(hex: "#ec4899"), Color(hex: "#be185d")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 80, height: 80)
                                .shadow(color: Color(hex: "#ec4899").opacity(0.5), radius: 24)
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 30)).foregroundColor(.white)
                                .offset(x: player.isPlaying ? 0 : 3)
                        }
                    }
                    skipButton(direction: 1)
                }
                .padding(.top, 24).padding(.bottom, 20)

                // ── Speed pills (hidden in edit mode) ─────────────────
                if editMode == .none {
                    HStack(spacing: 8) {
                        ForEach(speeds, id: \.self) { spd in
                            Button { player.setRate(spd) } label: {
                                Text(spd == 1.0 ? "1×" : "\(spd, specifier: "%.2g")×")
                                    .font(.inter(12, weight: .bold))
                                    .foregroundColor(player.rate == spd ? Color(hex: "#f472b6") : Color.white.opacity(0.5))
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(player.rate == spd ? Color(hex: "#ec4899").opacity(0.18) : Color.white.opacity(0.06))
                                    .overlay(Capsule().stroke(player.rate == spd ? Color(hex: "#ec4899").opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }

                // ── Edit controls ─────────────────────────────────────
                editControls

                Spacer()
            }

            // Processing overlay
            if isProcessing {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().progressViewStyle(.circular).tint(.stageMedia).scaleEffect(1.3)
                    Text(langMgr.t("common.processing")).font(.inter(13, weight: .semibold)).foregroundColor(.textSecondary)
                }
            }
        }
        .onAppear {
            player.load(url: entry.fileURL, autoPlay: autoPlay && initialEditMode == .none)
            if initialEditMode != .none {
                editMode = initialEditMode
                if initialEditMode == .split { splitFraction = 0.5 }
                else if initialEditMode == .trim { trimStart = 0.25; trimEnd = 0.75 }
            }
        }
        .onDisappear { player.stop() }
        .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    // ── Edit controls sub-view ────────────────────────────────────────

    @ViewBuilder
    private var editControls: some View {
        switch editMode {
        case .none:
            HStack(spacing: 14) {
                editPill(icon: "scissors", label: langMgr.t("media.split")) {
                    player.pause()
                    splitFraction = progress > 0.05 ? progress : 0.5
                    editMode = .split
                }
                editPill(icon: "crop", label: langMgr.t("media.trim")) {
                    player.pause()
                    // Position handles around current playhead; default 25–75 if not yet played
                    let p = progress > 0.05 ? progress : 0.5
                    trimStart = max(0,   p - 0.15)
                    trimEnd   = min(1.0, p + 0.15)
                    editMode = .trim
                }
            }
            .padding(.bottom, 8)

        case .split:
            VStack(spacing: 10) {
                Text(langMgr.t("media.cutAt").replacingOccurrences(of: "%@", with: formatTime(splitFraction * player.duration)))
                    .font(.inter(12)).foregroundColor(Color.white.opacity(0.45))
                confirmRow(confirmLabel: langMgr.t("media.confirmSplit"), action: { Task { await doSplit() } })
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

        case .trim:
            VStack(spacing: 10) {
                Text(langMgr.t("media.keepRange")
                    .replacingOccurrences(of: "%1@", with: formatTime(trimStart * player.duration))
                    .replacingOccurrences(of: "%2@", with: formatTime(trimEnd * player.duration)))
                    .font(.inter(12)).foregroundColor(Color.white.opacity(0.45))
                confirmRow(confirmLabel: langMgr.t("media.confirmTrim"), action: { Task { await doTrim() } })
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────

    @ViewBuilder
    private func editPill(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(label).font(.inter(13, weight: .bold))
            }
            .foregroundColor(Color.white.opacity(0.65))
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Color.white.opacity(0.07))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func confirmRow(confirmLabel: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button { editMode = .none } label: {
                Text(langMgr.t("common.cancel"))
                    .font(.inter(13, weight: .semibold)).foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Button(action: action) {
                Text(confirmLabel)
                    .font(.inter(13, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Color(hex: "#ec4899"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func skipButton(direction: Int) -> some View {
        Button { player.skip(Double(direction) * 15) } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.07)).frame(width: 56, height: 56)
                Image(systemName: direction < 0 ? "gobackward.15" : "goforward.15")
                    .font(.system(size: 24)).foregroundColor(Color.white.opacity(0.75))
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let s = max(0, Int(t)); return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // ── Split logic ───────────────────────────────────────────────────

    private func doSplit() async {
        let splitTime = splitFraction * player.duration
        guard splitTime > 0.5, splitTime < player.duration - 0.5 else {
            errorMessage = "Split point must be at least 0.5 s from start and end."
            return
        }
        player.stop()
        isProcessing = true
        defer { isProcessing = false }
        do {
            let (url1, url2) = try await AudioFileProcessor.split(sourceURL: entry.fileURL, at: splitTime, itemId: entry.itemId)
            // Derive base name from displayName (strip .m4a)
            let base = displayName.hasSuffix(".m4a") ? String(displayName.dropLast(4)) : displayName
            let e1 = LocalRecordingEntry(id: UUID().uuidString, itemId: entry.itemId,
                relativePath: LocalRecordingStore.relativePath(of: url1),
                createdAt: entry.createdAt.addingTimeInterval(1),
                durationSeconds: splitTime,
                label: "\(base)-split-01.m4a")
            let e2 = LocalRecordingEntry(id: UUID().uuidString, itemId: entry.itemId,
                relativePath: LocalRecordingStore.relativePath(of: url2),
                createdAt: entry.createdAt.addingTimeInterval(2),
                durationSeconds: entry.durationSeconds - splitTime,
                label: "\(base)-split-02.m4a")
            LocalRecordingStore.shared.add(e1)
            LocalRecordingStore.shared.add(e2)
            onRecordingsChanged?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ── Trim logic ────────────────────────────────────────────────────

    private func doTrim() async {
        let start = trimStart * player.duration
        let end   = trimEnd   * player.duration
        guard end - start > 0.5 else {
            errorMessage = "Trim region must be at least 0.5 s."
            return
        }
        player.stop()
        isProcessing = true
        defer { isProcessing = false }
        do {
            let url = try await AudioFileProcessor.trim(sourceURL: entry.fileURL, from: start, to: end, itemId: entry.itemId)
            let base = displayName.hasSuffix(".m4a") ? String(displayName.dropLast(4)) : displayName
            // Count existing trims from this same source to get the next sequential number
            let prefix = "\(base)-trim-"
            let existing = LocalRecordingStore.shared.recordings(for: entry.itemId)
                .filter { ($0.label ?? "").hasPrefix(prefix) }.count
            let trimIdx = String(format: "%02d", existing + 1)
            let newEntry = LocalRecordingEntry(id: UUID().uuidString, itemId: entry.itemId,
                relativePath: LocalRecordingStore.relativePath(of: url),
                createdAt: entry.createdAt, durationSeconds: end - start,
                label: "\(base)-trim-\(trimIdx).m4a")
            LocalRecordingStore.shared.add(newEntry)
            onRecordingsChanged?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Move To Sheet
struct MoveToSheet: View {
    let entry: LocalRecordingEntry
    var onMoved: () -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langMgr = LanguageManager.shared

    @State private var expanded = Set<String>()
    private let allItems   = LocalItemStore.shared.all()
    private let collections = LocalCollectionStore.shared.all()

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
                    Text(langMgr.t("common.moveTo"))
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
        let blockItems = items(forCollectionId: id).filter { $0.id != entry.itemId }
        if !blockItems.isEmpty {
            VStack(spacing: 0) {
                // Collection header
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { toggle(key) } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: expanded.contains(key) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 16)
                        Image(systemName: "tray.fill")
                            .font(.system(size: 13)).foregroundColor(.brandCyan)
                        Text(name)
                            .font(.inter(14, weight: .bold)).foregroundColor(.textPrimary)
                        Spacer()
                        Text("\(blockItems.count)")
                            .font(.inter(11, weight: .semibold)).foregroundColor(.textQuaternary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if expanded.contains(key) {
                    VStack(spacing: 0) {
                        ForEach(blockItems) { it in
                            let audioCount = LocalRecordingStore.shared.count(for: it.id)
                            Button { moveHere(it) } label: {
                                HStack(spacing: 10) {
                                    Rectangle().fill(Color.brandCyan.opacity(0.4)).frame(width: 2, height: 22)
                                        .padding(.leading, 14)
                                    ZStack {
                                        Circle().fill(Color.stageMedia.opacity(0.15)).frame(width: 26, height: 26)
                                        Image(systemName: "waveform")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.stageMedia)
                                    }
                                    Text(it.name)
                                        .font(.inter(13, weight: .semibold)).foregroundColor(.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    if audioCount > 0 {
                                        Text("\(audioCount) audio\(audioCount == 1 ? "" : "s")")
                                            .font(.inter(10, weight: .semibold))
                                            .foregroundColor(.stageMedia.opacity(0.8))
                                            .padding(.horizontal, 7).padding(.vertical, 3)
                                            .background(Color.stageMedia.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 15)).foregroundColor(.brandCyan.opacity(0.7))
                                }
                                .padding(.vertical, 10).padding(.trailing, 14)
                                .background(Color.white.opacity(0.03))
                            }
                            .buttonStyle(.plain)
                            if it.id != blockItems.last?.id {
                                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1).padding(.leading, 32)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func toggle(_ key: String) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }

    private func moveHere(_ target: LocalStoredItem) {
        let moved = LocalRecordingEntry(
            id: entry.id,
            itemId: target.id,
            relativePath: entry.relativePath,
            createdAt: entry.createdAt,
            durationSeconds: entry.durationSeconds,
            label: entry.label
        )
        LocalRecordingStore.shared.delete(id: entry.id)
        LocalRecordingStore.shared.add(moved)
        onMoved()
        dismiss()
    }
}

struct ImageMoveToSheet: View {
    let imageFile: ImageFile
    let currentItemId: String
    var onMoved: () -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langMgr = LanguageManager.shared

    @State private var expanded = Set<String>()
    private let allItems    = LocalItemStore.shared.all()
    private let collections = LocalCollectionStore.shared.all()

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
                    Text(langMgr.t("common.moveTo")).font(.inter(17, weight: .heavy)).foregroundColor(.textPrimary)
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
                        ForEach(collections) { col in collectionBlock(name: col.name, id: col.id) }
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
                        ForEach(blockItems) { it in
                            Button { moveHere(it) } label: {
                                HStack(spacing: 10) {
                                    Rectangle().fill(Color.brandCyan.opacity(0.4)).frame(width: 2, height: 22).padding(.leading, 14)
                                    ZStack {
                                        Circle().fill(Color.stageMedia.opacity(0.15)).frame(width: 26, height: 26)
                                        Image(systemName: "photo.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(.stageMedia)
                                    }
                                    Text(it.name).font(.inter(13, weight: .semibold)).foregroundColor(.textSecondary).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 15)).foregroundColor(.brandCyan.opacity(0.7))
                                }
                                .padding(.vertical, 10).padding(.trailing, 14)
                                .background(Color.white.opacity(0.03))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 2).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func moveHere(_ target: LocalStoredItem) {
        var newPath = imageFile.localPath
        if let srcPath = imageFile.localPath {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destDir = docs.appendingPathComponent("images/\(target.id)", isDirectory: true)
            try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let destURL = destDir.appendingPathComponent(URL(fileURLWithPath: srcPath).lastPathComponent)
            try? FileManager.default.moveItem(atPath: srcPath, toPath: destURL.path)
            newPath = destURL.path
        }
        // Update store: delete from old item, add to new item
        LocalImageStore.shared.delete(id: imageFile.id)
        let moved = LocalImageEntry(id: UUID().uuidString, itemId: target.id, name: imageFile.name, localPath: newPath, createdAt: imageFile.createdAt)
        LocalImageStore.shared.add(moved)
        onMoved()
        dismiss()
    }
}

// MARK: - Server transcript row
struct MediaFileRow: View {
    let transcript: TranscriptSummary
    var isSelected: Bool
    var onSelect: () -> Void
    var onPlay: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.stageMedia.opacity(0.5), Color.stageMedia.opacity(0.25)], center: .center, startRadius: 0, endRadius: 24))
                    .frame(width: 48, height: 48)
                HStack(spacing: 2) {
                    ForEach([0.4, 0.7, 1.0, 0.6, 0.85, 0.5, 0.75], id: \.self) { h in
                        Capsule()
                            .fill(Color.stageMedia.opacity(0.9))
                            .frame(width: 2.5, height: 20 * h)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(transcript.label)
                    .font(.inter(14, weight: .bold)).foregroundColor(.textPrimary).lineLimit(1)
                Text(transcript.duration.isEmpty ? "—" : transcript.duration)
                    .font(.inter(11)).foregroundColor(.textQuaternary)
            }

            Spacer()

            // Play button
            Button { onPlay() } label: {
                ZStack {
                    Circle()
                        .fill(Color.stageMedia.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.stageMedia)
                        .offset(x: 1.5)
                }
            }
            .buttonStyle(.plain)

            Menu {
                Section("Process Audio") {
                    Button { } label: { Label("Transcribe", systemImage: "waveform.badge.magnifyingglass") }
                    Button { } label: { Label("Convert to MP3", systemImage: "arrow.triangle.2.circlepath") }
                    Button { } label: { Label("Trim Audio", systemImage: "scissors") }
                }
                Section("Share & Export") {
                    Button { } label: { Label("Upload to Drive", systemImage: "arrow.up.circle") }
                    Button { } label: { Label("Email", systemImage: "envelope") }
                    Button { } label: { Label("Share…", systemImage: "square.and.arrow.up") }
                }
                Section("Manage") {
                    Button { } label: { Label("Rename", systemImage: "pencil") }
                    Button { } label: { Label("Move to…", systemImage: "folder") }
                    Button(role: .destructive) { } label: { Label("Delete", systemImage: "trash") }
                }
                Section("Info") {
                    Button { } label: { Label("More Info", systemImage: "info.circle") }
                }
            } label: {
                Text("···")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(isSelected ? Color.stageMedia.opacity(0.08) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Image file row
struct ImageFileRow: View {
    let imageFile: ImageFile
    let item: Item
    var index: Int = 1
    var isSelected: Bool = false
    var isQueued: Bool = false
    var onSelect: () -> Void = {}
    var onDelete: () -> Void = {}
    var onMoved: () -> Void = {}
    var onRenamed: () -> Void = {}
    var onRenameRequested: () -> Void = {}

    @ObservedObject private var imageMgr = ImageProcessingManager.shared

    @State private var hourglassFlipped = false
    @State private var showViewer = false
    @State private var showPromptImage = false
    @State private var showMoreInfo = false
    @State private var showMoveTo = false
    private let imageColor = Color.stageMedia

    private var displayName: String { imageFile.name }

    private var fileURL: URL? {
        guard let path = imageFile.localPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [imageColor.opacity(0.5), imageColor.opacity(0.25)], center: .center, startRadius: 0, endRadius: 24))
                    .frame(width: 48, height: 48)
                Image(systemName: "photo.fill")
                    .font(.system(size: 18)).foregroundColor(imageColor)
            }
            .onTapGesture { onSelect() }

            Text(displayName)
                .font(.inter(13, weight: .bold)).foregroundColor(.textPrimary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                .onTapGesture { onSelect() }

            HStack(spacing: 10) {
                // Status indicator — same position/pattern as audio rows
                let isProcessing = imageMgr.processingImageId == imageFile.id
                let isCompleted  = imageMgr.completedImageIds.contains(imageFile.id)
                let isFailed     = imageMgr.failedImageId == imageFile.id
                ZStack {
                    if isProcessing {
                        ProgressView().progressViewStyle(.circular).tint(.stageMedia)
                            .shadow(color: Color.stageMedia.opacity(0.6), radius: 5)
                    } else if isQueued {
                        Image(systemName: "hourglass").font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.45))
                            .rotationEffect(.degrees(hourglassFlipped ? 180 : 0))
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: false), value: hourglassFlipped)
                            .onAppear { hourglassFlipped = true }
                            .onDisappear { hourglassFlipped = false }
                    } else if isCompleted {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 17))
                            .foregroundColor(.stageMedia).shadow(color: Color.stageMedia.opacity(0.5), radius: 4)
                    } else if isFailed {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 17))
                            .foregroundColor(Color(hex: "#f87171")).shadow(color: Color(hex: "#f87171").opacity(0.5), radius: 4)
                    }
                }
                .frame(width: 20, height: 20)

                Button {
                    if imageFile.localPath != nil { showViewer = true }
                } label: {
                    ZStack {
                        Circle().fill(imageColor.opacity(0.18)).frame(width: 32, height: 32)
                        Image(systemName: "eye.fill").font(.system(size: 11, weight: .bold))
                            .foregroundColor(imageColor)
                    }
                }
                .buttonStyle(.plain)
                .opacity(imageFile.localPath != nil ? 1.0 : 0.3)

                Menu {
                    Section("Process Image") {
                        Button { showPromptImage = true } label: { Label("Prompt Image", systemImage: "photo.fill") }
                    }
                    Section("Share") {
                        if let url = fileURL {
                            ShareLink(item: url) {
                                Label("Share…", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    Section("Manage") {
                        Button { onRenameRequested() } label: { Label("Rename", systemImage: "pencil") }
                        Button { showMoveTo = true } label: { Label("Move to…", systemImage: "folder") }
                        Button(role: .destructive) { DeleteConfirmPresenter.show(itemName: displayName, onDelete: onDelete) } label: { Label("Delete", systemImage: "trash") }
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
        .background(isSelected ? Color.stageMedia.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }
        .fullScreenCover(isPresented: $showViewer) {
            ImageViewerSheet(path: imageFile.resolvedFileURL?.path ?? "", name: imageFile.name)
        }
        .fullScreenCover(isPresented: $showPromptImage) {
            if let url = imageFile.resolvedFileURL {
                PromptsView(context: .imageProcess(
                    imageId: imageFile.id,
                    imageURL: url,
                    itemId: item.id,
                    itemName: item.name
                ))
            } else {
                ZStack {
                    Color(hex: "#081221").ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36)).foregroundColor(.red.opacity(0.8))
                        Text("Image file not found.")
                            .font(.inter(15, weight: .semibold)).foregroundColor(.textPrimary)
                        Button("Close") { showPromptImage = false }
                            .font(.inter(14, weight: .semibold)).foregroundColor(.brandCyan)
                    }
                }
            }
        }
        .sheet(isPresented: $showMoveTo) {
            ImageMoveToSheet(imageFile: imageFile, currentItemId: item.id) { onMoved() }
        }
        .sheet(isPresented: $showMoreInfo) {
            ImageMoreInfoSheet(imageFile: imageFile)
        }
    }
}

struct ImageViewerSheet: View {
    let path: String
    let name: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            }
            VStack {
                HStack {
                    Text(name)
                        .font(.inter(14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 56)
                Spacer()
            }
        }
    }
}

struct ImageMoreInfoSheet: View {
    let imageFile: ImageFile
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langMgr = LanguageManager.shared

    struct Meta {
        var fileSize   = "—"
        var created    = "—"
        var modified   = "—"
        var dimensions = "—"
        var format     = "—"
    }
    @State private var meta = Meta()

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

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 1) {
                        infoRow(langMgr.t("info.name"),       imageFile.name)
                        infoRow(langMgr.t("info.format"),     meta.format)
                        infoRow(langMgr.t("info.dimensions"), meta.dimensions)
                        infoRow(langMgr.t("info.fileSize"),   meta.fileSize)
                        infoRow(langMgr.t("info.created"),    meta.created)
                        infoRow(langMgr.t("info.modified"),   meta.modified)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
                }
                Spacer()
            }
        }
        .task { loadMeta() }
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

    private func loadMeta() {
        guard let url = imageFile.resolvedFileURL else { return }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        var m = Meta()
        m.format = url.pathExtension.uppercased()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let sz = attrs[.size] as? Int64 {
                m.fileSize = ByteCountFormatter.string(fromByteCount: sz, countStyle: .file)
            }
            if let created  = attrs[.creationDate]    as? Date { m.created  = df.string(from: created)  }
            if let modified = attrs[.modificationDate] as? Date { m.modified = df.string(from: modified) }
        }
        if let img = UIImage(contentsOfFile: url.path) {
            m.dimensions = "\(Int(img.size.width)) × \(Int(img.size.height)) px"
        }
        meta = m
    }
}

// MARK: - Bulk move audio sheet

struct BulkMoveAudioSheet: View {
    let ids: [String]
    let currentItemId: String
    var onMoved: () -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langMgr = LanguageManager.shared

    @State private var expanded = Set<String>()
    private let allItems    = LocalItemStore.shared.all()
    private let collections = LocalCollectionStore.shared.all()

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
                    Text(langMgr.t("media.moveTo").replacingOccurrences(of: "%d", with: "\(ids.count)"))
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
                                        Circle().fill(Color.stageMedia.opacity(0.15)).frame(width: 26, height: 26)
                                        Image(systemName: "waveform").font(.system(size: 11, weight: .semibold)).foregroundColor(.stageMedia)
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
        let store = LocalRecordingStore.shared
        for id in ids {
            guard let entry = store.recordings(for: currentItemId).first(where: { $0.id == id }) else { continue }
            store.delete(id: id)
            store.add(LocalRecordingEntry(
                id: UUID().uuidString, itemId: target.id,
                relativePath: entry.relativePath, createdAt: entry.createdAt,
                durationSeconds: entry.durationSeconds, label: entry.label
            ))
        }
        onMoved()
        dismiss()
    }
}

