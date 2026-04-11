import Foundation
import Combine
import UserNotifications
import SwiftUI
import AVFoundation

// MARK: - AppLogger

@MainActor
final class AppLogger: ObservableObject {
    static let shared = AppLogger()
    private init() {}

    enum Level: String {
        case info    = "INFO"
        case success = "OK"
        case warning = "WARN"
        case error   = "ERR"

        var color: Color {
            switch self {
            case .info:    return Color.white.opacity(0.55)
            case .success: return Color(hex: "#34d399")
            case .warning: return Color(hex: "#fbbf24")
            case .error:   return Color(hex: "#f87171")
            }
        }
        var badge: Color {
            switch self {
            case .info:    return Color.white.opacity(0.12)
            case .success: return Color(hex: "#34d399").opacity(0.18)
            case .warning: return Color(hex: "#fbbf24").opacity(0.18)
            case .error:   return Color(hex: "#f87171").opacity(0.18)
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String

        var timeString: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f.string(from: timestamp)
        }
    }

    @Published private(set) var entries: [Entry] = []
    private let maxEntries = 1000

    func log(_ message: String, level: Level = .info) {
        entries.append(Entry(timestamp: Date(), level: level, message: message))
        if entries.count > maxEntries { entries.removeFirst() }
    }

    func clear() { entries.removeAll() }

    var allText: String {
        entries.map { "[\($0.timeString)] [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
    }
}

// Callable from any context — dispatches to MainActor
func appLog(_ message: String, level: AppLogger.Level = .info) {
    Task { @MainActor in AppLogger.shared.log(message, level: level) }
}

/// Owns the full upload → poll → save flow as a background singleton.
/// Lives forever — not tied to any view. Cancelled only by cancelAll().
@MainActor
final class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    private init() {}

    // MARK: - Published state (observed by views)
    @Published var transcribingItemName: String? = nil
    @Published var transcribingRecordingId: String? = nil
    @Published var transcribedRecordingIds: Set<String> = {
        let saved = UserDefaults.standard.stringArray(forKey: "transcribedRecordingIds") ?? []
        return Set(saved)
    }()
    @Published var failedRecordingIds: Set<String> = []
    @Published var queuedRecordingIds: Set<String> = []
    @Published var transcribingStatus: String = ""
    @Published var transcribingError: String? = nil
    @Published var transcriptionResult: Bool? = nil
    @Published var lastSavedItemId: String? = nil
    @Published var transcriptSaveCounter: Int = 0

    private let api = APIClient.shared
    private var resultClearTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var activeAudioTaskId: String?

    // MARK: - Auto-trigger (fires when a recording is saved, if automation is enabled)
    func autoTriggerIfEnabled(entry: LocalRecordingEntry, item: Item) {
        guard UserDefaults.standard.bool(forKey: "auto_transcription") else { return }

        TaskQueueManager.shared.enqueue { [weak self] in
            guard let self, !Task.isCancelled else { return }

            var workingEntry = entry

            // ── Step 1: Convert to M4A if needed ────────────────────────────
            let origExt = workingEntry.fileURL.pathExtension.lowercased()
            if origExt != "m4a" && origExt != "mp3" && FileManager.default.fileExists(atPath: workingEntry.fileURL.path) {
                do {
                    let m4aURL = try await AudioProcessor.convertToM4A(sourceURL: workingEntry.fileURL)
                    var updated = workingEntry
                    updated.relativePath = LocalRecordingStore.relativePath(of: m4aURL)
                    if let lbl = updated.label {
                        let base = lbl.hasSuffix(".\(origExt)") ? String(lbl.dropLast(origExt.count + 1)) : lbl
                        updated.label = "\(base).m4a"
                    }
                    LocalRecordingStore.shared.update(updated)
                    try? FileManager.default.removeItem(at: workingEntry.fileURL)
                    workingEntry = updated
                    appLog("Auto-converted to M4A: \(m4aURL.lastPathComponent)", level: .success)
                } catch {
                    appLog("Auto-conversion failed: \(error.localizedDescription)", level: .warning)
                }
            }

            // ── Step 2: Split if needed — persist chunks as real entries ────
            let fileSize = (try? FileManager.default.attributesOfItem(
                atPath: workingEntry.fileURL.path)[.size] as? Int64) ?? 0

            // Read actual duration from the file (stored durationSeconds may be wrong)
            var actualDuration: Double = workingEntry.durationSeconds
            if FileManager.default.fileExists(atPath: workingEntry.fileURL.path) {
                let asset = AVURLAsset(url: workingEntry.fileURL)
                if let cmDur = try? await asset.load(.duration) {
                    let d = CMTimeGetSeconds(cmDur)
                    if d > 0 { actualDuration = d }
                }
            }

            let needsSplit = actualDuration >= AudioProcessor.maxDurationSeconds
                          || fileSize > AudioProcessor.maxFileSizeBytes

            var entriesToProcess: [LocalRecordingEntry] = [workingEntry]

            if needsSplit && FileManager.default.fileExists(atPath: workingEntry.fileURL.path) {
                appLog("Auto-split needed: \(actualDuration)s / \(fileSize) bytes", level: .info)
                do {
                    // Tighten max duration if file is also too large
                    var effectiveMax = AudioProcessor.maxDurationSeconds
                    if fileSize > AudioProcessor.maxFileSizeBytes && actualDuration > 0 {
                        let bps = Double(fileSize) / actualDuration
                        let sizeLimited = floor(Double(AudioProcessor.maxFileSizeBytes) / bps)
                        effectiveMax = min(effectiveMax, max(sizeLimited, 60))
                    }

                    let chunkURLs = try await AudioProcessor.split(
                        sourceURL: workingEntry.fileURL, maxDuration: effectiveMax)

                    if chunkURLs.count > 1 {
                        var newEntries: [LocalRecordingEntry] = []
                        for (i, url) in chunkURLs.enumerated() {
                            // Load actual duration from each chunk file — don't trust stored/calculated values
                            var chunkDur: Double = actualDuration / Double(chunkURLs.count)
                            let chunkAsset = AVURLAsset(url: url)
                            if let cmDur = try? await chunkAsset.load(.duration) {
                                let d = CMTimeGetSeconds(cmDur)
                                if d > 0 { chunkDur = d }
                            }
                            let newEntry = LocalRecordingEntry(
                                id: UUID().uuidString,
                                itemId: item.id,
                                relativePath: LocalRecordingStore.relativePath(of: url),
                                createdAt: workingEntry.createdAt.addingTimeInterval(Double(i)),
                                durationSeconds: chunkDur,
                                label: url.lastPathComponent
                            )
                            LocalRecordingStore.shared.add(newEntry)
                            newEntries.append(newEntry)
                            appLog("  Chunk \(i+1)/\(chunkURLs.count): \(url.lastPathComponent) (\(Int(chunkDur))s)", level: .success)
                        }
                        // Remove original entry and file — chunks are the source of truth now
                        LocalRecordingStore.shared.delete(id: workingEntry.id)
                        LocalRecordingStore.shared.deleteFile(at: workingEntry.fileURL)
                        appLog("  Original removed — \(newEntries.count) chunks registered", level: .success)
                        entriesToProcess = newEntries
                    }
                } catch {
                    appLog("Auto-split failed: \(error.localizedDescription) — proceeding with original", level: .warning)
                }
            }

            // ── Step 3: Queue each entry (chunks or the single file) ─────────
            // Mark all as queued upfront so hourglass shows for each
            entriesToProcess.forEach { self.queuedRecordingIds.insert($0.id) }

            for entryToTranscribe in entriesToProcess {
                guard !Task.isCancelled else { break }
                let currentRecordings = LocalRecordingStore.shared.recordings(for: item.id)
                let index = (currentRecordings.firstIndex(where: { $0.id == entryToTranscribe.id }) ?? 0) + 1
                let ext = entryToTranscribe.fileURL.pathExtension.isEmpty ? "m4a" : entryToTranscribe.fileURL.pathExtension
                let displayName = "Audio-\(item.name)-\(String(format: "%02d", index)).\(ext)"
                appLog("Auto-trigger: \(displayName)")
                self.transcribingItemName = item.name
                let result = AudioProcessor.validate(entry: entryToTranscribe, displayName: displayName)
                await self.runTranscriptions(item: item, preparationResults: [result], recordings: currentRecordings)
            }

            self.transcribingItemName = nil
            self.transcribingStatus = ""
            self.transcribingRecordingId = nil
        }
    }

