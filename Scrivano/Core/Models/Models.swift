import Foundation

// MARK: - User & Auth
struct User: Codable {
    let id: String
    let email: String
    var firstName: String
    var plan: String
    var credit: Double
    var freeCredit: Double

    enum CodingKeys: String, CodingKey {
        case id, email, plan, credit, name
        case firstName = "first_name"
        case freeCredit = "free_credit"
    }

    init(id: String, email: String, firstName: String, plan: String, credit: Double, freeCredit: Double) {
        self.id = id; self.email = email; self.firstName = firstName
        self.plan = plan; self.credit = credit; self.freeCredit = freeCredit
    }

    // Custom decoder: handles both `first_name` (login) and `name` (/api/auth/me),
    // and tolerates missing optional fields so a partial response never breaks decoding.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(String.self, forKey: .id)
        email      = try c.decode(String.self, forKey: .email)
        plan       = (try? c.decode(String.self, forKey: .plan)) ?? "free"
        credit     = (try? c.decode(Double.self, forKey: .credit)) ?? 0
        freeCredit = (try? c.decode(Double.self, forKey: .freeCredit)) ?? 0
        if let fn = try? c.decode(String.self, forKey: .firstName), !fn.isEmpty {
            firstName = fn
        } else {
            firstName = (try? c.decode(String.self, forKey: .name)) ?? ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,         forKey: .id)
        try c.encode(email,      forKey: .email)
        try c.encode(firstName,  forKey: .firstName)
        try c.encode(plan,       forKey: .plan)
        try c.encode(credit,     forKey: .credit)
        try c.encode(freeCredit, forKey: .freeCredit)
    }

    var hasBYOK: Bool {
        let p = plan.lowercased()
        return p.contains("api") || p.contains("byok") || p == "bring_your_own"
    }
}

struct LoginResponse: Codable {
    let success: Bool
    let message: String?
    let token: String?
    let refreshToken: String?
    let user: User?
    let confirmedEmail: Bool?

    enum CodingKeys: String, CodingKey {
        case success, message, token
        case refreshToken = "refresh_token"
        case user
        case confirmedEmail = "confirmed_email"
    }
}

// MARK: - Collections & Items

struct ScrivanoCollection: Codable, Identifiable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id, name
    }
}

final class LocalCollectionStore {
    static let shared = LocalCollectionStore()
    private let storeURL: URL
    private let queue = DispatchQueue(label: "com.scrivano.collectionstore", qos: .utility)
    private(set) var collections: [ScrivanoCollection] = []

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = docs.appendingPathComponent("collections_manifest.json")
        load()
    }

    func save(_ collection: ScrivanoCollection) {
        if let idx = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[idx] = collection
        } else {
            collections.append(collection)
        }
        persist()
    }

    func delete(_ id: String) {
        collections.removeAll { $0.id == id }
        persist()
    }

    func all() -> [ScrivanoCollection] { collections }

    func clearAll() { collections.removeAll(); persist() }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([ScrivanoCollection].self, from: data)
        else { return }
        collections = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(collections) else { return }
        queue.async { [url = storeURL] in try? data.write(to: url, options: .atomic) }
    }
}

/// Local item — stored on-device only. Never fetched from server.
struct Item: Codable, Identifiable {
    let id: String
    let name: String
    let collection: String?
    let collectionId: String?
    let createdAt: String
    let transcripts: [TranscriptSummary]?
    let notes: [NoteSummary]?

    var textCount: Int  { transcripts?.count ?? 0 }
    var noteCount: Int  { notes?.count ?? 0 }

    func renamed(to newName: String) -> Item {
        Item(id: id, name: newName, collection: collection, collectionId: collectionId,
             createdAt: createdAt, transcripts: transcripts, notes: notes)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, collection, transcripts, notes
        case collectionId = "collection_id"
        case createdAt = "createdAt"
    }
}

struct TranscriptSummary: Codable, Identifiable {
    let id: String
    let label: String
    let text: String
    let duration: String
    var isMerge: Bool = false
}

