import Foundation
import SafariServices
import UIKit

@MainActor
final class IntegrationStore: ObservableObject {
    static let shared = IntegrationStore()

    @Published private(set) var catalog: [IntegrationConfig] = []
    @Published private(set) var installed: [InstalledIntegration] = []
    @Published private(set) var log: [IntegrationLogEntry] = []
    @Published var isLoadingCatalog = false
    @Published var catalogError: String? = nil
    @Published var lastPullWarnings: [String] = []   // non-fatal errors from pull items (e.g. 403 on labs)

    private let installedKey = "integrations.installed.v3"
    private let api = APIClient.shared

    private init() {
        installed = load(key: installedKey) ?? []
    }

    // MARK: - Catalog

    func fetchCatalog() async {
        isLoadingCatalog = true
        catalogError = nil
        do {
            let response = try await api.request(
                path: "/api/integrations",
                method: "GET",
                responseType: IntegrationListResponse.self
            )
            // For catalog display use minimal configs; full config loads on demand
            let configs = response.integrations.map { $0.toMinimalConfig() }
            catalog = configs
            syncInstalledFromCatalog(response.integrations)
        } catch {
            catalogError = error.localizedDescription
        }
        isLoadingCatalog = false
    }

    /// Fetches full config for a single integration and updates catalog + installed entries.
    func fetchDetail(integrationId: String) async throws {
        let detail = try await api.request(
            path: "/api/integrations/\(integrationId)",
            method: "GET",
            responseType: ServerIntegrationDetail.self
        )
        let config = detail.toConfig()
        if let idx = catalog.firstIndex(where: { $0.id == integrationId }) {
            catalog[idx] = config
        } else {
            catalog.append(config)
        }
        if let idx = installed.firstIndex(where: { $0.id == integrationId }) {
            installed[idx].config = config
            let serverState = connectionState(from: detail.status)
            if serverState != .disconnected {
                installed[idx].connectionState = serverState
            }
            save(installed, key: installedKey)
        }
    }

    private func syncInstalledFromCatalog(_ items: [ServerIntegrationListItem]) {
        for item in items where item.installed == true {
            let serverState = connectionState(from: item.status)
            if !installed.contains(where: { $0.id == item.id }) {
                let config = item.toMinimalConfig()
                let integration = InstalledIntegration(id: item.id, config: config,
                                                       connectionState: serverState)
                installed.append(integration)
                save(installed, key: installedKey)
            } else if let idx = installed.firstIndex(where: { $0.id == item.id }) {
                if installed[idx].connectionState != serverState {
                    installed[idx].connectionState = serverState
                    save(installed, key: installedKey)
                }
            }
        }
        // Remove ones the server no longer lists as installed
        let serverInstalledIds = Set(items.filter { $0.installed == true }.map(\.id))
        let before = installed.count
        installed.removeAll { !serverInstalledIds.contains($0.id) }
        if installed.count != before { save(installed, key: installedKey) }
    }

    // MARK: - Install

    /// Installs or reconnects an integration.
    /// - For OAuth2: returns the auth URL to open in Safari.
    /// - For api-key/basic: pass credentials; returns nil (marks connected on success).
    func install(integrationId: String,
                 baseUrl: String? = nil,
                 username: String? = nil,
                 password: String? = nil,
                 apiKey: String? = nil) async throws -> URL? {

        let body = InstallRequest(
            baseUrl: baseUrl?.isEmpty == true ? nil : baseUrl,
            apiKey: apiKey?.isEmpty == true ? nil : apiKey,
            username: username?.isEmpty == true ? nil : username,
            password: password?.isEmpty == true ? nil : password
        )
        let response = try await api.request(
            path: "/api/integrations/\(integrationId)/install",
            method: "POST",
            body: body,
            responseType: InstallResponse.self
        )

        if let config = catalog.first(where: { $0.id == integrationId }) {
            if !installed.contains(where: { $0.id == integrationId }) {
                var integration = InstalledIntegration(id: integrationId, config: config,
                                                       connectionState: .disconnected)
                if let bu = baseUrl, !bu.isEmpty { integration.baseUrl = bu }
                installed.append(integration)
            }
            if let idx = installed.firstIndex(where: { $0.id == integrationId }) {
                if let bu = baseUrl, !bu.isEmpty { installed[idx].baseUrl = bu }
            }
            save(installed, key: installedKey)
        }

        // OAuth2: return the auth URL for Safari
        if let urlStr = response.authUrl, let url = URL(string: urlStr) {
            return url
        }
        // API key / basic: server confirms active immediately
        if response.status == "active" || response.success == true {
            markConnected(integrationId: integrationId, email: username)
        }
        return nil
    }