    // MARK: - Queue multiple items sequentially (used by Process Audio when multiple items selected)
    func transcribeQueue(_ pairs: [(item: Item, results: [AudioValidationResult], recordings: [LocalRecordingEntry])]) {
        // Add all recording IDs to the pending display immediately
        queuedRecordingIds.formUnion(Set(pairs.flatMap { $0.results.map { $0.recordingId } }))

        // Enqueue each item as a separate job — never cancels a running task
        for pair in pairs {
            let item = pair.item
            let results = pair.results
            let recordings = pair.recordings
            TaskQueueManager.shared.enqueue { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.transcribingItemName = item.name
                await self.runTranscriptions(item: item, preparationResults: results, recordings: recordings)
                self.transcribingRecordingId = nil
                self.transcribingItemName = nil
                self.transcribingStatus = ""
            }
        }
    }

    // MARK: - Start transcription (called from MediaListView)
    func transcribeRecordings(
        item: Item,
        preparationResults: [AudioValidationResult],
        recordings: [LocalRecordingEntry]
    ) {
        // Show all recordings as pending immediately — never cancels a running task
        queuedRecordingIds.formUnion(Set(preparationResults.map { $0.recordingId }))
        TaskQueueManager.shared.enqueue { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.runTranscribeJob(item: item, preparationResults: preparationResults, recordings: recordings)
        }
    }