struct NoteSummary: Codable, Identifiable {
    let id: String
    let label: String
    let text: String
    let promptType: String
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

/// Matches GET /api/audio/result/:taskId
/// status: "running" | "completed" | "failed"
struct AudioTaskResult: Codable {
    let success: Bool?
    let status: String
    let message: String?
    let data: AudioTaskData?
}

struct AudioTaskData: Codable {
    let responseData: AudioResponseData?
    let audioDurationSeconds: Double?
    let totalCost: Double?
    let credit: Double?
    let freeCredit: Double?

    enum CodingKeys: String, CodingKey {
        case responseData = "response_data"
        case audioDurationSeconds = "audio_duration_seconds"
        case totalCost = "total_cost"
        case credit
        case freeCredit = "free_credit"
    }
}

struct AudioResponseData: Codable {
    let text: String?
}

/// Matches GET /api/notes/result/:taskId
/// status: "running" | "completed" | "failed"
struct NoteTaskResult: Codable {
    let status: String
    let note: String?
    let error: String?
    let result: NoteTaskResultData?

    struct NoteTaskResultData: Codable {
        let data: NoteTaskResultBody?
    }
    struct NoteTaskResultBody: Codable {
        let creditCharge: Double?
        let credit: Double?
        let freeCredit: Double?
        enum CodingKeys: String, CodingKey {
            case creditCharge = "credit_charge"
            case credit
            case freeCredit = "free_credit"
        }
    }
    var creditCharge: Double? { result?.data?.creditCharge }
    var credit: Double?       { result?.data?.credit }
    var freeCredit: Double?   { result?.data?.freeCredit }
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

// MARK: - Image list errors

enum ImageListError: LocalizedError {
    case encodingFailed, authFailed, uploadFailed(Int), noTaskId, timeout
    case processingFailed(String)
    var errorDescription: String? {
        switch self {
        case .encodingFailed:        return "Could not encode image."
        case .authFailed:            return "Authentication error. Please log in again."
        case .uploadFailed(let c):   return "Image upload failed (HTTP \(c))."
        case .noTaskId:              return "Failed to start image processing."
        case .timeout:               return "Timed out waiting for result."
        case .processingFailed(let m): return "Processing failed: \(m)"
        }
    }
}

// MARK: - Image processing

struct ImageProcessResponse: Codable {
    let success: Bool
    let taskId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success
        case taskId = "task_id"
        case message
    }
}

/// Matches GET /api/image/result/:taskId
/// Server returns: { status, result: { success, data: { response_data: { note } } } }
struct ImageTaskResult: Codable {
    let status: String
    let result: ImageTaskResultBody?
    let error: String?

    /// Extracts the note text from the nested structure
    var note: String? { result?.data?.responseData?.note }

    struct ImageTaskResultBody: Codable {
        let success: Bool?
        let data: ImageTaskResultData?
    }
    struct ImageTaskResultData: Codable {
        let responseData: ImageTaskResultNote?
        let creditCharge: Double?
        let credit: Double?
        let freeCredit: Double?
        enum CodingKeys: String, CodingKey {
            case responseData = "response_data"
            case creditCharge = "credit_charge"
            case credit
            case freeCredit = "free_credit"
        }
    }
    struct ImageTaskResultNote: Codable {
        let note: String?
    }
    var creditCharge: Double? { result?.data?.creditCharge }
    var credit: Double?       { result?.data?.credit }
    var freeCredit: Double?   { result?.data?.freeCredit }
}

// MARK: - Prompts

struct Prompt: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let promptType: String?
    private let promptCategoriesRaw: String?

