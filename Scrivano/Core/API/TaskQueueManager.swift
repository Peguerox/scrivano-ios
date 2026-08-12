import Foundation
import BackgroundTasks
import UserNotifications

/// Serial background task queue. Every transcription and note-generation job is
/// routed here so that at most ONE job runs at a time and new submissions never
/// cancel in-progress work.
@MainActor
final class TaskQueueManager: ObservableObject {
    static let shared = TaskQueueManager()

    @Published var pendingCount: Int = 0
    @Published var isProcessing: Bool = false

    private var queue: [() async -> Void] = []
    private var runningTask: Task<Void, Never>?

    private init() {}

    // MARK: - Enqueue

    /// Add a unit of work to the end of the queue. If nothing is running it
    /// starts immediately; otherwise it waits its turn.
    func enqueue(_ work: @escaping () async -> Void) {
        queue.append(work)
        pendingCount = queue.count
        if runningTask == nil { startNext() }
    }

    // MARK: - Private

    private func startNext() {
        guard !queue.isEmpty else {
            isProcessing = false
            pendingCount = 0
            return
        }
        isProcessing = true
        let work = queue.removeFirst()
        pendingCount = queue.count

        runningTask = Task {
            await work()
            // Only advance if we haven't been force-cleared
            self.runningTask = nil
            self.startNext()
        }
    }

    // MARK: - Cancel everything

    /// Cancels the currently running task and discards all queued work.
    /// Resets both TranscriptionManager and NoteGenerationManager state.
    func clearAll() {
        queue.removeAll()
        pendingCount = 0
        isProcessing = false
        runningTask?.cancel()
        runningTask = nil
        TranscriptionManager.shared.resetState()
        NoteGenerationManager.shared.reset()
    }
}

// MARK: - BackgroundTaskManager