    // MARK: - Transcription job body (runs inside the serial queue)
    private func runTranscribeJob(
        item: Item,
        preparationResults: [AudioValidationResult],
        recordings: [LocalRecordingEntry]
    ) async {
        resultClearTask?.cancel()
        // transcribedRecordingIds intentionally NOT cleared — checkmarks persist permanently
        failedRecordingIds = []
        transcribingError = nil
        transcriptionResult = nil
        lastSavedItemId = nil
        transcribingItemName = item.name

        appLog("─────────────────────────────────")
        appLog("TranscriptionManager: \(preparationResults.count) file(s) for '\(item.name)'")

            for result in preparationResults {
                guard !Task.isCancelled else { break }
                guard let entry = recordings.first(where: { $0.id == result.recordingId }) else {
                    appLog("  ✗ No entry for \(result.recordingId)", level: .error); continue
                }

                appLog("Processing: \(result.displayName) | \(entry.durationSeconds)s")
                appLog("  fileExists: \(FileManager.default.fileExists(atPath: entry.fileURL.path))")
                queuedRecordingIds.remove(result.recordingId)
                transcribingRecordingId = result.recordingId

                do {
                    transcribingStatus = "Preparing \(result.displayName)…"
                    let prepared = try await Task.detached(priority: .userInitiated) {
                        try await AudioProcessor.prepare(entry: entry, displayName: result.displayName)
                    }.value
                    appLog("  Prepared into \(prepared.count) chunk(s)")

                    // Compute label once — all sub-chunks of this recording share the same destination file
                    let recIndex = (recordings.firstIndex(where: { $0.id == result.recordingId }) ?? 0) + 1
                    let slug = item.name.lowercased()
                        .replacingOccurrences(of: " ", with: "-")
                        .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                    let pendingLabel = "transcript-\(slug)-\(String(format: "%02d", recIndex)).txt"

                    var anyChunkSucceeded = false
                    var collectedTexts: [String] = []   // ordered sub-chunk texts — joined at end
                    var totalDuration: Double = 0

                    for (url, duration, name) in prepared {
                        guard !Task.isCancelled else { break }

                        guard let audioData = try? Data(contentsOf: url) else {
                            appLog("  ✗ Cannot read \(url.path)", level: .error)
                            transcribingError = "Cannot read: \(name)"
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            transcribingError = nil; continue
                        }
                        appLog("  Read OK: \(audioData.count) bytes")

                        transcribingStatus = "Uploading \(name)…"
                        appLog("  → POST /api/audio/transcribe (\(audioData.count) bytes, \(duration)s)")

                        var uploadResult2: TranscribeResponse? = nil
                        for uploadAttempt in 1...2 {
                            guard !Task.isCancelled else { break }
                            if uploadAttempt > 1 {
                                appLog("  Upload retry \(uploadAttempt)/2…", level: .warning)
                                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { break }
                                guard !Task.isCancelled else { break }
                            }
                            do {
                                uploadResult2 = try await api.uploadAudio(data: audioData, filename: name, durationSeconds: duration)
                                break
                            } catch APIClientError.unauthorized {
                                appLog("  ✗ Session expired on upload", level: .error)
                                failedRecordingIds.insert(result.recordingId)
                                transcribingRecordingId = nil; transcribingStatus = ""; transcribingItemName = nil
                                transcribingError = "Session expired. Please log in again."
                                if !AudioRecorderManager.shared.isRecording { AuthManager.shared.logout() }; return
                            } catch {
                                if Task.isCancelled { break }
                                appLog("  ✗ Upload attempt \(uploadAttempt): \(error.localizedDescription)", level: uploadAttempt == 2 ? .error : .warning)
                                if uploadAttempt == 2 {
                                    transcribingError = error.localizedDescription
                                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch {}
                                    transcribingError = nil
                                }
                            }
                        }
                        guard !Task.isCancelled, let triggerRes = uploadResult2 else { continue }

                        appLog("  ← success=\(triggerRes.success) taskId=\(triggerRes.taskId ?? "nil")")
                        guard let taskId = triggerRes.taskId else {
                            appLog("  ✗ No taskId: \(triggerRes.message ?? "")", level: .error)
                            transcribingError = triggerRes.message ?? "Failed to start transcription."
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            transcribingError = nil; continue
                        }
                        appLog("  taskId: \(taskId)", level: .success)
                        activeAudioTaskId = taskId

                        PendingTaskStore.shared.add(PendingTaskEntry(
                            taskId: taskId, itemId: item.id, itemName: item.name,
                            label: pendingLabel, recordingId: result.recordingId, uploadedAt: Date()
                        ))
                        appLog("  ↳ Anchor saved: \(pendingLabel)")

                        transcribingStatus = "Transcribing \(name)…"
                        var transcribedText: String? = nil
                        var attempt = 0
                        var consecutiveErrors = 0

                        pollLoop: while attempt < 120 {
                            guard !Task.isCancelled else { break pollLoop }
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            guard !Task.isCancelled else { break pollLoop }

                            do {
                                let poll = try await api.pollAudioResult(taskId: taskId)
                                consecutiveErrors = 0
                                appLog("  Poll #\(attempt + 1): \(poll.status)")
                                switch poll.status {
                                case "completed":
                                    appLog("  ✓ text=\(poll.data?.responseData?.text?.count ?? 0)ch", level: .success)
                                    appLog("[CREDITS] Charged: \(String(format: "%.4f", poll.data?.totalCost ?? 0)) | Balance: paid=\(String(format: "%.4f", poll.data?.credit ?? 0))  free=\(String(format: "%.0f", poll.data?.freeCredit ?? 0))", level: .info)
                                    transcribedText = poll.data?.responseData?.text
                                    break pollLoop
                                case "failed":
                                    appLog("  ✗ \(poll.message ?? "failed")", level: .error)
                                    transcribingError = poll.message ?? "Transcription failed."
                                    break pollLoop
                                default:
                                    transcribingStatus = "Transcribing \(name)… \(attempt * 5)s"
                                }
                            } catch APIClientError.unauthorized {
                                appLog("  ✗ Session expired during poll", level: .error)
                                failedRecordingIds.insert(result.recordingId)
                                transcribingRecordingId = nil; transcribingStatus = ""; transcribingItemName = nil
                                transcribingError = "Session expired. Please log in again."
                                if !AudioRecorderManager.shared.isRecording { AuthManager.shared.logout() }; return
                            } catch {
                                consecutiveErrors += 1
                                appLog("  Poll #\(attempt + 1) err (\(consecutiveErrors) consecutive): \(error.localizedDescription)", level: .warning)
                                if consecutiveErrors >= 5 {
                                    appLog("  ✗ Too many consecutive errors — aborting poll", level: .error)
                                    transcribingError = "Connection lost. Check the log."
                                    break pollLoop
                                }
                            }
                            attempt += 1
                        }
                        if attempt >= 120 { transcribingError = "Timed out." }

                        PendingTaskStore.shared.remove(taskId: taskId)
                        activeAudioTaskId = nil
                        if let text = transcribedText {
                            collectedTexts.append(text)
                            totalDuration += duration
                            anyChunkSucceeded = true
                            appLog("  ✓ Sub-chunk '\(name)' collected (\(collectedTexts.count)/\(prepared.count))", level: .success)
                        }
                    }

                    // Save all collected sub-chunk texts as ONE transcript in the correct order
                    if !collectedTexts.isEmpty {
                        let combinedText = collectedTexts.joined(separator: "\n")
                        LocalTranscriptStore.shared.addOrReplace(LocalTranscriptEntry(
                            id: UUID().uuidString, itemId: item.id, label: pendingLabel,
                            text: combinedText, durationSeconds: totalDuration, createdAt: Date()
                        ))
                        appLog("  ✓ Saved '\(pendingLabel)' (\(collectedTexts.count) part(s))", level: .success)
                        sendCompletionNotification(title: "Transcription Ready", body: "'\(item.name)' transcribed.")
                        lastSavedItemId = item.id
                        transcriptSaveCounter += 1
                        if UserDefaults.standard.bool(forKey: "auto_note") {
                            let allRecs = LocalRecordingStore.shared.recordings(for: item.id)
                            let allDone = !allRecs.isEmpty && allRecs.allSatisfy {
                                $0.id == result.recordingId ||
                                transcribedRecordingIds.contains($0.id) || failedRecordingIds.contains($0.id)
                            }
                            let notRecording = !AudioRecorderManager.shared.isRecording && !AudioRecorderManager.shared.isPaused
                            if allDone && notRecording {
                                let capturedId = item.id; let capturedName = item.name
                                NoteGenerationManager.shared.markQueued(itemId: capturedId, transcriptIds: [])
                                TaskQueueManager.shared.enqueue { await NoteGenerationManager.shared.runAutoNote(for: capturedId, itemName: capturedName) }
                            } else {
                                appLog("  Auto-note deferred — \(allRecs.filter { $0.id != result.recordingId && !transcribedRecordingIds.contains($0.id) && !failedRecordingIds.contains($0.id) }.count) recording(s) not yet done or recording active")
                            }
                        }
                    }

                    if anyChunkSucceeded {
                        transcribedRecordingIds.insert(result.recordingId)
                        UserDefaults.standard.set(Array(transcribedRecordingIds), forKey: "transcribedRecordingIds")
                    } else {
                        failedRecordingIds.insert(result.recordingId)
                    }
                    appLog("  Row done: \(result.displayName)", level: .success)

                } catch {
                    appLog("  ✗ Outer: \(error.localizedDescription)", level: .error)
                    transcribingError = error.localizedDescription
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    transcribingError = nil
                }
                transcribingRecordingId = nil
            }

            guard !Task.isCancelled else {
                transcribingItemName = nil
                transcribingStatus = ""
                appLog("Transcription cancelled")
                appLog("─────────────────────────────────")
                return
            }

            transcribingItemName = nil
            transcribingStatus = ""
            let succeeded = !transcribedRecordingIds.isEmpty
            transcriptionResult = succeeded
            appLog("Done — \(succeeded ? "success" : "no transcripts saved")")
            appLog("─────────────────────────────────")

            resultClearTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.transcriptionResult = nil
            }
    }

