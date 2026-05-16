import Foundation

// MARK: - Local models (used by the UI)

struct IntegrationConfig: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: IntegrationType
    let description: String
    let logoEmoji: String
    let logoColorStart: String
    let logoColorEnd: String
    let authType: AuthType
    let pullTargets: [IntegrationOption]
    let pullContent: [IntegrationOption]
    let pushTargets: [IntegrationOption]
    let identifierLabel: String?
    let identifierPlaceholder: String?
    var installed: Bool

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
}

struct IntegrationOption: Codable, Identifiable {
    let id: String
    let label: String
    let subtitle: String
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

enum AuthType: String, Codable { case oauth2, apiKey }

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
    let integrations: [ServerIntegrationConfig]
}

struct ServerIntegrationConfig: Codable {
    let id: String
    let name: String
    let type: String?
    let description: String?
    let logoEmoji: String?
    let logoColorStart: String?
    let logoColorEnd: String?
    let authType: String?
    let pullTargets: [ServerOption]?
    let pullContent: [ServerOption]?
    let pushTargets: [ServerOption]?
    let identifierLabel: String?
    let identifierPlaceholder: String?
    let installed: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, type, description, installed
        case logoEmoji          = "logo_emoji"
        case logoColorStart     = "logo_color_start"
        case logoColorEnd       = "logo_color_end"
        case authType           = "auth_type"
        case pullTargets        = "pull_targets"
        case pullContent        = "pull_content"
        case pushTargets        = "push_targets"
        case identifierLabel    = "identifier_label"
        case identifierPlaceholder = "identifier_placeholder"
    }

    func toConfig() -> IntegrationConfig {
        IntegrationConfig(
            id: id,
            name: name,
            type: IntegrationType(rawValue: type ?? "custom") ?? .custom,
            description: description ?? "",
            logoEmoji: logoEmoji ?? "🔗",
            logoColorStart: logoColorStart ?? "#1a1a2e",
            logoColorEnd: logoColorEnd ?? "#0e0e1e",
            authType: AuthType(rawValue: authType ?? "oauth2") ?? .oauth2,
            pullTargets: (pullTargets ?? []).map(\.toOption),
            pullContent: (pullContent ?? []).map(\.toOption),
            pushTargets: (pushTargets ?? []).map(\.toOption),
            identifierLabel: identifierLabel,
            identifierPlaceholder: identifierPlaceholder,
            installed: installed ?? false
        )
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

struct InstallResponse: Codable {
    let success: Bool?
    let oauthUrl: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success, message
        case oauthUrl = "oauth_url"
    }
}

struct PullRequest: Encodable {
    let entityId: String
    let contentTypes: [String]
    let identifier: String?

    enum CodingKeys: String, CodingKey {
        case entityId    = "entity_id"
        case contentTypes = "content_types"
        case identifier
    }
}

struct PushRequest: Encodable {
    let noteText: String
    let noteTitle: String
    let metadata: PushMetadata

    enum CodingKeys: String, CodingKey {
        case noteText  = "note_text"
        case noteTitle = "note_title"
        case metadata
    }
}

struct PushMetadata: Encodable {
    let ehrId: String?
    let mrn: String?

    enum CodingKeys: String, CodingKey {
        case ehrId = "ehr_id"
        case mrn
    }
}

struct ActionResponse: Codable {
    let success: Bool?
    let message: String?
    let collectionId: String?

    enum CodingKeys: String, CodingKey {
        case success, message
        case collectionId = "collection_id"
    }
}

struct ServerLogEntry: Codable {
    let id: String?
    let action: String?
    let target: String?
    let content: [String]?
    let status: String?
    let message: String?
    let summary: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, action, target, content, status, message, summary
        case createdAt = "created_at"
    }
}

struct ServerLogsResponse: Codable {
    let logs: [ServerLogEntry]?
    // Also accept top-level array
}
