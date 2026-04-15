import Foundation
import CryptoKit
import Compression

// MARK: - Backup Package

struct BackupPackage: Codable {
    var version: Int = 3
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

            guard let compressed = try? (archive as NSData).compressed(using: .zlib) as Data
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
        // Try each decompressor in order — no magic-byte guessing.
        // Each returns nil on wrong-format data so falling through is safe.
        let archive: Data
        if let d = try? (compressed as NSData).decompressed(using: .zlib) as Data {
            archive = d
        } else if let d = try? Self.gzipDecompress(compressed) {
            archive = d
        } else if let d = try? (compressed as NSData).decompressed(using: .lzfse) as Data {
            archive = d
        } else {
            throw BackupError.invalidFile
        }

        // Parse archive: [UInt32 jsonLen][json][audio segments...]
        guard archive.count >= 4 else { throw BackupError.invalidFile }
        let jsonLen = Int(Self.readLE(UInt32.self, from: archive, at: archive.startIndex))
        guard archive.count >= 4 + jsonLen else { throw BackupError.invalidFile }
        let jsonData = archive[archive.startIndex + 4 ..< archive.startIndex + 4 + jsonLen]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let pkg = try? decoder.decode(BackupPackage.self, from: jsonData)
        else { throw BackupError.invalidFile }

        // Load audio into a path→data map
        var audioMap: [String: Data] = [:]
        if pkg.version >= 2 {
            // Binary segments follow the JSON block
            var cursor = archive.startIndex + 4 + jsonLen
            while cursor + 4 <= archive.endIndex {
                let pathLen = Int(Self.readLE(UInt32.self, from: archive, at: cursor))
                cursor += 4
                guard cursor + pathLen + 8 <= archive.endIndex else { break }
                let pathData = archive[cursor ..< cursor + pathLen]
                cursor += pathLen
                guard let path = String(data: pathData, encoding: .utf8) else { break }
                let dataLen = Int(Self.readLE(UInt64.self, from: archive, at: cursor))
                cursor += 8
                guard cursor + dataLen <= archive.endIndex else { break }
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

    // MARK: - Safe integer reads (alignment-safe)

    /// Reads a little-endian integer from `data` at the given index without
    /// assuming pointer alignment — Data sub-slices are not guaranteed to be aligned.
    nonisolated private static func readLE<T: FixedWidthInteger>(_ type: T.Type, from data: Data, at index: Data.Index) -> T {
        var value = T.zero
        withUnsafeMutableBytes(of: &value) { dest in
            _ = data.copyBytes(to: dest, from: index ..< index + MemoryLayout<T>.size)
        }
        return T(littleEndian: value)
    }

    // MARK: - gzip (RFC 1952) helpers

    /// Compress using gzip (RFC 1952): 10-byte header + raw DEFLATE + CRC32 + ISIZE.
    /// Uses NSData.compressed(.zlib) to get zlib-wrapped deflate, strips the 2-byte zlib
    /// header and 4-byte Adler32 trailer, then wraps in a proper gzip envelope.
    nonisolated static func gzipCompress(_ data: Data) throws -> Data {
        guard let zlibData = try? (data as NSData).compressed(using: .zlib) as Data,
              zlibData.count >= 6
        else { throw BackupError.encodingFailed }

        // zlib format: [CMF][FLG][raw DEFLATE][Adler32 4 bytes]
        let rawDeflate = zlibData[2 ..< zlibData.count - 4]

        // gzip fixed 10-byte header
        // ID1=0x1f ID2=0x8b CM=8(deflate) FLG=0 MTIME=0(4B) XFL=0 OS=255(unknown)
        var gzip = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff])
        gzip.append(rawDeflate)

        var crc = crc32Checksum(data)
        gzip.append(Data(bytes: &crc, count: 4))           // CRC32 LE
        var isize = UInt32(data.count & 0xffff_ffff).littleEndian
        gzip.append(Data(bytes: &isize, count: 4))         // ISIZE LE (mod 2^32)

        return gzip
    }