    // MARK: - Inner loop extracted for reuse by transcribeQueue
    private func runTranscriptions(item: Item, preparationResults: [AudioValidationResult], recordings: [LocalRecordingEntry]) async {
        appLog("─────────────────────────────────")
        appLog("TranscriptionManager: \(preparationResults.count) file(s) for '\(item.name)'")

        for result in preparationResults {
            guard !Task.isCancelled else { break }
            guard let entry = recordings.first(where: { $0.id == result.recordingId }) else {
                appLog("  ✗ No entry for \(result.recordingId)", level: .error); continue
            }

            appLog("Processing: \(result.displayName) | \(entry.durationSeconds)s")
            queuedRecordingIds.remove(result.recordingId)
            transcribingRecordingId = result.recordingId

            do {
                transcribingStatus = "Preparing \(result.displayName)…"
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try await AudioProcessor.prepare(entry: entry, displayName: result.displayName)
                }.value

                var anyChunkSucceeded = false
                for (url, duration, name) in prepared {
                    guard !Task.isCancelled else { break }

                    guard let audioData = try? Data(contentsOf: url) else {
                        transcribingError = "Cannot read: \(name)"
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        transcribingError = nil; continue
                    }

                    transcribingStatus = "Uploading \(name)…"
                    let triggerRes: TranscribeResponse
                    var uploadResult: TranscribeResponse? = nil
                    for uploadAttempt in 1...2 {
                        guard !Task.isCancelled else { break }
                        if uploadAttempt > 1 {
                            appLog("  Upload retry \(uploadAttempt)/2 for \(name)…", level: .warning)
                            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { break }
                            guard !Task.isCancelled else { break }
                        }
                        do {
                            uploadResult = try await api.uploadAudio(data: audioData, filename: name, durationSeconds: duration)
                            break
                        } catch APIClientError.unauthorized {
                            failedRecordingIds.insert(result.recordingId)
                            transcribingRecordingId = nil; transcribingStatus = ""; transcribingItemName = nil
                            transcribingError = "Session expired. Please log in again."
                            if !AudioRecorderManager.shared.isRecording { AuthManager.shared.logout() }; return
                        } catch {
                            if Task.isCancelled { break }
                            if uploadAttempt == 2 {
                                transcribingError = error.localizedDescription
                                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch {}
                                transcribingError = nil
                            }
                        }
                    }
                    guard !Task.isCancelled, let triggerRes = uploadResult else { continue }

                    guard let taskId = triggerRes.taskId else {
                        transcribingError = triggerRes.message ?? "Failed to start transcription."
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        transcribingError = nil; continue
                    }

                    let recIndex = (recordings.firstIndex(where: { $0.id == result.recordingId }) ?? 0) + 1
                    let slug = item.name.lowercased().replacingOccurrences(of: " ", with: "-").filter { $0.isLetter || $0.isNumber || $0 == "-" }
                    let pendingLabel = "transcript-\(slug)-\(String(format: "%02d", recIndex)).txt"
                    PendingTaskStore.shared.add(PendingTaskEntry(taskId: taskId, itemId: item.id, itemName: item.name, label: pendingLabel, recordingId: result.recordingId, uploadedAt: Date()))
                    activeAudioTaskId = taskId

                    transcribingStatus = "Transcribing \(name)…"
                    var transcribedText: String? = nil
                    var attempt = 0; var consecutiveErrors = 0

                    pollLoop: while attempt < 120 {
                        guard !Task.isCancelled else { break pollLoop }
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        guard !Task.isCancelled else { break pollLoop }
                        do {
                            let poll = try await api.pollAudioResult(taskId: taskId)
                            consecutiveErrors = 0
                            switch poll.status {
                            case "completed":
                                transcribedText = poll.data?.responseData?.text
                                appLog("[CREDITS] Charged: \(String(format: "%.4f", poll.data?.totalCost ?? 0)) | Balance: paid=\(String(format: "%.4f", poll.data?.credit ?? 0))  free=\(String(format: "%.0f", poll.data?.freeCredit ?? 0))", level: .info)
                                break pollLoop
                            case "failed": transcribingError = poll.message ?? "Transcription failed."; break pollLoop
                            default: transcribingStatus = "Transcribing \(name)… \(attempt * 5)s"
                            }
                        } catch APIClientError.unauthorized {
                            failedRecordingIds.insert(result.recordingId)
                            transcribingRecordingId = nil; transcribingStatus = ""; transcribingItemName = nil
                            transcribingError = "Session expired. Please log in again."
                            if !AudioRecorderManager.shared.isRecording { AuthManager.shared.logout() }; return
                        } catch {
                            consecutiveErrors += 1
                            if consecutiveErrors >= 5 { transcribingError = "Connection lost."; break pollLoop }
                        }
                        attempt += 1
                    }

                    activeAudioTaskId = nil
                    if let text = transcribedText {
                        LocalTranscriptStore.shared.addOrReplace(LocalTranscriptEntry(id: UUID().uuidString, itemId: item.id, label: pendingLabel, text: text, durationSeconds: duration, createdAt: Date()))
                        PendingTaskStore.shared.remove(taskId: taskId)
                        sendCompletionNotification(title: "Transcription Ready", body: "'\(item.name)' transcribed.")
                        anyChunkSucceeded = true
                        lastSavedItemId = item.id
                        transcriptSaveCounter += 1
                        if UserDefaults.standard.bool(forKey: "auto_note") {
                            let allRecs = LocalRecordingStore.shared.recordings(for: item.id)
                            let allDone = !allRecs.isEmpty && allRecs.allSatisfy {
                                $0.id == result.recordingId ||
                                transcribedRecordingIds.contains($0.id) || failedRecordingIds.contains($0.id)
                            }
                            let notRecording = !AudioRecorderManager.shared.isRecording && !AudioRecorderManager.shared.isPaused
                            if allDone && notRecording {
                                let id = item.id; let name = item.name
                                NoteGenerationManager.shared.markQueued(itemId: id, transcriptIds: [])
                                TaskQueueManager.shared.enqueue { await NoteGenerationManager.shared.runAutoNote(for: id, itemName: name) }
                            } else {
                                appLog("  Auto-note deferred — \(allRecs.filter { $0.id != result.recordingId && !transcribedRecordingIds.contains($0.id) && !failedRecordingIds.contains($0.id) }.count) recording(s) not yet done or recording active")
                            }
                        }
                    } else {
                        PendingTaskStore.shared.remove(taskId: taskId)
                    }
                }

                if anyChunkSucceeded {
                    transcribedRecordingIds.insert(result.recordingId)
                    UserDefaults.standard.set(Array(transcribedRecordingIds), forKey: "transcribedRecordingIds")
                } else {
                    failedRecordingIds.insert(result.recordingId)
                }
            } catch {
                transcribingError = error.localizedDescription
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                transcribingError = nil
            }
            transcribingRecordingId = nil
        }
    }

    // MARK: - Resume orphaned tasks (called on app start)
    func resumePendingTasks() {
        let pending = PendingTaskStore.shared.all()
        guard !pending.isEmpty else { return }
        appLog("─────────────────────────────────")
        appLog("Resuming \(pending.count) pending task(s)…")
        resumeTask = Task {
            for entry in pending {
                guard !Task.isCancelled else { break }
                appLog("  Resuming taskId=\(entry.taskId) → '\(entry.label)'")
                var attempt = 0
                var transcribedText: String? = nil
                pollLoop: while attempt < 120 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { break pollLoop }
                    do {
                        let poll = try await api.pollAudioResult(taskId: entry.taskId)
                        switch poll.status {
                        case "completed":
                            transcribedText = poll.data?.responseData?.text
                            appLog("  ✓ Resumed '\(entry.label)'", level: .success)
                            break pollLoop
                        case "failed":
                            appLog("  ✗ Resumed task failed: \(poll.message ?? "failed")", level: .error)
                            break pollLoop
                        default:
                            break
                        }
                    } catch APIClientError.unauthorized {
                        appLog("  ✗ Session expired during resume poll", level: .error)
                        transcribingStatus = ""
                        transcribingItemName = nil
                        if !AudioRecorderManager.shared.isRecording { AuthManager.shared.logout() }
                        return
                    } catch {
                        // Network blip — keep polling
                    }
                    attempt += 1
                }
                if let text = transcribedText {
                    LocalTranscriptStore.shared.addOrReplace(LocalTranscriptEntry(
                        id: UUID().uuidString, itemId: entry.itemId, label: entry.label,
                        text: text, durationSeconds: nil, createdAt: Date()
                    ))
                    lastSavedItemId = entry.itemId
                    transcriptSaveCounter += 1
                    sendCompletionNotification(title: "Transcription Ready", body: "'\(entry.itemName)' transcribed.")
                }
                PendingTaskStore.shared.remove(taskId: entry.taskId)
            }
            appLog("Resume complete")
            appLog("─────────────────────────────────")
        }
    }

    // MARK: - Cancel (called by "Clear Task" button)
    func cancelAll() {
        resultClearTask?.cancel()
        resumeTask?.cancel()
        resumeTask = nil

        if let taskId = activeAudioTaskId {
            Task { try? await api.cancelAudioTask(taskId: taskId) }
            activeAudioTaskId = nil
        }

        TaskQueueManager.shared.clearAll()   // cancels running task + clears queue + calls resetState()
        appLog("All tasks cancelled by user", level: .warning)
    }

    /// Reset all display state — called by TaskQueueManager.clearAll()
    func resetState() {
        transcribingItemName = nil
        transcribingRecordingId = nil
        transcribingStatus = ""
        transcribingError = nil
        transcriptionResult = nil
        failedRecordingIds = []
        queuedRecordingIds = []
        PendingTaskStore.shared.clearAll()
    }
}