    // New structured fields (optional — fall back to parsing description if absent)
    private let promptTitle: String?
    private let promptOverview: String?
    private let promptExample: String?
    let averageCreditCost: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name = "prompt_name"
        case description = "prompt_description"
        case promptType = "prompt_type"
        case promptCategoriesRaw = "prompt_categories"
        case promptTitle = "prompt_title"
        case promptOverview = "prompt_overview"
        case promptExample = "prompt_example"
        case averageCreditCost = "average_credit_cost"
    }

    /// Display title — uses prompt_title if available, else prompt_name
    var displayName: String { promptTitle ?? name }

    /// Parsed flat dict, e.g. ["profession": "Medical", "language": "English"]
    var categories: [String: String] {
        guard let raw = promptCategoriesRaw,
              let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    /// Uses prompt_overview if available, otherwise parses from description
    var overview: String {
        if let o = promptOverview, !o.isEmpty { return o }
        let splits = ["\\n\\nAverage", "\\n\\nExample", "\n\nAverage", "\n\nExample"]
        for sep in splits {
            if let r = description.range(of: sep, options: [.caseInsensitive, .regularExpression]) {
                return String(description[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return description
    }

    /// Uses prompt_example if available, otherwise parses from description
    var example: String? {
        if let e = promptExample, !e.isEmpty { return e }
        guard let r = description.range(of: "Example:", options: .caseInsensitive) else { return nil }
        let raw = String(description[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }
}

struct PromptsResponse: Codable {
    let success: Bool
    let data: [Prompt]
}

// MARK: - Collection Upload

struct CollectionUploadPayload: Encodable {
    let dictionaryname: String
    let dictionarytime: String
    let items: [CollectionUploadItem]
}

struct CollectionUploadItem: Encodable {
    let itemname: String
    let transcriptions: [CollectionUploadTranscription]
    let notes: [CollectionUploadNote]
}

struct CollectionUploadTranscription: Encodable {
    let transcriptionname: String
    let transcriptiontext: String
    let notes: [CollectionUploadNote]
}

struct CollectionUploadNote: Encodable {
    let notename: String
    let notetext: String
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

// MARK: - Local Recording Store

struct LocalRecordingEntry: Codable, Identifiable {
    let id: String
    let itemId: String
    var relativePath: String   // relative to Documents directory
    let createdAt: Date
    let durationSeconds: Double
    var label: String? = nil   // custom display name override (e.g. after split)

    var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(relativePath)
    }
}

final class LocalRecordingStore {
    static let shared = LocalRecordingStore()

    private let manifestURL: URL
    private let queue = DispatchQueue(label: "com.scrivano.recordingstore", qos: .utility)
    private(set) var entries: [LocalRecordingEntry] = []

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        manifestURL = docs.appendingPathComponent("recordings_manifest.json")
        load()
    }

    func add(_ entry: LocalRecordingEntry) {
        entries.append(entry)
        persist()
    }

    func update(_ entry: LocalRecordingEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
            persist()
        }
    }

    func delete(id: String) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func deleteFile(at url: URL) {
        queue.async { try? FileManager.default.removeItem(at: url) }
    }

    func count(for itemId: String) -> Int {
        entries.filter { $0.itemId == itemId }.count
    }

    func recordings(for itemId: String) -> [LocalRecordingEntry] {
        entries.filter { $0.itemId == itemId }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Removes all recordings for an item from the manifest and deletes their files.
    func deleteAll(for itemId: String) {
        let toDelete = entries.filter { $0.itemId == itemId }
        entries.removeAll { $0.itemId == itemId }
        persist()
        queue.async {
            for entry in toDelete {
                try? FileManager.default.removeItem(at: entry.fileURL)
            }
        }
    }

    static func newFileURL(itemId: String, ext: String = "m4a") -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("recordings/\(itemId)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "recording_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).\(ext)"
        return dir.appendingPathComponent(name)
    }

    func clearAll() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        entries.removeAll()
        persist()
        queue.async {
            let dir = docs.appendingPathComponent("recordings")
            try? FileManager.default.removeItem(at: dir)
        }
    }

    static func relativePath(of url: URL) -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        let full = url.path
        guard full.hasPrefix(docs) else { return full }
        return String(full.dropFirst(docs.count + 1))
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([LocalRecordingEntry].self, from: data)
        else { return }
        entries = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        if entries.count != decoded.count { persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        queue.async { [url = manifestURL] in
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Local Item Store

struct LocalStoredItem: Codable, Identifiable {
    let id: String
    var name: String
    var collection: String?
    var collectionId: String?
    let createdAt: String
}

final class LocalItemStore {
    static let shared = LocalItemStore()
    private let storeURL: URL
    private let queue = DispatchQueue(label: "com.scrivano.itemstore", qos: .utility)
    private(set) var items: [LocalStoredItem] = []

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = docs.appendingPathComponent("items_manifest.json")
        load()
    }

    func save(_ item: LocalStoredItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) { items[idx] = item }
        else { items.insert(item, at: 0) }
        persist()
    }

    func delete(_ id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    func all() -> [LocalStoredItem] { items }

    func clearAll() { items.removeAll(); persist() }

    /// Removes the collection assignment from all items that belonged to the deleted collection.
    func clearCollection(_ collectionId: String) {
        var changed = false
        for idx in items.indices where items[idx].collectionId == collectionId {
            items[idx].collectionId = nil
            items[idx].collection = nil
            changed = true
        }
        if changed { persist() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([LocalStoredItem].self, from: data)
        else { return }
        items = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        queue.async { [url = storeURL] in try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Local Transcript Store

struct LocalTranscriptEntry: Codable, Identifiable {
    let id: String
    let itemId: String
    let label: String
    let text: String
    let durationSeconds: Double?
    let createdAt: Date
    var isMerge: Bool

    // Custom initialiser so call-sites keep `isMerge` defaulting to false
    init(id: String, itemId: String, label: String, text: String,
         durationSeconds: Double?, createdAt: Date, isMerge: Bool = false) {
        self.id = id; self.itemId = itemId; self.label = label
        self.text = text; self.durationSeconds = durationSeconds
        self.createdAt = createdAt; self.isMerge = isMerge
    }

    // Backward-compatible decode: old JSON without "isMerge" defaults to false
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self,  forKey: .id)
        itemId        = try c.decode(String.self,  forKey: .itemId)
        label         = try c.decode(String.self,  forKey: .label)
        text          = try c.decode(String.self,  forKey: .text)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
        createdAt     = try c.decode(Date.self,    forKey: .createdAt)
        isMerge       = (try? c.decode(Bool.self,  forKey: .isMerge)) ?? false
    }

    var summary: TranscriptSummary {
        let dur: String
        if let d = durationSeconds {
            dur = String(format: "%02d:%02d", Int(d) / 60, Int(d) % 60)
        } else { dur = "" }
        return TranscriptSummary(id: id, label: label, text: text, duration: dur, isMerge: isMerge)
    }
}

final class LocalTranscriptStore {
    static let shared = LocalTranscriptStore()
    private let storeURL: URL
    private let queue = DispatchQueue(label: "com.scrivano.transcriptstore", qos: .utility)
    private(set) var entries: [LocalTranscriptEntry] = []

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = docs.appendingPathComponent("transcripts_manifest.json")
        load()
    }

    func add(_ entry: LocalTranscriptEntry) { entries.append(entry); persist() }

    /// Replaces an existing transcript with the same label+itemId, or appends if none exists.
    func addOrReplace(_ entry: LocalTranscriptEntry) {
        if let idx = entries.firstIndex(where: { $0.itemId == entry.itemId && $0.label == entry.label }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        persist()
    }

    func transcripts(for itemId: String) -> [LocalTranscriptEntry] {
        entries.filter { $0.itemId == itemId }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Returns the number of real (non-merge) transcripts — used for display counts and filename indexing.
    func count(for itemId: String) -> Int { entries.filter { $0.itemId == itemId && !$0.isMerge }.count }

    func delete(id: String) { entries.removeAll { $0.id == id }; persist() }

    func update(_ entry: LocalTranscriptEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) { entries[idx] = entry; persist() }
    }

    func rename(id: String, newLabel: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let old = entries[idx]
        entries[idx] = LocalTranscriptEntry(id: old.id, itemId: old.itemId, label: newLabel,
                                            text: old.text, durationSeconds: old.durationSeconds,
                                            createdAt: old.createdAt, isMerge: old.isMerge)
        persist()
    }

    /// Rebuilds (or removes) the auto-managed Merge file for an item.
    /// Call this after any transcript add or delete.
    /// Extracts the trailing number from a transcript label, e.g. "transcript-name-02.txt" → 2.
    /// Used to keep split chunks in the correct order regardless of save timestamps.
    private static func labelSortIndex(_ label: String) -> Int {
        let base = label.hasSuffix(".txt") ? String(label.dropLast(4)) : label
        if let dashIdx = base.lastIndex(of: "-") {
            let suffix = String(base[base.index(after: dashIdx)...])
            if let n = Int(suffix) { return n }
        }
        return Int.max
    }

    func rebuildMerge(for itemId: String, itemName: String) {
        // Sort by label index first (preserves chunk order for split files),
        // then fall back to createdAt for entries that share the same index.
        let regular = entries
            .filter { $0.itemId == itemId && !$0.isMerge }
            .sorted {
                let ia = Self.labelSortIndex($0.label)
                let ib = Self.labelSortIndex($1.label)
                return ia != ib ? ia < ib : $0.createdAt < $1.createdAt
            }

        // Remove existing merge entry
        entries.removeAll { $0.itemId == itemId && $0.isMerge }

        guard !regular.isEmpty else { persist(); return }

        let mergedText = regular.map { $0.text }.joined(separator: "\n")
        let mergeEntry = LocalTranscriptEntry(
            id: "merge-\(itemId)",
            itemId: itemId,
            label: "Merge-\(itemName)",
            text: mergedText,
            durationSeconds: nil,
            createdAt: Date(),
            isMerge: true
        )
        entries.append(mergeEntry)
        persist()
    }

    func deleteAll(for itemId: String) { entries.removeAll { $0.itemId == itemId }; persist() }

    func clearAll() { entries.removeAll(); persist() }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([LocalTranscriptEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        queue.async { [url = storeURL] in try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Local Note Store

struct LocalNoteEntry: Codable, Identifiable {
    let id: String
    let itemId: String
    let label: String
    let text: String
    let promptType: String
    let createdAt: Date

    var summary: NoteSummary { NoteSummary(id: id, label: label, text: text, promptType: promptType) }
}

final class LocalNoteStore {
    static let shared = LocalNoteStore()
    private let storeURL: URL
    private let queue = DispatchQueue(label: "com.scrivano.notestore", qos: .utility)
    private(set) var entries: [LocalNoteEntry] = []

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = docs.appendingPathComponent("notes_manifest.json")
        load()
    }

    func add(_ entry: LocalNoteEntry) { entries.append(entry); persist() }

    /// Replaces an existing note with the same label+itemId, or appends if none exists.
    func addOrReplace(_ entry: LocalNoteEntry) {
        if let idx = entries.firstIndex(where: { $0.itemId == entry.itemId && $0.label == entry.label }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        persist()
    }

    func notes(for itemId: String) -> [LocalNoteEntry] {
        entries.filter { $0.itemId == itemId }.sorted { $0.createdAt > $1.createdAt }
    }

    func count(for itemId: String) -> Int { entries.filter { $0.itemId == itemId }.count }

    func delete(id: String) { entries.removeAll { $0.id == id }; persist() }

    func update(_ entry: LocalNoteEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) { entries[idx] = entry; persist() }
    }

    func deleteAll(for itemId: String) { entries.removeAll { $0.itemId == itemId }; persist() }

    func clearAll() { entries.removeAll(); persist() }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([LocalNoteEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        queue.async { [url = storeURL] in try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Trash Store

enum TrashKind: String, Codable {
    case collection, item, transcript, note, recording
}

struct TrashEntry: Codable, Identifiable {
    let id: String
    let kind: TrashKind
    let name: String
    let parentName: String?   // collection name for items; item name for transcripts/notes
    let deletedAt: Date
    let payload: Data         // JSON-encoded original entity
}

final class TrashStore {
    static let shared = TrashStore()
    private let storeURL: URL
    private let queue = DispatchQueue(label: "com.scrivano.trashstore", qos: .utility)
    private(set) var entries: [TrashEntry] = []

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = docs.appendingPathComponent("trash_manifest.json")
        load()
    }

    var count: Int { entries.count }

    // MARK: - Move to trash

    func trashCollection(_ c: ScrivanoCollection) {
        guard let data = try? JSONEncoder().encode(c) else { return }
        entries.append(TrashEntry(id: UUID().uuidString, kind: .collection, name: c.name,
                                  parentName: nil, deletedAt: Date(), payload: data))
        persist()
    }

    func trashItem(_ item: LocalStoredItem) {
        guard let data = try? JSONEncoder().encode(item) else { return }
        entries.append(TrashEntry(id: UUID().uuidString, kind: .item, name: item.name,
                                  parentName: item.collection, deletedAt: Date(), payload: data))
        persist()
    }

    func trashTranscript(_ t: LocalTranscriptEntry, itemName: String) {
        guard let data = try? JSONEncoder().encode(t) else { return }
        entries.append(TrashEntry(id: UUID().uuidString, kind: .transcript, name: t.label,
                                  parentName: itemName, deletedAt: Date(), payload: data))
        persist()
    }

    func trashNote(_ n: LocalNoteEntry, itemName: String) {
        guard let data = try? JSONEncoder().encode(n) else { return }
        entries.append(TrashEntry(id: UUID().uuidString, kind: .note, name: n.label,
                                  parentName: itemName, deletedAt: Date(), payload: data))
        persist()
    }

    func trashRecording(_ rec: LocalRecordingEntry, itemName: String) {
        guard let data = try? JSONEncoder().encode(rec) else { return }
        let displayName = rec.label ?? rec.relativePath.components(separatedBy: "/").last ?? rec.id
        entries.append(TrashEntry(id: UUID().uuidString, kind: .recording, name: displayName,
                                  parentName: itemName, deletedAt: Date(), payload: data))
        // Remove from manifest only — file stays on disk until permanently deleted
        LocalRecordingStore.shared.delete(id: rec.id)
        persist()
    }

    static let didRestoreNotification = Notification.Name("TrashStore.didRestore")

    // MARK: - Restore

    func restore(_ entry: TrashEntry) {
        switch entry.kind {
        case .collection:
            if let c = try? JSONDecoder().decode(ScrivanoCollection.self, from: entry.payload) {
                LocalCollectionStore.shared.save(c)
            }
        case .item:
            if let item = try? JSONDecoder().decode(LocalStoredItem.self, from: entry.payload) {
                LocalItemStore.shared.save(item)
            }
        case .transcript:
            if let t = try? JSONDecoder().decode(LocalTranscriptEntry.self, from: entry.payload) {
                LocalTranscriptStore.shared.add(t)
            }
        case .note:
            if let n = try? JSONDecoder().decode(LocalNoteEntry.self, from: entry.payload) {
                LocalNoteStore.shared.add(n)
            }
        case .recording:
            if let rec = try? JSONDecoder().decode(LocalRecordingEntry.self, from: entry.payload),
               FileManager.default.fileExists(atPath: rec.fileURL.path) {
                LocalRecordingStore.shared.add(rec)
            }
        }
        entries.removeAll { $0.id == entry.id }
        persist()
        NotificationCenter.default.post(name: TrashStore.didRestoreNotification, object: nil)
    }

    // MARK: - Restore item with collection override

    /// Restores a trashed item, optionally overriding its collectionId (e.g. "My Collection" = nil).
    func restoreItem(_ entry: TrashEntry, toCollectionId: String?, collectionName: String?) {
        guard entry.kind == .item,
              let item = try? JSONDecoder().decode(LocalStoredItem.self, from: entry.payload) else { return }
        let patched = LocalStoredItem(id: item.id, name: item.name,
                                      collection: collectionName,
                                      collectionId: toCollectionId,
                                      createdAt: item.createdAt)
        LocalItemStore.shared.save(patched)
        entries.removeAll { $0.id == entry.id }
        persist()
        NotificationCenter.default.post(name: TrashStore.didRestoreNotification, object: nil)
    }

    // MARK: - Permanent delete

    func permanentlyDelete(_ id: String) {
        if let entry = entries.first(where: { $0.id == id }),
           entry.kind == .recording,
           let rec = try? JSONDecoder().decode(LocalRecordingEntry.self, from: entry.payload) {
            LocalRecordingStore.shared.deleteFile(at: rec.fileURL)
        }
        entries.removeAll { $0.id == id }
        persist()
    }

    func empty() {
        for entry in entries where entry.kind == .recording {
            if let rec = try? JSONDecoder().decode(LocalRecordingEntry.self, from: entry.payload) {
                LocalRecordingStore.shared.deleteFile(at: rec.fileURL)
            }
        }
        entries.removeAll()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([TrashEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        queue.async { [url = storeURL] in try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Pending Task Store

struct PendingTaskEntry: Codable {
    let taskId: String
    let itemId: String
    let itemName: String
    let label: String
    let recordingId: String
    let uploadedAt: Date
}

final class PendingTaskStore {
    static let shared = PendingTaskStore()
    private let storeURL: URL
    private let queue = DispatchQueue(label: "com.scrivano.pendingtasks", qos: .utility)
    private(set) var entries: [PendingTaskEntry] = []

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = docs.appendingPathComponent("pending_tasks.json")
        load()
        pruneStale()
    }

    func add(_ entry: PendingTaskEntry) {
        entries.removeAll { $0.taskId == entry.taskId }
        entries.append(entry)
        persist()
    }

    func remove(taskId: String) {
        entries.removeAll { $0.taskId == taskId }
        persist()
    }

    func clearAll() {
        entries.removeAll()
        persist()
    }

    func all() -> [PendingTaskEntry] { entries }

    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-86400)
        entries.removeAll { $0.uploadedAt < cutoff }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([PendingTaskEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        queue.async { [url = storeURL] in try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Local Image Store
struct LocalImageEntry: Codable, Identifiable, Equatable {
    let id: String
    let itemId: String
    var name: String
    var localPath: String?
    let createdAt: Date

    /// Always resolves against the current Documents directory, ignoring any
    /// stale container UUID embedded in the stored absolute path.
    var resolvedFileURL: URL? {
        guard let stored = localPath else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Extract the relative part starting from "images/" — the rest is stable
        if let range = stored.range(of: "/images/") {
            let relative = String(stored[range.lowerBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return docs.appendingPathComponent(relative)
        }
        // Fallback: stored path was already relative or in an unexpected format
        return URL(fileURLWithPath: stored)
    }
}

final class LocalImageStore {
    static let shared = LocalImageStore()
    private var entries: [LocalImageEntry] = []
    private let manifestURL: URL
    private let queue = DispatchQueue(label: "com.scrivano.imagestore", qos: .utility)

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        manifestURL = docs.appendingPathComponent("images_manifest.json")
        load()
    }

    func add(_ entry: LocalImageEntry) { entries.append(entry); persist() }

    func update(_ entry: LocalImageEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry; persist()
        }
    }

    func delete(id: String) { entries.removeAll { $0.id == id }; persist() }

    func images(for itemId: String) -> [LocalImageEntry] {
        entries.filter { $0.itemId == itemId }.sorted { $0.createdAt < $1.createdAt }
    }

    func count(for itemId: String) -> Int {
        entries.filter { $0.itemId == itemId }.count
    }

    func clearAll() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        entries.removeAll()
        persist()
        queue.async {
            let dir = docs.appendingPathComponent("images")
            try? FileManager.default.removeItem(at: dir)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([LocalImageEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        queue.async { [url = manifestURL] in try? data.write(to: url, options: .atomic) }
    }
}
