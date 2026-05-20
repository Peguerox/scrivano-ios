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
    let noteTypes: [NoteTypeOption]        // from server; empty = use fallback
    let canPush: Bool
    let supportedPushFormats: [String]     // [] = text only; ["text","pdf"] = both
    let supportedNoteStatuses: [String]    // [] = final only; ["draft","final"] = both
    let maxNoteLength: Int?
    let rateLimitMs: Int?
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
    var group: String? = nil
    var defaultCount: Int? = nil
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
        case .connected:    return "Active"
        case .expired:      return "Expired"
        case .error:        return "Invalid"
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
    let status: String?
    let lastSyncedAt: String?
    let noteTypes: [ServerNoteType]?

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, installed, status
        case logoUrl       = "logo_url"
        case lastSyncedAt  = "last_synced_at"
        case noteTypes     = "note_types"
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
            noteTypes: (noteTypes ?? []).map { NoteTypeOption(id: $0.code, display: $0.display) },
            canPush: true,
            supportedPushFormats: [],
            supportedNoteStatuses: [],
            maxNoteLength: nil,
            rateLimitMs: nil,
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

        // Prefer new grouped format; fall back to flat content_types if groups not present yet
        let pullContent: [IntegrationOption]
        if let groups = capabilities?.contentTypeGroups, !groups.isEmpty {
            pullContent = groups.flatMap { group in
                group.items.map { item in
                    IntegrationOption(id: item.id, label: item.label, subtitle: "",
                                      group: group.group, defaultCount: item.defaultCount)
                }
            }
        } else {
            pullContent = (capabilities?.contentTypes ?? []).map { item in
                IntegrationOption(id: item.id, label: item.label, subtitle: "",
                                  defaultCount: item.defaultCount)
            }
        }

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
            pullContent: pullContent,
            pushTargets: [],
            identifierLabel: entities.first(where: { $0.requiresId == true })?.idLabel,
            identifierPlaceholder: entities.first(where: { $0.requiresId == true })?.idLabel,
            listSourceEntity: capabilities?.listSourceEntity,
            noteTypes: (capabilities?.noteTypes ?? []).map { NoteTypeOption(id: $0.code, display: $0.display) },
            canPush: capabilities?.canPush ?? true,
            supportedPushFormats: capabilities?.pushFormats ?? [],
            supportedNoteStatuses: capabilities?.noteStatuses ?? [],
            maxNoteLength: capabilities?.maxNoteLength,
            rateLimitMs: capabilities?.rateLimitMs,
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
    let contentTypeGroups: [ServerContentTypeGroup]?
    let contentTypes: [ServerContentTypeItem]?
    let canPush: Bool?
    let listSourceEntity: String?
    let noteTypes: [ServerNoteType]?
    let pushFormats: [String]?
    let noteStatuses: [String]?
    let maxNoteLength: Int?
    let rateLimitMs: Int?

    enum CodingKeys: String, CodingKey {
        case entities
        case contentTypeGroups = "content_type_groups"
        case contentTypes      = "content_types"
        case canPush           = "can_push"
        case listSourceEntity  = "list_source_entity"
        case noteTypes         = "note_types"
        case pushFormats       = "push_formats"
        case noteStatuses      = "note_statuses"
        case maxNoteLength     = "max_note_length"
        case rateLimitMs       = "rate_limit_ms"
    }
}

struct ServerNoteType: Codable {
    let code: String
    let display: String
}

struct ServerContentTypeGroup: Codable {
    let group: String
    let items: [ServerContentTypeItem]
}

struct ServerContentTypeItem: Codable {
    let id: String
    let label: String
    let defaultCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, label
        case defaultCount = "default_count"
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
    let listId: String?
    let entityRecordId: String?
    let contentTypes: [String]
    let counts: [String: Int]?
    let collectionName: String?

    enum CodingKeys: String, CodingKey {
        case entityId       = "entity_id"
        case listId         = "list_id"
        case entityRecordId = "entity_record_id"
        case contentTypes   = "content_types"
        case counts
        case collectionName = "collection_name"
    }
}

// MARK: - Browse

struct BrowseResponse: Codable {
    let entityId: String?
    let items: [BrowseItem]?

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case items
    }
}

struct BrowseItem: Codable, Identifiable {
    let id: String
    let name: String
    let metadata: [String: String]?
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
    let errors: [String]?
}

struct PullTranscript: Codable {
    let title: String?
    let content: String?
}

// MARK: - Push

struct NoteTypeOption: Codable, Identifiable {
    let id: String      // LOINC code
    let display: String

    // Fallback used when the server doesn't provide note_types
    static let fallback: [NoteTypeOption] = [
        NoteTypeOption(id: "11506-3", display: "Progress Note"),
        NoteTypeOption(id: "11488-4", display: "Consultation Note"),
        NoteTypeOption(id: "18842-5", display: "Discharge Summary"),
        NoteTypeOption(id: "34117-2", display: "History & Physical"),
        NoteTypeOption(id: "28570-0", display: "Operative Note"),
        NoteTypeOption(id: "18748-4", display: "Radiology Report"),
    ]

    static let defaultOption = NoteTypeOption(id: "11506-3", display: "Progress Note")
}

struct SavedPushConfig: Codable, Equatable {
    var noteTypeCode: String    = "11506-3"
    var noteTypeDisplay: String = "Progress Note"
    var pushFormat: String      = "text"    // "text" | "pdf"
    var noteStatus: String      = "final"   // "final" | "draft"
}

struct PushRequest: Encodable {
    let noteText: String
    let noteTitle: String
    let noteTypeCode: String?
    let noteTypeDisplay: String?
    let noteStatus: String?
    let pushFormat: String?
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case noteText        = "note_text"
        case noteTitle       = "note_title"
        case noteTypeCode    = "note_type_code"
        case noteTypeDisplay = "note_type_display"
        case noteStatus      = "note_status"
        case pushFormat      = "push_format"
        case metadata
    }
}

struct ActionResponse: Codable {
    let success: Bool?
    let message: String?
    let error: String?
    let collectionId: String?
    let ehrId: String?

    enum CodingKeys: String, CodingKey {
        case success, message, error
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
