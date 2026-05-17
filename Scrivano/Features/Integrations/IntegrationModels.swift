import Foundation

// MARK: - Local models (used by the UI)

struct IntegrationConfig: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: IntegrationType
    let description: String
    let logoUrl: String?
    let logoEmoji: String
    let logoColorStart: String
    let logoColorEnd: String
    let authType: AuthType
    let requiresBaseUrl: Bool
    let baseUrlLabel: String?
    let baseUrlDefault: String?
    let pullTargets: [IntegrationOption]   // entities → radio buttons
    let pullContent: [IntegrationOption]   // content_types → checkboxes
    let pushTargets: [IntegrationOption]
    let identifierLabel: String?
    let identifierPlaceholder: String?
    let listSourceEntity: String?          // if set, browse endpoint must be called first
    var installed: Bool

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
}

struct IntegrationOption: Codable, Identifiable {
    let id: String
    let label: String
    let subtitle: String
    var requiresId: Bool = false
    var idLabel: String? = nil
}

enum IntegrationType: String, Codable {
    case medical, legal, crm, finance, custom
    var label: String {
        switch self {
        case .medical:  return "Medical"
        case .legal:    return "Legal"
        case .crm:      return "CRM"
        case .finance:  return "Finance"
        case .custom:   return "Custom"
        }
    }
}

enum AuthType: String, Codable {
    case oauth2
    case apiKey = "api-key"
    case basic

    var isOAuth: Bool { self == .oauth2 }
    var requiresCredentials: Bool { self == .apiKey || self == .basic }
    var credentialLabel: String {
        switch self {
        case .oauth2:  return "OAuth 2.0"
        case .apiKey:  return "API Key"
        case .basic:   return "Username & Password"
        }
    }
}

struct InstalledIntegration: Codable, Identifiable {
    let id: String
    var config: IntegrationConfig
    var connectionState: ConnectionState = .disconnected
    var accountEmail: String?
    var accountOrganization: String?
    var tokenPreview: String?
    var tokenExpiry: Date?
    var tokenScopes: String?
    var lastAuthDate: Date?
    var installedAt: Date = Date()
    var baseUrl: String?          // user-entered EHR base URL (if required)
}

enum ConnectionState: String, Codable {
    case disconnected, connected, expired, error
    var label: String {
        switch self {
        case .disconnected: return "Not connected"
        case .connected:    return "Connected"
        case .expired:      return "Token expired"
        case .error:        return "Error"
        }
    }
}

struct IntegrationLogEntry: Codable, Identifiable {
    let id: String
    let integrationId: String
    let integrationName: String
    let action: LogAction
    let targetLabel: String
    let contentLabels: [String]
    let destinationName: String?
    let resultSummary: String?
    let status: LogEntryStatus
    let errorMessage: String?
    let date: Date
}

enum LogAction: String, Codable { case pull, push }
enum LogEntryStatus: String, Codable { case success, error }

struct IntegrationItemMetadata: Codable {
    let integrationId: String
    let integrationName: String
    let sourceIdentifier: String
    let identifierLabel: String
    let rawFields: [String: String]
    let lastSynced: Date
}

// MARK: - Server response models

struct IntegrationListResponse: Codable {
    let integrations: [ServerIntegrationListItem]
}

/// Lightweight item from GET /api/integrations list
struct ServerIntegrationListItem: Codable {
    let id: String
    let name: String
    let description: String?
    let logoUrl: String?
    let version: String?
    let installed: Bool?
    let status: String?           // "active" | "pending_auth" | "error"
    let lastSyncedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, installed, status
        case logoUrl       = "logo_url"
        case lastSyncedAt  = "last_synced_at"
    }

    /// Converts list item to a minimal config; full config fetched separately via GET /api/integrations/{id}
    func toMinimalConfig() -> IntegrationConfig {
        IntegrationConfig(
            id: id,
            name: name,
            type: .custom,
            description: description ?? "",
            logoUrl: logoUrl,
            logoEmoji: "🔗",
            logoColorStart: "#1a1a2e",
            logoColorEnd: "#0e0e1e",
            authType: .oauth2,
            requiresBaseUrl: false,
            baseUrlLabel: nil,
            baseUrlDefault: nil,
            pullTargets: [],
            pullContent: [],
            pushTargets: [],
            identifierLabel: nil,
            identifierPlaceholder: nil,
            listSourceEntity: nil,
            installed: installed ?? false
        )
    }
}

