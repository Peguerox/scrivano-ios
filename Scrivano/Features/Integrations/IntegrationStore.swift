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

    private let installedKey = "integrations.installed.v2"
    private let api = APIClient.shared

    private init() {
        installed = load(key: installedKey) ?? []
    }

    // MARK: - Catalog (from server)

    func fetchCatalog() async {
        isLoadingCatalog = true
        catalogError = nil
        do {
            let response = try await api.request(
                path: "/api/integrations",
                method: "GET",
                responseType: IntegrationListResponse.self
            )
            let configs = response.integrations.map { $0.toConfig() }
            catalog = configs
            // Sync installed flags
            syncInstalledFromCatalog(configs)
        } catch {
            catalogError = error.localizedDescription
        }
        isLoadingCatalog = false
    }

    private func syncInstalledFromCatalog(_ configs: [IntegrationConfig]) {
        // Mark integrations the server says are installed
        for config in configs where config.installed {
            if !installed.contains(where: { $0.id == config.id }) {
                let integration = InstalledIntegration(id: config.id, config: config,
                                                       connectionState: .connected)
                installed.append(integration)
                save(installed, key: installedKey)
            }
        }
        // Remove locally installed ones the server no longer lists as installed
        let serverInstalledIds = Set(configs.filter(\.installed).map(\.id))
        let before = installed.count
        installed.removeAll { !serverInstalledIds.contains($0.id) }
        if installed.count != before { save(installed, key: installedKey) }
    }

    // MARK: - Install

    /// Installs an integration and returns the OAuth URL if auth is required.
    func install(integrationId: String) async throws -> URL? {
        let body = ["base_url": String?.none as Any?]  // null base_url per spec
        struct InstallBody: Encodable { let base_url: String? }
        let response = try await api.request(
            path: "/api/integrations/\(integrationId)/install",
            method: "POST",
            body: InstallBody(base_url: nil),
            responseType: InstallResponse.self
        )
        // Add to installed list
        if let config = catalog.first(where: { $0.id == integrationId }) {
            var integration = InstalledIntegration(id: integrationId, config: config,
                                                   connectionState: .disconnected)
            if let urlStr = response.oauthUrl, !urlStr.isEmpty {
                integration.connectionState = .disconnected
            } else {
                integration.connectionState = .connected
                integration.lastAuthDate = Date()
            }
            if !installed.contains(where: { $0.id == integrationId }) {
                installed.append(integration)
                save(installed, key: installedKey)
            }
        }
        if let urlStr = response.oauthUrl, let url = URL(string: urlStr) {
            return url
        }
        return nil
    }

    // MARK: - Uninstall

    func uninstall(integrationId: String) async throws {
        struct Empty: Codable {}
        _ = try? await api.request(
            path: "/api/integrations/\(integrationId)/uninstall",
            method: "DELETE",
            responseType: ActionResponse.self
        )
        installed.removeAll { $0.id == integrationId }
        log.removeAll { $0.integrationId == integrationId }
        save(installed, key: installedKey)
    }

    // MARK: - Mark connected (called after OAuth callback)

    func markConnected(integrationId: String, email: String? = nil, org: String? = nil) {
        guard let idx = installed.firstIndex(where: { $0.id == integrationId }) else { return }
        installed[idx].connectionState = .connected
        installed[idx].lastAuthDate = Date()
        if let email { installed[idx].accountEmail = email }
        if let org   { installed[idx].accountOrganization = org }
        save(installed, key: installedKey)
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

    // MARK: - Pull

    func pull(integrationId: String, target: String, content: [String], identifier: String?) async throws -> ActionResponse {
        let body = PullRequest(entityId: target, contentTypes: content, identifier: identifier?.isEmpty == true ? nil : identifier)
        let response = try await api.request(
            path: "/api/integrations/\(integrationId)/pull",
            method: "POST",
            body: body,
            responseType: ActionResponse.self
        )
        appendLog(IntegrationLogEntry(
            id: UUID().uuidString,
            integrationId: integrationId,
            integrationName: installed.first(where: { $0.id == integrationId })?.config.name ?? integrationId,
            action: .pull,
            targetLabel: target,
            contentLabels: content,
            destinationName: nil,
            resultSummary: response.message,
            status: response.success == true ? .success : .error,
            errorMessage: response.success == true ? nil : response.message,
            date: Date()
        ))
        return response
    }

    // MARK: - Push

    func push(integrationId: String, noteText: String, noteTitle: String, ehrId: String?, mrn: String?) async throws -> ActionResponse {
        let body = PushRequest(noteText: noteText, noteTitle: noteTitle,
                               metadata: PushMetadata(ehrId: ehrId, mrn: mrn))
        let response = try await api.request(
            path: "/api/integrations/\(integrationId)/push",
            method: "POST",
            body: body,
            responseType: ActionResponse.self
        )
        appendLog(IntegrationLogEntry(
            id: UUID().uuidString,
            integrationId: integrationId,
            integrationName: installed.first(where: { $0.id == integrationId })?.config.name ?? integrationId,
            action: .push,
            targetLabel: "Note",
            contentLabels: [],
            destinationName: nil,
            resultSummary: response.message,
            status: response.success == true ? .success : .error,
            errorMessage: response.success == true ? nil : response.message,
            date: Date()
        ))
        return response
    }

    // MARK: - Fetch logs from server

    func fetchLogs(integrationId: String) async {
        do {
            // Try object wrapper first
            if let response = try? await api.request(
                path: "/api/integrations/\(integrationId)/logs",
                method: "GET",
                responseType: ServerLogsResponse.self
            ), let entries = response.logs {
                let mapped = entries.compactMap { mapServerLog($0, integrationId: integrationId) }
                let existing = log.filter { $0.integrationId != integrationId }
                log = existing + mapped
            }
        }
    }

    private func mapServerLog(_ e: ServerLogEntry, integrationId: String) -> IntegrationLogEntry? {
        let name = installed.first(where: { $0.id == integrationId })?.config.name ?? integrationId
        let action: LogAction = e.action == "push" ? .push : .pull
        let status: LogEntryStatus = e.status == "success" || e.status == "completed" ? .success : .error
        var date = Date()
        if let str = e.createdAt {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = f.date(from: str) ?? Date()
        }
        return IntegrationLogEntry(
            id: e.id ?? UUID().uuidString,
            integrationId: integrationId,
            integrationName: name,
            action: action,
            targetLabel: e.target ?? "Request",
            contentLabels: e.content ?? [],
            destinationName: nil,
            resultSummary: e.summary ?? e.message,
            status: status,
            errorMessage: status == .error ? (e.message ?? "Unknown error") : nil,
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