    /// Decompress gzip (RFC 1952) data. Parses the header, extracts raw DEFLATE,
    /// prepends a valid zlib header, then decompresses using compression_stream
    /// WITHOUT COMPRESSION_STREAM_FINALIZE. This bypasses the Adler32 check:
    /// after processing the last DEFLATE block the stream waits for the Adler32
    /// but returns COMPRESSION_STATUS_OK (needs more input) rather than an error,
    /// and the decompressed bytes are already in the output buffer.
    nonisolated static func gzipDecompress(_ data: Data) throws -> Data {
        guard data.count >= 18,
              data[0] == 0x1f, data[1] == 0x8b,
              data[2] == 8                               // CM must be 8 (deflate)
        else { throw BackupError.invalidFile }

        let flg = data[3]
        var offset = 10                                   // skip fixed 10-byte header

        if flg & 0x04 != 0 {                              // FEXTRA
            guard offset + 2 <= data.count else { throw BackupError.invalidFile }
            let xlen = Int(Self.readLE(UInt16.self, from: data, at: data.startIndex + offset))
            offset += 2 + xlen
        }
        if flg & 0x08 != 0 {                              // FNAME (null-terminated)
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flg & 0x10 != 0 {                              // FCOMMENT (null-terminated)
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flg & 0x02 != 0 { offset += 2 }               // FHCRC

        guard data.count >= offset + 8 else { throw BackupError.invalidFile }
        let trailerStart = data.endIndex - 8
        let isize = Int(Self.readLE(UInt32.self, from: data, at: trailerStart + 4))

        // Build: [zlib header 0x78 0x9C] + [raw DEFLATE]
        // (0x78*256 + 0x9C) % 31 == 0 — valid zlib CMF/FLG pair
        // We intentionally omit the 4-byte Adler32 trailer so the stream
        // stalls waiting for it (COMPRESSION_STATUS_OK) instead of failing.
        var zlibInput = Data([0x78, 0x9C])
        zlibInput.append(data[offset ..< trailerStart])

        let outSize = max(isize, (data.count - offset) * 4, 65536)
        var dst = [UInt8](repeating: 0, count: outSize)

        // Swift requires non-nil values for the non-optional pointer fields at init time.
        // compression_stream_init only touches `state`; src/dst are overwritten in the closure.
        var dummyDst: UInt8 = 0
        var dummySrc: UInt8 = 0
        var stream = compression_stream(dst_ptr: &dummyDst, dst_size: 0,
                                        src_ptr: &dummySrc, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK
        else { throw BackupError.invalidFile }
        defer { compression_stream_destroy(&stream) }

        // Both input and output pointers must be obtained inside their respective
        // withUnsafe… closures so they remain valid for the duration of the call.
        let written = try dst.withUnsafeMutableBufferPointer { dstBuf throws -> Int in
            try zlibInput.withUnsafeBytes { srcBuf throws -> Int in
                guard let srcPtr = srcBuf.baseAddress,
                      let dstPtr = dstBuf.baseAddress
                else { throw BackupError.invalidFile }
                stream.src_ptr  = srcPtr.assumingMemoryBound(to: UInt8.self)
                stream.src_size = zlibInput.count
                stream.dst_ptr  = dstPtr
                stream.dst_size = outSize
                // No COMPRESSION_STREAM_FINALIZE → Adler32 is never demanded
                let status = compression_stream_process(&stream, 0)
                guard status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END
                else { throw BackupError.invalidFile }
                return outSize - stream.dst_size
            }
        }

        guard written > 0 else { throw BackupError.invalidFile }
        return Data(dst[0 ..< written])
    }

    /// Pure-Swift CRC32 (IEEE 802.3 polynomial).
    nonisolated private static func crc32Checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xff)
            crc = crc32Table[idx] ^ (crc >> 8)
        }
        return (crc ^ 0xffff_ffff).littleEndian
    }

    // Pre-computed CRC32 lookup table (IEEE 802.3 / gzip polynomial 0xEDB88320)
    nonisolated private static let crc32Table: [UInt32] = {
        (0..<256).map { n -> UInt32 in
            var c = UInt32(n)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()
}

// MARK: - Notification

extension Notification.Name {
    static let scrivanoBackupRestored  = Notification.Name("scrivano.backupRestored")
    static let scrivanoOpenBackupFile  = Notification.Name("scrivano.openBackupFile")
}
