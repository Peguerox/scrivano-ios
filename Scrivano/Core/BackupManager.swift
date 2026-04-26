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

        // Clean up orphaned recording entries before snapshotting
        LocalRecordingStore.shared.purgeOrphaned()

        // Snapshot all in-memory stores (main actor)
        let collections = LocalCollectionStore.shared.all()
        let knownCollectionIds = Set(collections.map { $0.id })
        let items = LocalItemStore.shared.all().filter { item in
            item.collectionId == nil || knownCollectionIds.contains(item.collectionId!)
        }
        let itemIds = Set(items.map { $0.id })
        let transcripts = LocalTranscriptStore.shared.entries.filter { itemIds.contains($0.itemId) }
        let notes       = LocalNoteStore.shared.entries.filter { itemIds.contains($0.itemId) }
        let recsMeta    = LocalRecordingStore.shared.entries.filter {
            itemIds.contains($0.itemId) && FileManager.default.fileExists(atPath: $0.fileURL.path)
        }

        progress = "Creating backup…"
        let audioPaths = recsMeta.map { $0.relativePath }
        let pkg = BackupPackage(
            version: 4,
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

        // V4: stream audio files one at a time to avoid loading everything into memory.
        // Layout: [4 magic]["SCV4"][8 encMetaLen][encryptedMeta][per-audio: [4 pathLen][path][8 encAudioLen][encAudio]]
        let backupManager = self
        let dest = try await Task.detached(priority: .userInitiated) {
            // 1. Encrypt JSON metadata only (small — safe to hold in memory)
            var jsonArchive = Data()
            var jsonLen = UInt32(jsonData.count).littleEndian
            jsonArchive.append(Data(bytes: &jsonLen, count: 4))
            jsonArchive.append(jsonData)
            guard let compressed = try? (jsonArchive as NSData).compressed(using: .zlib) as Data
            else { throw BackupError.encodingFailed }
            let encryptedMeta = try BackupManager.encryptData(compressed, password: password)

            // 2. Open output file and write header
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let name = "scrivano-\(df.string(from: Date())).scrivano"
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: dest.path, contents: nil)
            let handle = try FileHandle(forWritingTo: dest)
            defer { try? handle.close() }

            try handle.write(contentsOf: Data("SCV4".utf8))
            var metaLen = UInt64(encryptedMeta.count).littleEndian
            try handle.write(contentsOf: Data(bytes: &metaLen, count: 8))
            try handle.write(contentsOf: encryptedMeta)

            // 3. Stream each audio file — compress, encrypt, write, release
            if includeAudio {
                let total = recsMeta.count
                for (index, rec) in recsMeta.enumerated() {
                    let msg = "Backing up audio \(index + 1)/\(total)…"
                    await MainActor.run { [weak backupManager] in backupManager?.progress = msg }

                    guard let audioData = try? Data(contentsOf: rec.fileURL) else { continue }
                    let pathBytes = Data(rec.relativePath.utf8)
                    let encryptedAudio = try BackupManager.encryptData(audioData, password: password)
                    var pathLen = UInt32(pathBytes.count).littleEndian
                    var audioLen = UInt64(encryptedAudio.count).littleEndian
                    try handle.write(contentsOf: Data(bytes: &pathLen, count: 4))
                    try handle.write(contentsOf: pathBytes)
                    try handle.write(contentsOf: Data(bytes: &audioLen, count: 8))
                    try handle.write(contentsOf: encryptedAudio)
                }
            }

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

        // Detect v4 by magic header — v3 and earlier start with a random AES-GCM nonce
        let header = (try? FileHandle(forReadingFrom: url))?.readData(ofLength: 4) ?? Data()
        if header == Data("SCV4".utf8) {
            return try await restoreV4(from: url, password: password)
        }

        // ── V3 and earlier path ──────────────────────────────────────────
        let encrypted = try Data(contentsOf: url)
        let compressed: Data
        do {
            compressed = try Self.decryptData(encrypted, password: password)
        } catch {
            throw BackupError.wrongPassword
        }
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

        guard archive.count >= 4 else { throw BackupError.invalidFile }
        let jsonLen = Int(Self.readLE(UInt32.self, from: archive, at: archive.startIndex))
        guard archive.count >= 4 + jsonLen else { throw BackupError.invalidFile }
        let jsonData = archive[archive.startIndex + 4 ..< archive.startIndex + 4 + jsonLen]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let pkg = try? decoder.decode(BackupPackage.self, from: jsonData)
        else { throw BackupError.invalidFile }

        var audioMap: [String: Data] = [:]
        if pkg.version >= 2 {
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
            for entry in pkg.audioFiles ?? [] {
                audioMap[entry.relativePath] = entry.data
            }
        }

        return try await applyRestoredPackage(pkg: pkg, audioMap: audioMap)
    }

    // MARK: - V4 restore (streaming — no full-file load into memory)

    private func restoreV4(from url: URL, password: String) async throws -> Int {
        // Phase 1: read + decrypt metadata off the main thread
        progress = "Decrypting backup…"
        let (pkg, audioOffset) = try await Task.detached(priority: .userInitiated) { () throws -> (BackupPackage, UInt64) in
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            try handle.seek(toOffset: 4) // skip magic

            guard let metaLenData = try? handle.read(upToCount: 8), metaLenData.count == 8
            else { throw BackupError.invalidFile }
            let metaLen = Int(BackupManager.readLE(UInt64.self, from: metaLenData, at: metaLenData.startIndex))
            guard let encryptedMeta = try? handle.read(upToCount: metaLen), encryptedMeta.count == metaLen
            else { throw BackupError.invalidFile }

            let compressed: Data
            do { compressed = try BackupManager.decryptData(encryptedMeta, password: password) }
            catch { throw BackupError.wrongPassword }

            guard let archive = try? (compressed as NSData).decompressed(using: .zlib) as Data
            else { throw BackupError.invalidFile }

            guard archive.count >= 4 else { throw BackupError.invalidFile }
            let jsonLen = Int(BackupManager.readLE(UInt32.self, from: archive, at: archive.startIndex))
            guard archive.count >= 4 + jsonLen else { throw BackupError.invalidFile }
            let jsonData = archive[archive.startIndex + 4 ..< archive.startIndex + 4 + jsonLen]

            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            guard let pkg = try? decoder.decode(BackupPackage.self, from: jsonData)
            else { throw BackupError.invalidFile }

            let audioOffset = UInt64(4 + 8 + metaLen) // magic + metaLen field + meta blob
            return (pkg, audioOffset)
        }.value

        // Phase 2: restore metadata on main actor (store writes require main actor)
        let (_, itemIdMap) = try await applyMetadata(pkg: pkg)

        // Phase 3: stream audio files off the main thread, post progress back to main actor
        let totalAudio = pkg.audioFilePaths.count
        progress = totalAudio > 0 ? "Restoring audio 0/\(totalAudio)…" : "Restoring audio files…"

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let itemIdMapCopy = itemIdMap
        let recsMeta = pkg.recordingsMeta

        let restoredEntries: [LocalRecordingEntry] = try await Task.detached(priority: .userInitiated) { () throws -> [LocalRecordingEntry] in
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: audioOffset)

            var entries: [LocalRecordingEntry] = []
            var count = 0

            while true {
                guard let pathLenData = try? handle.read(upToCount: 4), pathLenData.count == 4 else { break }
                let pathLen = Int(BackupManager.readLE(UInt32.self, from: pathLenData, at: pathLenData.startIndex))
                guard let pathData = try? handle.read(upToCount: pathLen), pathData.count == pathLen else { break }
                guard let relativePath = String(data: pathData, encoding: .utf8) else { break }

                guard let audioLenData = try? handle.read(upToCount: 8), audioLenData.count == 8 else { break }
                let audioLen = Int(BackupManager.readLE(UInt64.self, from: audioLenData, at: audioLenData.startIndex))
                guard let encryptedAudio = try? handle.read(upToCount: audioLen), encryptedAudio.count == audioLen else { break }

                guard let audioData = try? BackupManager.decryptData(encryptedAudio, password: password) else { continue }

                let parts = relativePath.components(separatedBy: "/")
                guard parts.count >= 3, parts[0] == "recordings" else { continue }
                let oldItemId = parts[1]
                guard let newItemId = itemIdMapCopy[oldItemId] else { continue }
                let filename = parts[2...].joined(separator: "/")

                let dir = docs.appendingPathComponent("recordings/\(newItemId)")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? audioData.write(to: dir.appendingPathComponent(filename), options: .atomic)

                if let meta = recsMeta.first(where: { $0.itemId == oldItemId && $0.relativePath == relativePath }) {
                    entries.append(LocalRecordingEntry(
                        id: UUID().uuidString,
                        itemId: newItemId,
                        relativePath: "recordings/\(newItemId)/\(filename)",
                        createdAt: meta.createdAt,
                        durationSeconds: meta.durationSeconds,
                        label: meta.label
                    ))
                }

                count += 1
                if totalAudio > 0 {
                    let msg = "Restoring audio \(count)/\(totalAudio)…"
                    await MainActor.run { [weak self] in self?.progress = msg }
                }
            }
            return entries
        }.value

        // Phase 4: persist recording entries + finalize on main actor
        LocalRecordingStore.shared.addBatch(restoredEntries)

        progress = "Finalizing…"
        for item in pkg.items {
            if let newId = itemIdMap[item.id] {
                LocalTranscriptStore.shared.rebuildMerge(for: newId, itemName: item.name)
            }
        }

        NotificationCenter.default.post(name: .scrivanoBackupRestored, object: nil)
        return pkg.collections.count
    }

    // MARK: - Shared restore helpers

    /// Restores collections, items, transcripts and notes from a package. Returns (collectionIdMap, itemIdMap).
    @discardableResult
    private func applyMetadata(pkg: BackupPackage) async throws -> ([String: String], [String: String]) {
        progress = "Restoring collections…"
        var collectionIdMap: [String: String] = [:]
        var usedNames = Set(LocalCollectionStore.shared.all().map { $0.name })
        for col in pkg.collections {
            let newId = UUID().uuidString
            collectionIdMap[col.id] = newId
            var name = col.name
            if usedNames.contains(name) {
                var n = 1; while usedNames.contains("\(col.name) \(n)") { n += 1 }
                name = "\(col.name) \(n)"
            }
            usedNames.insert(name)
            LocalCollectionStore.shared.save(ScrivanoCollection(id: newId, name: name))
        }

        progress = "Restoring items…"
        var itemIdMap: [String: String] = [:]
        for item in pkg.items {
            let newId = UUID().uuidString
            itemIdMap[item.id] = newId
            let newColId = item.collectionId.flatMap { collectionIdMap[$0] }
            let newColName = newColId.flatMap { cid in LocalCollectionStore.shared.all().first(where: { $0.id == cid })?.name }
            LocalItemStore.shared.save(LocalStoredItem(
                id: newId, name: item.name, collection: newColName,
                collectionId: newColId, createdAt: item.createdAt
            ))
        }

        progress = "Restoring transcripts…"
        let transcriptBatch: [LocalTranscriptEntry] = pkg.transcripts.compactMap { t in
            guard !t.isMerge else { return nil }
            let newItemId = itemIdMap[t.itemId] ?? t.itemId
            return LocalTranscriptEntry(id: UUID().uuidString, itemId: newItemId, label: t.label,
                                        text: t.text, durationSeconds: t.durationSeconds, createdAt: t.createdAt)
        }
        LocalTranscriptStore.shared.addBatch(transcriptBatch)

        progress = "Restoring notes…"
        let notesBatch: [LocalNoteEntry] = pkg.notes.map { n in
            let newItemId = itemIdMap[n.itemId] ?? n.itemId
            return LocalNoteEntry(id: UUID().uuidString, itemId: newItemId, label: n.label,
                                  text: n.text, promptType: n.promptType, createdAt: n.createdAt)
        }
        LocalNoteStore.shared.addBatch(notesBatch)

        return (collectionIdMap, itemIdMap)
    }

    /// Used by the v3 restore path — applies a fully-loaded audioMap after metadata is restored.
    private func applyRestoredPackage(pkg: BackupPackage, audioMap: [String: Data]) async throws -> Int {
        let (_, itemIdMap) = try await applyMetadata(pkg: pkg)

        progress = "Restoring audio files…"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for (relativePath, audioData) in audioMap {
            let parts = relativePath.components(separatedBy: "/")
            guard parts.count >= 3, parts[0] == "recordings" else { continue }
            let oldItemId = parts[1]
            guard let newItemId = itemIdMap[oldItemId] else { continue }
            let filename = parts[2...].joined(separator: "/")
            let dir = docs.appendingPathComponent("recordings/\(newItemId)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? audioData.write(to: dir.appendingPathComponent(filename), options: .atomic)
            if let meta = pkg.recordingsMeta.first(where: {
                $0.itemId == oldItemId && $0.relativePath == relativePath
            }) {
                LocalRecordingStore.shared.add(LocalRecordingEntry(
                    id: UUID().uuidString, itemId: newItemId,
                    relativePath: "recordings/\(newItemId)/\(filename)",
                    createdAt: meta.createdAt, durationSeconds: meta.durationSeconds, label: meta.label
                ))
            }
        }

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
    nonisolated static func readLE<T: FixedWidthInteger>(_ type: T.Type, from data: Data, at index: Data.Index) -> T {
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