    // MARK: - Uninstall

    func uninstall(integrationId: String) async throws {
        _ = try? await api.request(
            path: "/api/integrations/\(integrationId)/uninstall",
            method: "DELETE",
            responseType: ActionResponse.self
        )
        installed.removeAll { $0.id == integrationId }
        log.removeAll { $0.integrationId == integrationId }
        save(installed, key: installedKey)
        // Refresh catalog so the uninstalled integration reappears as available
        await fetchCatalog()
    }

    // MARK: - Mark connected (called after OAuth callback deep link)

    func markConnected(integrationId: String, email: String? = nil, org: String? = nil) {
        guard let idx = installed.firstIndex(where: { $0.id == integrationId }) else { return }
        installed[idx].connectionState = .connected
        installed[idx].lastAuthDate = Date()
        if let email { installed[idx].accountEmail = email }
        if let org   { installed[idx].accountOrganization = org }
        save(installed, key: installedKey)
        // Fetch full config now that it's connected
        Task { try? await fetchDetail(integrationId: integrationId) }
    }

    func disconnect(id: String) {
        guard let idx = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[idx].connectionState = .disconnected
        installed[idx].accountEmail = nil
        installed[idx].accountOrganization = nil
        installed[idx].tokenPreview = nil
        installed[idx].tokenExpiry = nil
        installed[idx].tokenScopes = nil
        installed[idx].lastAuthDate = nil
        save(installed, key: installedKey)
    }

    func updateConnection(_ integration: InstalledIntegration) {
        guard let idx = installed.firstIndex(where: { $0.id == integration.id }) else { return }
        installed[idx] = integration
        save(installed, key: installedKey)
    }

    // MARK: - Browse (list dropdown before pull)

    func browse(integrationId: String, entityId: String) async throws -> [BrowseItem] {
        let response = try await api.request(
            path: "/api/integrations/\(integrationId)/browse?entity_id=\(entityId)",
            method: "GET",
            responseType: BrowseResponse.self
        )
        return response.items ?? []
    }

    // MARK: - Pull

    func pull(integrationId: String,
              entityId: String,
              listId: String?,
              entityRecordId: String?,
              content: [String],
              counts: [String: Int]?,
              collectionName: String?) async throws -> PullResponse {

        let body = PullRequest(
            entityId: entityId,
            listId: listId?.isEmpty == true ? nil : listId,
            entityRecordId: entityRecordId?.isEmpty == true ? nil : entityRecordId,
            contentTypes: content,
            counts: counts?.isEmpty == true ? nil : counts,
            collectionName: collectionName?.isEmpty == true ? nil : collectionName
        )
        let response = try await api.request(
            path: "/api/integrations/\(integrationId)/pull",
            method: "POST",
            body: body,
            responseType: PullResponse.self
        )
        let integrationName = installed.first(where: { $0.id == integrationId })?.config.name ?? integrationId
        let itemCount = response.collection?.items?.count ?? 0
        appendLog(IntegrationLogEntry(
            id: UUID().uuidString,
            integrationId: integrationId,
            integrationName: integrationName,
            action: .pull,
            targetLabel: entityId,
            contentLabels: content,
            destinationName: response.collection?.name,
            resultSummary: response.message ?? "\(itemCount) item(s) received",
            status: .success,
            errorMessage: nil,
            date: Date()
        ))
        return response
    }

    // MARK: - Persist pull result (called after user names the collection)

