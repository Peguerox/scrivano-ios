import Foundation
import CryptoKit

// MARK: - Backup Package

struct BackupPackage: Codable {
    var version: Int = 2
    let createdAt: Date
    let appVersion: String
    let collections: [ScrivanoCollection]
    let items: [LocalStoredItem]
    let transcripts: [LocalTranscriptEntry]
    let notes: [LocalNoteEntry]
    let recordingsMeta: [LocalRecordingEntry]
    // v2+: audio file paths only — raw bytes follow the JSON in the binary archive
    let audioFilePaths: [String]
    // v1 legacy: audio was embedded as base64 in JSON; nil in v2+
    let audioFiles: [AudioEntry]?

    struct AudioEntry: Codable {
        let relativePath: String
        let data: Data
    }
}

// MARK: - Errors

enum BackupError: LocalizedError {
    case wrongPassword
    case invalidFile
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .wrongPassword:  return "Wrong password — please try again."
        case .invalidFile:    return "This file is not a valid Scrivano backup."
        case .encodingFailed: return "Failed to process the backup file."
        }
    }
}

// MARK: - BackupManager

@MainActor
final class BackupManager: ObservableObject {
    static let shared = BackupManager()

    @Published var isWorking = false
    @Published var progress = ""

    private init() {}

    // MARK: - Create Backup