/// Full detail from GET /api/integrations/{id}
struct ServerIntegrationDetail: Codable {
    let id: String
    let name: String
    let description: String?
    let logoUrl: String?
    let version: String?
    let installed: Bool?
    let status: String?
    let auth: ServerAuth?
    let capabilities: ServerCapabilities?

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, installed, status, auth, capabilities
        case logoUrl = "logo_url"
    }

    func toConfig() -> IntegrationConfig {
        let rawType = auth?.type ?? "oauth2"
        let authType = AuthType(rawValue: rawType) ?? .oauth2
        let entities = capabilities?.entities ?? []
        let contentTypes = capabilities?.contentTypes ?? []

        return IntegrationConfig(
            id: id,
            name: name,
            type: .medical,
            description: description ?? "",
            logoUrl: logoUrl,
            logoEmoji: "🔗",
            logoColorStart: "#1a1a2e",
            logoColorEnd: "#0e0e1e",
            authType: authType,
            requiresBaseUrl: auth?.requiresBaseUrl ?? false,
            baseUrlLabel: auth?.baseUrlLabel,
            baseUrlDefault: auth?.baseUrlDefault,
            pullTargets: entities.map { IntegrationOption(id: $0.id, label: $0.label, subtitle: $0.description ?? "", requiresId: $0.requiresId ?? false, idLabel: $0.idLabel) },
            pullContent: contentTypes.map { IntegrationOption(id: $0.id, label: $0.label, subtitle: "") },
            pushTargets: [],
            identifierLabel: entities.first(where: { $0.requiresId == true })?.idLabel,
            identifierPlaceholder: entities.first(where: { $0.requiresId == true })?.idLabel,
            listSourceEntity: capabilities?.listSourceEntity,
            installed: installed ?? false
        )
    }
}

struct ServerAuth: Codable {
    let type: String?
    let requiresBaseUrl: Bool?
    let baseUrlLabel: String?
    let baseUrlDefault: String?

    enum CodingKeys: String, CodingKey {
        case type
        case requiresBaseUrl  = "requires_base_url"
        case baseUrlLabel     = "base_url_label"
        case baseUrlDefault   = "base_url_default"
    }
}

struct ServerCapabilities: Codable {
    let entities: [ServerEntity]?
    let contentTypes: [ServerContentType]?
    let canPush: Bool?
    let listSourceEntity: String?

    enum CodingKeys: String, CodingKey {
        case entities
        case contentTypes     = "content_types"
        case canPush          = "can_push"
        case listSourceEntity = "list_source_entity"
    }
}

struct ServerEntity: Codable {
    let id: String
    let label: String
    let description: String?
    let requiresId: Bool?
    let idLabel: String?

    enum CodingKeys: String, CodingKey {
        case id, label, description
        case requiresId = "requires_id"
        case idLabel    = "id_label"
    }
}

struct ServerContentType: Codable {
    let id: String
    let label: String
}

struct ServerOption: Codable {
    let id: String
    let label: String
    let subtitle: String?

    var toOption: IntegrationOption {
        IntegrationOption(id: id, label: label, subtitle: subtitle ?? "")
    }
}

// MARK: - Install

struct InstallRequest: Encodable {
    let baseUrl: String?
    let apiKey: String?
    let username: String?
    let password: String?

    enum CodingKeys: String, CodingKey {
        case baseUrl  = "base_url"
        case apiKey   = "api_key"
        case username
        case password
    }
}

struct InstallResponse: Codable {
    let success: Bool?
    let authUrl: String?     // OAuth2: redirect URL
    let status: String?      // API key/basic: "active" when done
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success, status, message
        case authUrl = "auth_url"
    }
}

// MARK: - Pull

struct PullRequest: Encodable {
    let entityId: String
    let listId: String?           // selected list from browse dropdown
    let entityRecordId: String?   // only when entity requires_id = true
    let contentTypes: [String]
    let collectionName: String?

    enum CodingKeys: String, CodingKey {
        case entityId       = "entity_id"
        case listId         = "list_id"
        case entityRecordId = "entity_record_id"
        case contentTypes   = "content_types"
        case collectionName = "collection_name"
    }
}

// MARK: - Browse

struct BrowseResponse: Codable {
    let items: [BrowseItem]?
}

struct BrowseItem: Codable, Identifiable {
    let id: String
    let name: String
}

struct PullResponse: Codable {
    let collection: PullCollection?
    let success: Bool?
    let message: String?
}

struct PullCollection: Codable {
    let name: String?
    let items: [PullItem]?
}

struct PullItem: Codable {
    let name: String?
    let metadata: [String: String]?
    let transcripts: [PullTranscript]?
}

struct PullTranscript: Codable {
    let title: String?
    let content: String?
}

// MARK: - Push

struct PushRequest: Encodable {
    let noteText: String
    let noteTitle: String
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case noteText  = "note_text"
        case noteTitle = "note_title"
        case metadata
    }
}

struct ActionResponse: Codable {
    let success: Bool?
    let message: String?
    let collectionId: String?
    let ehrId: String?

    enum CodingKeys: String, CodingKey {
        case success, message
        case collectionId = "collection_id"
        case ehrId        = "ehr_id"
    }
}

// MARK: - Logs

struct ServerLogEntry: Codable {
    let id: String?
    let entity: String?
    let contentTypes: [String]?
    let collectionName: String?
    let status: String?
    let errorMessage: String?
    let itemsCount: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, entity, status
        case contentTypes   = "content_types"
        case collectionName = "collection_name"
        case errorMessage   = "error_message"
        case itemsCount     = "items_count"
        case createdAt      = "created_at"
    }
}

struct ServerLogsResponse: Codable {
    let logs: [ServerLogEntry]?
}