    @discardableResult
    func persistPullResult(_ response: PullResponse,
                           integrationId: String,
                           collectionName: String,
                           entityRecordId: String? = nil,
                           existingCollectionId: String? = nil) -> ScrivanoCollection? {
        guard let pullCollection = response.collection,
              let items = pullCollection.items, !items.isEmpty else { return nil }

        let integrationName = installed.first(where: { $0.id == integrationId })?.config.name ?? integrationId

        // Use existing collection if provided
        let collection: ScrivanoCollection
        if let existingId = existingCollectionId,
           let found = LocalCollectionStore.shared.collections.first(where: { $0.id == existingId }) {
            collection = found
        } else {
            // Ensure unique name — append counter if name already taken
            let baseName = collectionName.isEmpty ? integrationName : collectionName
            let existingNames = Set(LocalCollectionStore.shared.collections.map(\.name))
            var finalName = baseName
            var counter = 2
            while existingNames.contains(finalName) {
                finalName = "\(baseName) (\(counter))"
                counter += 1
            }
            collection = ScrivanoCollection(id: UUID().uuidString, name: finalName)
            LocalCollectionStore.shared.save(collection)
        }

        let isoFmt = ISO8601DateFormatter()
        var transcriptBatch: [LocalTranscriptEntry] = []
        var metadataMap = loadItemMetadataMap()
        var warnings: [String] = []
        for pullItem in items {
            let trimmedName = pullItem.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedName.isEmpty else { continue }

            // Reuse existing item in this collection if name matches — avoids duplicates when pulling additional content
            let existingItem = LocalItemStore.shared.items.first(where: {
                $0.collectionId == collection.id && $0.name == trimmedName
            })
            let itemId: String
            if let existing = existingItem {
                itemId = existing.id
            } else {
                itemId = UUID().uuidString
                let storedItem = LocalStoredItem(
                    id: itemId,
                    name: trimmedName,
                    collection: collection.name,
                    collectionId: collection.id,
                    createdAt: isoFmt.string(from: Date())
                )
                LocalItemStore.shared.save(storedItem)
            }
            // Store integration metadata
            var rawFields = pullItem.metadata ?? [:]
            if let mrn = entityRecordId, !mrn.isEmpty {
                rawFields["mrn"] = rawFields["mrn"] ?? mrn
            }
            let sourceId = entityRecordId ?? rawFields["mrn"] ?? rawFields["id"] ?? trimmedName
            metadataMap[itemId] = IntegrationItemMetadata(
                integrationId: integrationId,
                integrationName: integrationName,
                sourceIdentifier: sourceId,
                identifierLabel: "MRN",
                rawFields: rawFields,
                lastSynced: Date()
            )

            // Collect non-fatal errors (e.g. 403 on labs in sandbox)
            if let errs = pullItem.errors { warnings.append(contentsOf: errs) }

            // Save transcripts nested directly on the patient item
            if let transcripts = pullItem.transcripts {
                for transcript in transcripts {
                    guard let content = transcript.content, !content.isEmpty else { continue }
                    transcriptBatch.append(LocalTranscriptEntry(
                        id: UUID().uuidString,
                        itemId: itemId,
                        label: transcript.title ?? "Clinical Note",
                        text: content,
                        durationSeconds: nil,
                        createdAt: Date()
                    ))
                }
            }
        }

        if !transcriptBatch.isEmpty { LocalTranscriptStore.shared.addBatch(transcriptBatch) }
        saveItemMetadataMap(metadataMap)
        lastPullWarnings = warnings
        return collection
    }

    // MARK: - Integration item metadata

    private let metadataKey = "integration.item.metadata.v1"

    func integrationMetadata(for itemId: String) -> IntegrationItemMetadata? {
        loadItemMetadataMap()[itemId]
    }

    /// Returns the collection name if any patient in the pull response already exists locally.
    func existingCollectionName(for response: PullResponse, entityRecordId: String?) -> String? {
        let map = loadItemMetadataMap()
        let items = response.collection?.items ?? []
        for pullItem in items {
            let name = pullItem.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let mrn = entityRecordId ?? pullItem.metadata?["mrn"] ?? ""
            // Check by MRN first (most reliable)
            if !mrn.isEmpty, let entry = map.first(where: { $0.value.sourceIdentifier == mrn }) {
                if let item = LocalItemStore.shared.items.first(where: { $0.id == entry.key }),
                   let colId = item.collectionId,
                   let col = LocalCollectionStore.shared.collections.first(where: { $0.id == colId }) {
                    return col.name
                }
            }
            // Fall back to patient name match
            if !name.isEmpty, let entry = map.first(where: { _ in
                LocalItemStore.shared.items.first(where: { $0.name == name && map[$0.id] != nil }) != nil
            }) {
                let _ = entry
                if let item = LocalItemStore.shared.items.first(where: { $0.name == name && map[$0.id] != nil }),
                   let colId = item.collectionId,
                   let col = LocalCollectionStore.shared.collections.first(where: { $0.id == colId }) {
                    return col.name
                }
            }
        }
        return nil
    }