    func createBackup(password: String, includeAudio: Bool = true) async throws -> URL {
        isWorking = true
        progress = "Gathering data…"
        defer { isWorking = false; progress = "" }

        // Snapshot all in-memory stores (main actor)
        let collections = LocalCollectionStore.shared.all()
        let knownCollectionIds = Set(collections.map { $0.id })
        let items = LocalItemStore.shared.all().filter { item in
            item.collectionId == nil || knownCollectionIds.contains(item.collectionId!)
        }
        let transcripts = LocalTranscriptStore.shared.entries
        let notes       = LocalNoteStore.shared.entries
        let recsMeta    = LocalRecordingStore.shared.entries

        progress = "Creating backup…"
        let audioPaths = recsMeta.map { $0.relativePath }
        let pkg = BackupPackage(
            createdAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            collections: collections,
            items: items,
            transcripts: transcripts,
            notes: notes,
            recordingsMeta: recsMeta,
            audioFilePaths: audioPaths,
            audioFiles: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(pkg) else { throw BackupError.encodingFailed }

        // Run heavy I/O and CPU work off the main thread so the spinner stays visible
        let dest = try await Task.detached(priority: .userInitiated) {
            // Build binary archive: [UInt32 jsonLen][json][repeated: UInt32 pathLen][pathUTF8][UInt64 dataLen][rawAudio]
            var archive = Data()
            var jsonLen = UInt32(jsonData.count).littleEndian
            archive.append(Data(bytes: &jsonLen, count: 4))
            archive.append(jsonData)

            if includeAudio {
                for rec in recsMeta {
                    guard let audioData = try? Data(contentsOf: rec.fileURL) else { continue }
                    let pathBytes = Data(rec.relativePath.utf8)
                    var pathLen = UInt32(pathBytes.count).littleEndian
                    var dataLen = UInt64(audioData.count).littleEndian
                    archive.append(Data(bytes: &pathLen, count: 4))
                    archive.append(pathBytes)
                    archive.append(Data(bytes: &dataLen, count: 8))
                    archive.append(audioData)
                }
            }

            guard let compressed = try? (archive as NSData).compressed(using: .lzfse) as Data
            else { throw BackupError.encodingFailed }
            let encrypted = try BackupManager.encryptData(compressed, password: password)

            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let name = "scrivano-\(df.string(from: Date())).scrivano"
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try encrypted.write(to: dest, options: .atomic)
            return dest
        }.value

        return dest
    }

    // MARK: - Restore Backup

    /// Returns number of collections restored.
    func restoreBackup(from url: URL, password: String) async throws -> Int {
        isWorking = true
        progress = "Decrypting…"
        defer { isWorking = false; progress = "" }

        let encrypted = try Data(contentsOf: url)
        let compressed: Data
        do {
            compressed = try Self.decryptData(encrypted, password: password)
        } catch {
            throw BackupError.wrongPassword
        }
        guard let archive = try? (compressed as NSData).decompressed(using: .lzfse) as Data
        else { throw BackupError.invalidFile }

        // Parse archive: [UInt32 jsonLen][json][audio segments...]
        guard archive.count >= 4 else { throw BackupError.invalidFile }
        let jsonLen = Int(UInt32(littleEndian: archive[0..<4].withUnsafeBytes { $0.load(as: UInt32.self) }))
        guard archive.count >= 4 + jsonLen else { throw BackupError.invalidFile }
        let jsonData = archive[4 ..< 4 + jsonLen]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let pkg = try? decoder.decode(BackupPackage.self, from: jsonData)
        else { throw BackupError.invalidFile }

        // Load audio into a path→data map
        var audioMap: [String: Data] = [:]
        if pkg.version >= 2 {
            // Binary segments follow the JSON block
            var cursor = 4 + jsonLen
            while cursor + 4 <= archive.count {
                let pathLen = Int(UInt32(littleEndian: archive[cursor ..< cursor + 4].withUnsafeBytes { $0.load(as: UInt32.self) }))
                cursor += 4
                guard cursor + pathLen + 8 <= archive.count else { break }
                let pathData = archive[cursor ..< cursor + pathLen]
                cursor += pathLen
                guard let path = String(data: pathData, encoding: .utf8) else { break }
                let dataLen = Int(UInt64(littleEndian: archive[cursor ..< cursor + 8].withUnsafeBytes { $0.load(as: UInt64.self) }))
                cursor += 8
                guard cursor + dataLen <= archive.count else { break }
                audioMap[path] = archive[cursor ..< cursor + dataLen]
                cursor += dataLen
            }
        } else {
            // v1: audio was embedded as base64 in the JSON
            for entry in pkg.audioFiles ?? [] {
                audioMap[entry.relativePath] = entry.data
            }
        }

        progress = "Restoring collections…"

        // ── Collections ─────────────────────────────────────────────────
        var collectionIdMap: [String: String] = [:]
        var usedNames = Set(LocalCollectionStore.shared.all().map { $0.name })

        for col in pkg.collections {
            let newId = UUID().uuidString
            collectionIdMap[col.id] = newId
            var name = col.name
            if usedNames.contains(name) {
                var n = 1
                while usedNames.contains("\(col.name) \(n)") { n += 1 }
                name = "\(col.name) \(n)"
            }
            usedNames.insert(name)
            LocalCollectionStore.shared.save(ScrivanoCollection(id: newId, name: name))
        }

        // ── Items ────────────────────────────────────────────────────────
        progress = "Restoring items…"
        var itemIdMap: [String: String] = [:]

        for item in pkg.items {
            let newId = UUID().uuidString
            itemIdMap[item.id] = newId
            let newColId = item.collectionId.flatMap { collectionIdMap[$0] }
            let newColName: String?
            if let cid = newColId {
                newColName = LocalCollectionStore.shared.all().first(where: { $0.id == cid })?.name
            } else {
                newColName = nil
            }
            LocalItemStore.shared.save(LocalStoredItem(
                id: newId,
                name: item.name,
                collection: newColName,
                collectionId: newColId,
                createdAt: item.createdAt
            ))
        }

        // ── Transcripts (skip auto-generated merges) ─────────────────────
        progress = "Restoring transcripts…"
        for t in pkg.transcripts where !t.isMerge {
            let newItemId = itemIdMap[t.itemId] ?? t.itemId
            LocalTranscriptStore.shared.add(LocalTranscriptEntry(
                id: UUID().uuidString,
                itemId: newItemId,
                label: t.label,
                text: t.text,
                durationSeconds: t.durationSeconds,
                createdAt: t.createdAt
            ))
        }

        // ── Notes ────────────────────────────────────────────────────────
        progress = "Restoring notes…"
        for n in pkg.notes {
            let newItemId = itemIdMap[n.itemId] ?? n.itemId
            LocalNoteStore.shared.add(LocalNoteEntry(
                id: UUID().uuidString,
                itemId: newItemId,
                label: n.label,
                text: n.text,
                promptType: n.promptType,
                createdAt: n.createdAt
            ))
        }

        // ── Audio files ──────────────────────────────────────────────────
        progress = "Restoring audio files…"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        for (relativePath, audioData) in audioMap {
            // relativePath shape: recordings/{oldItemId}/filename
            let parts = relativePath.components(separatedBy: "/")
            guard parts.count >= 3, parts[0] == "recordings" else { continue }
            let oldItemId = parts[1]
            guard let newItemId = itemIdMap[oldItemId] else { continue }
            let filename = parts[2...].joined(separator: "/")

            let dir = docs.appendingPathComponent("recordings/\(newItemId)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(filename)
            try? audioData.write(to: dest, options: .atomic)

            // Match to recording metadata entry
            if let meta = pkg.recordingsMeta.first(where: {
                $0.itemId == oldItemId && $0.relativePath == relativePath
            }) {
                LocalRecordingStore.shared.add(LocalRecordingEntry(
                    id: UUID().uuidString,
                    itemId: newItemId,
                    relativePath: "recordings/\(newItemId)/\(filename)",
                    createdAt: meta.createdAt,
                    durationSeconds: meta.durationSeconds,
                    label: meta.label
                ))
            }
        }

        // ── Rebuild merge transcripts ────────────────────────────────────
        progress = "Finalizing…"
        for item in pkg.items {
            if let newId = itemIdMap[item.id] {
                LocalTranscriptStore.shared.rebuildMerge(for: newId, itemName: item.name)
            }
        }

        NotificationCenter.default.post(name: .scrivanoBackupRestored, object: nil)
        return pkg.collections.count
    }

    // MARK: - Crypto (static so Task.detached can use them)

    nonisolated static func encryptData(_ data: Data, password: String) throws -> Data {
        let key = derivedKey(from: password)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw BackupError.encodingFailed }
        return combined
    }

    nonisolated static func decryptData(_ data: Data, password: String) throws -> Data {
        let key = derivedKey(from: password)
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    private nonisolated static func derivedKey(from password: String) -> SymmetricKey {
        var raw = Data(password.utf8)
        raw.append(Data("scrivano-backup-salt-v1".utf8))
        return SymmetricKey(data: SHA256.hash(data: raw))
    }
}

// MARK: - Notification

extension Notification.Name {
    static let scrivanoBackupRestored  = Notification.Name("scrivano.backupRestored")
    static let scrivanoOpenBackupFile  = Notification.Name("scrivano.openBackupFile")
}
