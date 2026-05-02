import Foundation
import AVFoundation

final class PendingImportProcessor {
    static let shared = PendingImportProcessor()
    private init() {}

    private var isProcessing = false

    func process() {
        guard !isProcessing else { return }
        guard let container = AppGroup.containerURL else { return }
        let pendingDir  = container.appendingPathComponent("pending_imports")
        let manifestURL = pendingDir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([PendingImport].self, from: data),
              !entries.isEmpty else { return }

        isProcessing = true
        Task {
            defer { isProcessing = false }
            var remaining = entries
            for entry in entries {
                let fileURL = container.appendingPathComponent(entry.fileRelativePath)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    remaining.removeAll { $0.id == entry.id }
                    continue
                }
                let ok = await processEntry(entry, fileURL: fileURL)
                if ok { remaining.removeAll { $0.id == entry.id } }
            }
            // Write back survivors (failed entries stay for retry)
            if let updated = try? JSONEncoder().encode(remaining) {
                try? updated.write(to: manifestURL, options: .atomic)
            }
            // Re-mirror stores so extension sees any new collections/items
            AppGroup.mirrorCollections()
            AppGroup.mirrorItems()
        }
    }

    private func processEntry(_ entry: PendingImport, fileURL: URL) async -> Bool {
        // Find or create collection
        let collection: ScrivanoCollection
        if let existing = LocalCollectionStore.shared.collections.first(where: { $0.id == entry.collectionId }) {
            collection = existing
        } else {
            let new = ScrivanoCollection(id: entry.collectionId, name: entry.collectionName)
            LocalCollectionStore.shared.save(new)
            collection = new
        }

        // Find or create item
        let item: LocalStoredItem
        if let existing = LocalItemStore.shared.items.first(where: { $0.id == entry.itemId }) {
            item = existing
        } else {
            let new = LocalStoredItem(
                id: entry.itemId,
                name: entry.itemName,
                collection: collection.name,
                collectionId: collection.id,
                createdAt: ISO8601DateFormatter().string(from: entry.importedAt)
            )
            LocalItemStore.shared.save(new)
            item = new
        }

        if entry.isAudio {
            return await importAudio(fileURL: fileURL, item: item, entry: entry)
        } else {
            return await importDocument(fileURL: fileURL, item: item, entry: entry)
        }
    }

    private func importAudio(fileURL: URL, item: LocalStoredItem, entry: PendingImport) async -> Bool {
        let ext  = entry.fileExtension.isEmpty ? "m4a" : entry.fileExtension
        let dest = LocalRecordingStore.newFileURL(itemId: item.id, ext: ext)
        do {
            try FileManager.default.copyItem(at: fileURL, to: dest)
        } catch { return false }

        let asset    = AVURLAsset(url: dest)
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0

        let recording = LocalRecordingEntry(
            id: UUID().uuidString,
            itemId: item.id,
            relativePath: LocalRecordingStore.relativePath(of: dest),
            createdAt: Date(),
            durationSeconds: duration,
            label: fileURL.lastPathComponent
        )
        LocalRecordingStore.shared.add(recording)
        try? FileManager.default.removeItem(at: fileURL)
        return true
    }

    private func importDocument(fileURL: URL, item: LocalStoredItem, entry: PendingImport) async -> Bool {
        do {
            let text = try await APIClient.shared.uploadDocument(fileURL: fileURL)
            let label = fileURL.deletingPathExtension().lastPathComponent
            let transcript = LocalTranscriptEntry(
                id: UUID().uuidString,
                itemId: item.id,
                label: label,
                text: text,
                durationSeconds: nil,
                createdAt: Date()
            )
            LocalTranscriptStore.shared.add(transcript)
            LocalTranscriptStore.shared.rebuildMerge(for: item.id, itemName: item.name)
            try? FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }
}