    private func loadItemMetadataMap() -> [String: IntegrationItemMetadata] {
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let map = try? JSONDecoder().decode([String: IntegrationItemMetadata].self, from: data)
        else { return [:] }
        return map
    }

    private func saveItemMetadataMap(_ map: [String: IntegrationItemMetadata]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: metadataKey)
        }
    }

    // MARK: - Push

    // MARK: - Push config persistence

    func savePushConfig(_ config: SavedPushConfig, integrationId: String) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "pushConfig.\(integrationId)")
        }
    }

    func loadPushConfig(integrationId: String) -> SavedPushConfig {
        guard let data = UserDefaults.standard.data(forKey: "pushConfig.\(integrationId)"),
              let config = try? JSONDecoder().decode(SavedPushConfig.self, from: data)
        else { return SavedPushConfig() }
        return config
    }

    func push(integrationId: String,
              itemId: String,
              noteText: String,
              noteTitle: String,
              noteTypeCode: String? = nil,
              noteTypeDisplay: String? = nil,
              noteStatus: String? = nil,
              pushFormat: String? = nil) async throws -> ActionResponse {

        let metadata = integrationMetadata(for: itemId)?.rawFields ?? [:]
        let body = PushRequest(noteText: noteText, noteTitle: noteTitle,
                               noteTypeCode: noteTypeCode, noteTypeDisplay: noteTypeDisplay,
                               noteStatus: noteStatus, pushFormat: pushFormat,
                               metadata: metadata)
        let response = try await api.request(
            path: "/api/integrations/\(integrationId)/push",
            method: "POST",
            body: body,
            responseType: ActionResponse.self
        )
        let errorMsg = response.error ?? (response.success == false ? response.message : nil)
        appendLog(IntegrationLogEntry(
            id: UUID().uuidString,
            integrationId: integrationId,
            integrationName: installed.first(where: { $0.id == integrationId })?.config.name ?? integrationId,
            action: .push,
            targetLabel: "Note",
            contentLabels: [],
            destinationName: nil,
            resultSummary: response.message ?? (response.success == true ? "Note pushed" : "Failed"),
            status: errorMsg == nil ? .success : .error,
            errorMessage: errorMsg,
            date: Date()
        ))
        if let err = errorMsg { throw NSError(domain: "push", code: 502, userInfo: [NSLocalizedDescriptionKey: err]) }
        return response
    }

    // MARK: - Logs

    func fetchLogs(integrationId: String) async {
        do {
            let response = try await api.request(
                path: "/api/integrations/\(integrationId)/logs",
                method: "GET",
                responseType: ServerLogsResponse.self
            )
            if let entries = response.logs {
                let mapped = entries.compactMap { mapServerLog($0, integrationId: integrationId) }
                let existing = log.filter { $0.integrationId != integrationId }
                log = existing + mapped
            }
        } catch {}
    }

    private func mapServerLog(_ e: ServerLogEntry, integrationId: String) -> IntegrationLogEntry? {
        let name = installed.first(where: { $0.id == integrationId })?.config.name ?? integrationId
        let status: LogEntryStatus = e.status == "success" ? .success : .error
        var date = Date()
        if let str = e.createdAt {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = f.date(from: str) ?? Date()
        }
        let count = e.itemsCount ?? 0
        return IntegrationLogEntry(
            id: e.id ?? UUID().uuidString,
            integrationId: integrationId,
            integrationName: name,
            action: .pull,
            targetLabel: e.entity ?? e.collectionName ?? "Request",
            contentLabels: e.contentTypes ?? [],
            destinationName: e.collectionName,
            resultSummary: status == .success ? "\(count) item(s)" : e.errorMessage,
            status: status,
            errorMessage: status == .error ? e.errorMessage : nil,
            date: date
        )
    }

    // MARK: - Local log

    func appendLog(_ entry: IntegrationLogEntry) {
        log.insert(entry, at: 0)
        if log.count > 200 { log = Array(log.prefix(200)) }
    }

    func logEntries(for integrationId: String) -> [IntegrationLogEntry] {
        log.filter { $0.integrationId == integrationId }
    }

    // MARK: - Helpers

    private func connectionState(from status: String?) -> ConnectionState {
        switch status {
        case "active":   return .connected
        case "expired":  return .expired
        case "error":    return .error
        default:         return .disconnected
        }
    }

    // MARK: - Persistence

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
