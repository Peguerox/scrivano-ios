import Foundation
import Combine

/// Handles the full upload → poll → save flow for audio transcription.
@MainActor
final class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    private init() {}

    enum TranscriptionState {
        case idle
        case uploading
        case processing(progress: String)
        case completed(text: String)
        case failed(String)
    }

    @Published var state: TranscriptionState = .idle

    private let api = APIClient.shared
    private var pollTask: Task<Void, Never>?

    /// Full flow: upload audio → trigger.dev job → poll until done → save transcript
    func transcribe(
        audioURL: URL,
        durationSeconds: Double,
        itemId: String,
        onComplete: @escaping (String) -> Void
    ) async {
        state = .uploading

        // Read audio data
        guard let audioData = try? Data(contentsOf: audioURL) else {
            state = .failed("Failed to read audio file.")
            return
        }

        // Upload & trigger job
        let filename = audioURL.lastPathComponent
        let triggerRes: TranscribeResponse
        do {
            triggerRes = try await api.uploadAudio(
                data: audioData,
                filename: filename,
                durationSeconds: durationSeconds
            )
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        guard let taskId = triggerRes.taskId else {
            state = .failed(triggerRes.message ?? "Failed to start transcription.")
            return
        }

        // Poll for result
        state = .processing(progress: "Transcribing…")
        pollTask = Task {
            var attempt = 0
            let maxAttempts = 120 // 10 min at 5s intervals

            while attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                guard !Task.isCancelled else { return }

                do {
                    let result = try await api.pollResult(taskId: taskId, endpoint: "/api/audio/result")
                    switch result.status {
                    case "COMPLETED":
                        if let text = result.output?.text {
                            // Save transcript to server
                            try? await api.saveTranscript(itemId: itemId, text: text, audioFileId: taskId)
                            state = .completed(text: text)
                            onComplete(text)
                        } else {
                            state = .failed("No transcription text returned.")
                        }
                        return
                    case "FAILED":
                        state = .failed(result.error ?? "Transcription failed.")
                        return
                    default:
                        // Still executing
                        let elapsed = attempt * 5
                        state = .processing(progress: "Transcribing… \(elapsed)s")
                    }
                } catch {
                    // Network blip — keep polling
                }
                attempt += 1
            }
            state = .failed("Transcription timed out.")
        }
    }

    func cancel(taskId: String) {
        pollTask?.cancel()
        Task { try? await api.cancelTask(taskId: taskId, endpoint: "/api/audio/cancel") }
        state = .idle
    }

    func reset() {
        pollTask?.cancel()
        state = .idle
    }
}

/// Handles note generation polling
@MainActor
final class NoteGenerationManager: ObservableObject {
    enum NoteState { case idle; case generating; case completed(text: String); case failed(String) }
    @Published var state: NoteState = .idle

    private let api = APIClient.shared

    func generate(promptId: String, textFileIds: [String], itemId: String, onComplete: @escaping (String) -> Void) async {
        state = .generating

        struct Body: Encodable {
            let promptId: String; let textFileIds: [String]; let itemId: String
            enum CodingKeys: String, CodingKey { case promptId = "prompt_id"; case textFileIds = "text_file_ids"; case itemId = "item_id" }
        }
        struct Res: Decodable { let success: Bool; let taskId: String?; let message: String?; enum CodingKeys: String, CodingKey { case success; case taskId = "task_id"; case message } }

        do {
            let res = try await api.request(
                path: "/api/notes/generate",
                method: "POST",
                body: Body(promptId: promptId, textFileIds: textFileIds, itemId: itemId),
                responseType: Res.self
            )

            guard let taskId = res.taskId else {
                state = .failed(res.message ?? "Failed to start generation.")
                return
            }

            // Poll
            var attempt = 0
            while attempt < 60 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let result = try await api.pollResult(taskId: taskId, endpoint: "/api/notes/result")
                switch result.status {
                case "COMPLETED":
                    if let text = result.output?.text {
                        state = .completed(text: text)
                        onComplete(text)
                    } else {
                        state = .failed("No text returned.")
                    }
                    return
                case "FAILED":
                    state = .failed(result.error ?? "Generation failed.")
                    return
                default: break
                }
                attempt += 1
            }
            state = .failed("Generation timed out.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reset() { state = .idle }
}