/// Handles note generation polling and tracks global processing state
/// for TextListView / ItemCardView indicators.
@MainActor
final class NoteGenerationManager: ObservableObject {
    static let shared = NoteGenerationManager()

    enum NoteState { case idle; case generating; case completed(text: String); case failed(String) }
    @Published var state: NoteState = .idle

    // MARK: - Global progress tracking (observed by TextListView / ItemCardView)
    @Published var processingItemId: String? = nil
    @Published var processingTranscriptIds: Set<String> = []
    @Published var completedTranscriptIds: Set<String> = []
    @Published var completedItemIds: Set<String> = []
    /// Items/transcripts that are scheduled in the queue but not yet running.
    @Published var queuedItemIds: Set<String> = []
    @Published var queuedTranscriptIds: Set<String> = []

    /// Call once for every item that is being added to TaskQueueManager before the tasks start.
    func markQueued(itemId: String, transcriptIds: [String]) {
        queuedItemIds.insert(itemId)
        transcriptIds.forEach { queuedTranscriptIds.insert($0) }
    }

    func begin(itemId: String, transcriptIds: [String]) {
        // Remove from queue — this item is now actively running
        queuedItemIds.remove(itemId)
        transcriptIds.forEach { queuedTranscriptIds.remove($0) }
        for id in transcriptIds { completedTranscriptIds.remove(id) }
        completedItemIds.remove(itemId)
        processingItemId = itemId
        processingTranscriptIds = Set(transcriptIds)
    }