/// Manages BGProcessingTask scheduling and execution.
/// When the app is backgrounded while transcriptions are pending,
/// iOS will run the registered task handler at an opportune time
/// (network available, device not under heavy load) to finish polling.
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    static let taskIdentifier = "com.scrivano.app.resume-pending"

    private init() {}

    // MARK: - Registration (call once before app finishes launching)

    /// Must be called in ScrivanoApp.init() — BGTaskScheduler requires registration
    /// before the app finishes launching or the handler will never fire.
    static func registerHandler() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: DispatchQueue.main
        ) { task in
            BackgroundTaskManager.shared.handle(task as! BGProcessingTask)
        }
    }

    // MARK: - Scheduling

    /// Call when the app goes to background and there are pending transcription or note tasks.
    func scheduleIfNeeded() {
        let hasPendingTranscriptions = !PendingTaskStore.shared.all().isEmpty
        let hasPendingNotes = !PendingNoteTaskStore.shared.all().isEmpty
        guard hasPendingTranscriptions || hasPendingNotes else { return }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)

        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            appLog("BGTask scheduled — \(PendingTaskStore.shared.all().count) transcription(s), \(PendingNoteTaskStore.shared.all().count) note(s)", level: .info)
        } catch {
            appLog("BGTask schedule failed: \(error.localizedDescription)", level: .warning)
        }
    }

    // MARK: - Handler

    private func handle(_ task: BGProcessingTask) {
        scheduleIfNeeded()  // reschedule in case we don't finish this run

        let work = Task {
            // Run both poll loops concurrently — they target different server endpoints
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.resumePendingTranscriptions() }
                group.addTask { await self.resumePendingNotePolling() }
            }
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
            appLog("BGTask expired — remaining tasks will retry next opportunity", level: .warning)
        }
    }

    // MARK: - Poll loop

    /// Polls every pending transcription task until completed, failed, or time runs out.
    func resumePendingTranscriptions() async {
        let pending = PendingTaskStore.shared.all()
        guard !pending.isEmpty else { return }

        appLog("BGTask: resuming \(pending.count) pending transcription(s)", level: .info)
        let api = APIClient.shared

        for entry in pending {
            guard !Task.isCancelled else { break }

            var attempt = 0
            var consecutiveErrors = 0

            pollLoop: while attempt < 20 {  // max ~9 min with exponential backoff (3s→30s)
                guard !Task.isCancelled else { break pollLoop }
                let delayNs = UInt64(min(3.0 * pow(1.5, Double(attempt)), 30.0) * 1_000_000_000)
                do { try await Task.sleep(nanoseconds: delayNs) } catch { break pollLoop }
                guard !Task.isCancelled else { break pollLoop }

                do {
                    let poll = try await api.pollAudioResult(taskId: entry.taskId)
                    consecutiveErrors = 0
                    appLog("BGTask poll #\(attempt + 1) [\(entry.itemName)]: \(poll.status)")

                    switch poll.status {
                    case "completed":
                        if let text = poll.data?.responseData?.text {
                            await saveTranscript(entry: entry, text: text)
                            sendNotification(title: "Transcription Ready",
                                             body: "'\(entry.itemName)' has been transcribed.")
                        }
                        break pollLoop
                    case "failed":
                        await MainActor.run { PendingTaskStore.shared.remove(taskId: entry.taskId) }
                        sendNotification(title: "Transcription Failed",
                                         body: "'\(entry.itemName)' could not be transcribed.")
                        appLog("BGTask: task failed for '\(entry.itemName)'", level: .error)
                        break pollLoop
                    default:
                        break
                    }
                } catch {
                    consecutiveErrors += 1
                    appLog("BGTask poll error (\(consecutiveErrors)): \(error.localizedDescription)", level: .warning)
                    if consecutiveErrors >= 5 { break pollLoop }
                }
                attempt += 1
            }
        }
    }

    // MARK: - Note poll loop (BGTask context)

    /// Polls every pending note task until completed, failed, or time runs out.
    func resumePendingNotePolling() async {
        let pending = PendingNoteTaskStore.shared.all()
        guard !pending.isEmpty else { return }

        appLog("BGTask: resuming \(pending.count) pending note(s)", level: .info)
        let api = APIClient.shared

        for entry in pending {
            guard !Task.isCancelled else { break }

            var attempt = 0
            var consecutiveErrors = 0

            pollLoop: while attempt < 20 {  // max ~9 min with exponential backoff (3s→30s)
                guard !Task.isCancelled else { break pollLoop }
                let delayNs = UInt64(min(3.0 * pow(1.5, Double(attempt)), 30.0) * 1_000_000_000)
                do { try await Task.sleep(nanoseconds: delayNs) } catch { break pollLoop }
                guard !Task.isCancelled else { break pollLoop }

                do {
                    let result = try await api.pollNoteResult(taskId: entry.taskId)
                    consecutiveErrors = 0
                    appLog("BGTask note poll #\(attempt + 1) [\(entry.itemName)/\(entry.promptName)]: \(result.status)")

                    switch result.status {
                    case "completed":
                        if let noteText = result.note {
                            await MainActor.run {
                                let label = "Note-\(entry.itemName)-\(entry.promptName)"
                                LocalNoteStore.shared.addOrReplace(LocalNoteEntry(
                                    id: UUID().uuidString, itemId: entry.itemId,
                                    label: label, text: noteText,
                                    promptType: entry.promptName, createdAt: Date()
                                ))
                                PendingNoteTaskStore.shared.remove(taskId: entry.taskId)
                            }
                            sendNotification(title: "Note Ready",
                                             body: "'\(entry.itemName)' note has been generated.")
                            appLog("BGTask: saved note for '\(entry.itemName)'", level: .success)
                        } else {
                            PendingNoteTaskStore.shared.remove(taskId: entry.taskId)
                        }
                        break pollLoop
                    case "failed":
                        PendingNoteTaskStore.shared.remove(taskId: entry.taskId)
                        sendNotification(title: "Note Failed",
                                         body: "'\(entry.itemName)' — note generation failed.")
                        appLog("BGTask: note failed for '\(entry.itemName)'", level: .error)
                        break pollLoop
                    default:
                        break
                    }
                } catch {
                    consecutiveErrors += 1
                    appLog("BGTask note poll error (\(consecutiveErrors)): \(error.localizedDescription)", level: .warning)
                    if consecutiveErrors >= 5 { break pollLoop }
                }
                attempt += 1
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func saveTranscript(entry: PendingTaskEntry, text: String) {
        LocalTranscriptStore.shared.addOrReplace(LocalTranscriptEntry(
            id: UUID().uuidString,
            itemId: entry.itemId,
            label: entry.label,
            text: text,
            durationSeconds: nil,
            createdAt: Date()
        ))
        PendingTaskStore.shared.remove(taskId: entry.taskId)
        var ids = Set(UserDefaults.standard.stringArray(forKey: "transcribedRecordingIds") ?? [])
        ids.insert(entry.recordingId)
        UserDefaults.standard.set(Array(ids), forKey: "transcribedRecordingIds")
        appLog("BGTask: saved transcript for '\(entry.itemName)'", level: .success)
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
