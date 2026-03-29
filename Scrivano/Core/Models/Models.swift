import Foundation

// MARK: - User & Auth
struct User: Codable {
    let id: String
    let email: String
    let firstName: String
    let plan: String
    var credit: Double
    var freeCredit: Double

    enum CodingKeys: String, CodingKey {
        case id, email
        case firstName = "first_name"
        case plan, credit
        case freeCredit = "free_credit"
    }
}

struct LoginResponse: Codable {
    let success: Bool
    let message: String?
    let token: String?
    let refreshToken: String?
    let user: User?

    enum CodingKeys: String, CodingKey {
        case success, message, token
        case refreshToken = "refresh_token"
        case user
    }
}

// MARK: - Collections & Items
struct ScrivanoCollection: Codable, Identifiable {
    let id: String
    let name: String
    let itemCount: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case itemCount = "item_count"
        case createdAt = "created_at"
    }
}

struct Item: Codable, Identifiable {
    let id: String
    let name: String
    let collectionId: String?
    let mediaCount: Int
    let textCount: Int
    let noteCount: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case collectionId = "collection_id"
        case mediaCount = "media_count"
        case textCount = "text_count"
        case noteCount = "note_count"
        case updatedAt = "updated_at"
    }
}

// MARK: - Audio / Transcription
struct TranscribeResponse: Codable {
    let success: Bool
    let taskId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success
        case taskId = "task_id"
        case message
    }
}

struct TaskResult: Codable {
    let status: String   // "EXECUTING" | "COMPLETED" | "FAILED"
    let output: TaskOutput?
    let error: String?
}

struct TaskOutput: Codable {
    let text: String?
    let audioDurationSeconds: Double?
    let totalCost: Double?
    let credit: Double?
    let freeCredit: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case audioDurationSeconds = "audio_duration_seconds"
        case totalCost = "total_cost"
        case credit
        case freeCredit = "free_credit"
    }
}

// MARK: - Notes
struct NoteGenerateResponse: Codable {
    let success: Bool
    let taskId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success
        case taskId = "task_id"
        case message
    }
}

// MARK: - Prompts
struct Prompt: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let category: String?
    let tags: [String]
    let isCustom: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, tags
        case isCustom = "is_custom"
    }
}

struct PromptsResponse: Codable {
    let success: Bool
    let prompts: [Prompt]
}

// MARK: - API Error
struct APIError: Codable {
    let success: Bool
    let message: String
}

struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let message: String?
    let data: T?
}