    func finish(itemId: String, success: Bool) {
        let ids = processingTranscriptIds
        processingItemId = nil
        processingTranscriptIds = []
        if success {
            completedItemIds.insert(itemId)
            ids.forEach { completedTranscriptIds.insert($0) }
        }
    }

    private let api = APIClient.shared
    private var pollTask: Task<Void, Never>?

    /// Generate a note from transcript text using a prompt.
    /// - Parameters:
    ///   - transcript: The full transcript text to process
    ///   - promptId: The prompt ID to apply
    ///   - itemId: The item ID to associate the note with
    ///   - onComplete: Called with the generated note text
    func generate(transcript: String, promptId: String, itemId: String, onComplete: @escaping (String) -> Void) async {
        state = .generating

        struct Body: Encodable {
            let transcript: String
            let promptId: String
            enum CodingKeys: String, CodingKey {
                case transcript
                case promptId = "prompt_id"
            }
        }

        do {
            let res = try await api.request(
                path: "/api/notes/generate",
                method: "POST",
                body: Body(transcript: transcript, promptId: promptId),
                responseType: NoteGenerateResponse.self
            )

            guard let taskId = res.taskId else {
                state = .failed(res.message ?? "Failed to start generation.")
                return
            }

            pollTask = Task {
                var attempt = 0
                while attempt < 60 {
                    guard !Task.isCancelled else { return }
                    do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                    guard !Task.isCancelled else { return }

                    do {
                        let result = try await api.pollNoteResult(taskId: taskId)
                        switch result.status {
                        case "completed":
                            appLog("[CREDITS] Charged: \(String(format: "%.4f", result.creditCharge ?? 0)) | Balance: paid=\(String(format: "%.4f", result.credit ?? 0))  free=\(String(format: "%.0f", result.freeCredit ?? 0))", level: .info)
                            if let text = result.note {
                                try? await api.saveNote(text: text, itemId: itemId, promptLabel: promptId)
                                state = .completed(text: text)
                                onComplete(text)
                                sendCompletionNotification(title: "Note Ready", body: "Your note has been generated.")
                            } else {
                                state = .failed("No note text returned.")
                            }
                            return
                        case "failed":
                            let serverErr = result.error ?? "Generation failed."
                            appLog("  /api/notes/result — status: failed — \(serverErr) (task: \(taskId))", level: .error)
                            state = .failed(serverErr)
                            return
                        default: break
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        // Network blip — keep polling
                    }
                    attempt += 1
                }
                state = .failed("Generation timed out.")
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func cancel(taskId: String) {
        pollTask?.cancel()
        pollTask = nil
        Task { try? await api.cancelNoteTask(taskId: taskId) }
        state = .idle
        processingItemId = nil
        processingTranscriptIds = []
        queuedItemIds = []
        queuedTranscriptIds = []
    }

    func reset() {
        pollTask?.cancel()
        pollTask = nil
        state = .idle
        processingItemId = nil
        processingTranscriptIds = []
        queuedItemIds = []
        queuedTranscriptIds = []
    }

    // MARK: - Automatic Note (triggered after transcript save)

    /// Called automatically when a new transcript is saved. Reads saved automation prompts,
    /// picks the merge file for the item, and runs note generation in the background.
    func runAutoNote(for itemId: String, itemName: String) async {
        let encoded = UserDefaults.standard.string(forKey: "auto_note_prompts_encoded") ?? ""
        guard !encoded.isEmpty else {
            await MainActor.run { queuedItemIds.remove(itemId) }
            return
        }

        let pairs: [(id: String, name: String)] = encoded.split(separator: ",").compactMap { pair in
            let parts = pair.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (id: String(parts[0]), name: String(parts[1]))
        }
        guard !pairs.isEmpty else {
            await MainActor.run { queuedItemIds.remove(itemId) }
            return
        }

        // Ensure merge file is up-to-date before using it
        LocalTranscriptStore.shared.rebuildMerge(for: itemId, itemName: itemName)
        let transcripts = LocalTranscriptStore.shared.transcripts(for: itemId)
        guard let merge = transcripts.first(where: { $0.isMerge }),
              !merge.text.isEmpty else {
            await MainActor.run { queuedItemIds.remove(itemId) }
            return
        }

        await MainActor.run { begin(itemId: itemId, transcriptIds: [merge.id]) }
        var success = true
        for pair in pairs {
            let ok = await runNoteGenerationEntry(
                text: merge.text, promptId: pair.id,
                itemId: itemId, promptName: pair.name, itemName: itemName
            )
            if !ok { success = false; break }
        }
        await MainActor.run { finish(itemId: itemId, success: success) }
    }

    private func runNoteGenerationEntry(
        text: String, promptId: String,
        itemId: String, promptName: String, itemName: String
    ) async -> Bool {
        struct Body: Encodable {
            let transcript: String
            let promptId: String
            enum CodingKeys: String, CodingKey { case transcript; case promptId = "prompt_id" }
        }
        struct Res: Decodable {
            let success: Bool
            let taskId: String?
            enum CodingKeys: String, CodingKey { case success; case taskId = "task_id" }
        }
        do {
            let res = try await api.request(
                path: "/api/notes/generate", method: "POST",
                body: Body(transcript: text, promptId: promptId),
                responseType: Res.self
            )
            guard let taskId = res.taskId else { return false }
            var attempt = 0
            while attempt < 60 {
                guard !Task.isCancelled else { return false }
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return false }
                guard !Task.isCancelled else { return false }
                do {
                    let result = try await api.pollNoteResult(taskId: taskId)
                    switch result.status {
                    case "completed":
                        appLog("[CREDITS] Charged: \(String(format: "%.4f", result.creditCharge ?? 0)) | Balance: paid=\(String(format: "%.4f", result.credit ?? 0))  free=\(String(format: "%.0f", result.freeCredit ?? 0))", level: .info)
                        if let noteText = result.note {
                            let label = "Note-\(itemName)-\(promptName)"
                            LocalNoteStore.shared.addOrReplace(LocalNoteEntry(
                                id: UUID().uuidString, itemId: itemId,
                                label: label, text: noteText,
                                promptType: promptName, createdAt: Date()
                            ))
                            sendCompletionNotification(title: "Note Ready", body: "'\(itemName)' note has been generated.")
                            return true
                        }
                        return false
                    case "failed": return false
                    default: break
                    }
                } catch {
                    guard !Task.isCancelled else { return false }
                }
                attempt += 1
            }
        } catch {}
        return false
    }
}

// MARK: - Notification helper (file-level, nonisolated)
func sendCompletionNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
}

/// Handles image processing (send image + prompt → AI analysis)
@MainActor
final class ImageProcessingManager: ObservableObject {
    static let shared = ImageProcessingManager()
    private init() {}

    @Published var processingImageId: String? = nil
    @Published var pendingImageIds: Set<String> = []     // queued but not yet running
    @Published var completedImageIds: Set<String> = []
    @Published var failedImageId: String? = nil
    @Published var failedError: String? = nil
    @Published var processingStatus: String = ""
    @Published var processingItemId: String? = nil
    @Published var processingResult: Bool? = nil
    @Published var lastFinishedImageId: String? = nil

    private let api = APIClient.shared
    private var resultClearTask: Task<Void, Never>?
    private var activeImageTaskId: String?

    /// Enqueue image processing. Only adds to the queue — display state is set
    /// inside run() when it is actually this image's turn.
    func start(imageId: String, imageURL: URL, promptId: String, itemId: String, itemName: String) {
        pendingImageIds.insert(imageId)
        TaskQueueManager.shared.enqueue { [weak self] in
            guard let self, !Task.isCancelled else {
                self?.pendingImageIds.remove(imageId)
                return
            }
            await self.run(imageId: imageId, imageURL: imageURL, promptId: promptId,
                           itemId: itemId, itemName: itemName)
        }
    }

    private func run(imageId: String, imageURL: URL, promptId: String,
                     itemId: String, itemName: String) async {
        // Now it's this image's turn — set display state
        pendingImageIds.remove(imageId)
        processingImageId = imageId
        processingItemId = itemId
        processingStatus = ""
        processingResult = nil
        failedImageId = nil
        failedError = nil
        lastFinishedImageId = nil
        resultClearTask?.cancel()
        TranscriptionManager.shared.transcribingItemName = itemName
        TranscriptionManager.shared.transcribingStatus = ""

        appLog("[IMG] Starting — imageId: \(imageId), promptId: \(promptId)")
        // Always clean up spinner if cancelled mid-run
        defer {
            if processingImageId == imageId {
                processingImageId = nil
                processingStatus = ""
                TranscriptionManager.shared.transcribingItemName = nil
                TranscriptionManager.shared.transcribingStatus = ""
                activeImageTaskId = nil
            }
        }

        // ── 1. Load + resize image ────────────────────────────────────────────
        processingStatus = "Loading image…"
        TranscriptionManager.shared.transcribingStatus = "Loading image…"
        guard let uiImage = UIImage(contentsOfFile: imageURL.path) else {
            appLog("[IMG] ERROR: Could not load image from path: \(imageURL.path)", level: .error)
            fail(imageId: imageId, error: "Could not load image file."); return
        }
        let resized = uiImage.resizedToMaxDimension(1024)
        guard let jpegData = resized.jpegData(compressionQuality: 0.8) else {
            fail(imageId: imageId, error: "Could not encode image."); return
        }
        appLog("[IMG] JPEG after resize: \(jpegData.count / 1024)KB")

        // ── 2. Extract Supabase URL + userId from JWT ─────────────────────────
        guard let token = KeychainService.shared.getToken(),
              let supabaseBase = supabaseURL(from: token),
              let userId = jwtSubject(from: token) else {
            appLog("[IMG] ERROR: Could not extract Supabase info from token", level: .error)
            fail(imageId: imageId, error: "Authentication error. Please log in again."); return
        }

        // ── 3. Upload to Supabase imports bucket ──────────────────────────────
        processingStatus = "Uploading image…"
        TranscriptionManager.shared.transcribingStatus = "Uploading image…"
        let filename = "\(UUID().uuidString).jpg"
        let storagePath = "\(userId)/\(filename)"
        let uploadURL = URL(string: "\(supabaseBase)/storage/v1/object/imports/\(storagePath)")!
        appLog("[IMG] Uploading to Supabase: \(uploadURL)")

        var uploadReq = URLRequest(url: uploadURL, timeoutInterval: 60)
        uploadReq.httpMethod = "POST"
        uploadReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        uploadReq.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        uploadReq.httpBody = jpegData

        do {
            let (uploadData, uploadResp) = try await URLSession.shared.data(for: uploadReq)
            let uploadStatus = (uploadResp as? HTTPURLResponse)?.statusCode ?? 0
            appLog("[IMG] Supabase upload status: \(uploadStatus)")
            guard uploadStatus == 200 || uploadStatus == 201 else {
                appLog("[IMG] Upload body: \(String(data: uploadData, encoding: .utf8) ?? "<binary>")", level: .error)
                fail(imageId: imageId, error: "Image upload failed (HTTP \(uploadStatus)).")
                return
            }
        } catch {
            appLog("[IMG] ERROR: Supabase upload failed — \(error)", level: .error)
            fail(imageId: imageId, error: "Image upload failed: \(error.localizedDescription)"); return
        }

        // ── 4. Call /api/image/process with storagePath ───────────────────────
        processingStatus = "Processing image…"
        TranscriptionManager.shared.transcribingStatus = "Processing image…"
        struct Body: Encodable {
            let storagePath: String
            let promptId: String
            enum CodingKeys: String, CodingKey { case storagePath = "storagePath"; case promptId = "prompt_id" }
        }

        do {
            appLog("[IMG] POST /api/image/process — storagePath: \(storagePath)")
            let res = try await api.request(
                path: "/api/image/process",
                method: "POST",
                body: Body(storagePath: storagePath, promptId: promptId),
                responseType: ImageProcessResponse.self
            )
            appLog("[IMG] Response — success: \(res.success), taskId: \(res.taskId ?? "nil")")
            guard let taskId = res.taskId else {
                fail(imageId: imageId, error: res.message ?? "Failed to start image processing."); return
            }
            activeImageTaskId = taskId

            // ── 5. Poll for result ────────────────────────────────────────────
            var attempt = 0
            while attempt < 60 {
                guard !Task.isCancelled else { return }
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                processingStatus = "Processing image… \(attempt * 5)s"
                TranscriptionManager.shared.transcribingStatus = processingStatus

                do {
                    let result = try await api.pollImageResult(taskId: taskId)
                    appLog("[IMG] Poll \(attempt + 1) — status: \(result.status)")
                    switch result.status {
                    case "completed":
                        appLog("[CREDITS] Charged: \(String(format: "%.4f", result.creditCharge ?? 0)) | Balance: paid=\(String(format: "%.4f", result.credit ?? 0))  free=\(String(format: "%.0f", result.freeCredit ?? 0))", level: .info)
                        if let text = result.note {
                            appLog("[IMG] Done — saving note (\(text.count) chars)", level: .success)
                            let idx = LocalTranscriptStore.shared.count(for: itemId)
                            LocalTranscriptStore.shared.add(LocalTranscriptEntry(
                                id: UUID().uuidString,
                                itemId: itemId,
                                label: "image-analysis-\(String(format: "%02d", idx + 1))",
                                text: text,
                                durationSeconds: nil,
                                createdAt: Date()
                            ))
                        } else {
                            appLog("[IMG] ERROR: completed but note is nil", level: .error)
                        }
                        completedImageIds.insert(imageId)
                        lastFinishedImageId = imageId   // triggers queue advance
                        processingImageId = nil
                        processingStatus = ""
                        TranscriptionManager.shared.transcribingItemName = nil
                        TranscriptionManager.shared.transcribingStatus = ""
                        processingResult = true
                        sendCompletionNotification(title: "Image Note Ready", body: "Image analysis saved to Text.")
                        resultClearTask = Task {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            self.processingResult = nil
                            self.processingItemId = nil
                        }
                        return
                    case "failed":
                        fail(imageId: imageId, error: result.error ?? "Image processing failed."); return
                    default: break
                    }
                } catch {
                    appLog("[IMG] Poll error attempt \(attempt + 1): \(error)", level: .warning)
                    guard !Task.isCancelled else { return }
                }
                attempt += 1
            }
            fail(imageId: imageId, error: "Image processing timed out.")
        } catch {
            appLog("[IMG] ERROR: \(error)", level: .error)
            fail(imageId: imageId, error: error.localizedDescription)
        }
    }

    private func fail(imageId: String, error: String) {
        processingImageId = nil
        processingStatus = ""
        TranscriptionManager.shared.transcribingItemName = nil
        TranscriptionManager.shared.transcribingStatus = ""
        failedImageId = imageId
        failedError = error
        lastFinishedImageId = imageId   // triggers queue advance even on failure
        resultClearTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self.processingItemId = nil
        }
    }

    /// Extracts the Supabase project base URL from the JWT `iss` claim.
    /// e.g. "https://xxxx.supabase.co/auth/v1" → "https://xxxx.supabase.co"
    private func supabaseURL(from jwt: String) -> String? {
        guard let payload = jwtPayload(from: jwt),
              let iss = payload["iss"] as? String else { return nil }
        // Strip the /auth/v1 suffix
        if let range = iss.range(of: "/auth/v1") {
            return String(iss[..<range.lowerBound])
        }
        return iss
    }

    /// Extracts the `sub` (userId) claim from the JWT.
    private func jwtSubject(from jwt: String) -> String? {
        guard let payload = jwtPayload(from: jwt) else { return nil }
        return payload["sub"] as? String
    }

    /// Decodes the JWT payload (middle segment, base64url).
    private func jwtPayload(from jwt: String) -> [String: Any]? {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    func cancel() {
        if let taskId = activeImageTaskId {
            Task { try? await api.cancelImageTask(taskId: taskId) }
            activeImageTaskId = nil
        }
        resultClearTask?.cancel()
        processingImageId = nil
        processingItemId = nil
        processingStatus = ""
        processingResult = nil
    }
}

private extension UIImage {
    func resizedToMaxDimension(_ maxDim: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDim else { return self }
        let scale = maxDim / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
