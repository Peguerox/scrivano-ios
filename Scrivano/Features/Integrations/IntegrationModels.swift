import Foundation

// MARK: - Config (downloaded from Supabase catalog)

struct IntegrationConfig: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: IntegrationType
    let description: String
    let logoEmoji: String
    let logoColorStart: String   // hex, e.g. "#1a3a6e"
    let logoColorEnd: String
    let authType: AuthType
    let baseURL: String
    let tokenURL: String?
    let scopes: [String]
    let pullTargets: [IntegrationOption]
    let pullContent: [IntegrationOption]
    let pushTargets: [IntegrationOption]
    let identifierLabel: String?        // e.g. "MRN"
    let identifierPlaceholder: String?  // e.g. "Enter MRN…"

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

// MARK: - Installed Integration (config + auth state stored locally)

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

// MARK: - Log Entry

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

// MARK: - Request payload (sent to server)

struct IntegrationRequest: Codable {
    let integrationId: String
    let action: LogAction
    let target: String           // option id e.g. "patient_list"
    let content: [String]        // content option ids e.g. ["notes","labs"]
    let identifier: String?      // for specific patient lookups
    let destinationCollectionId: String?
    let destinationName: String?
}

// MARK: - Item metadata (stored silently per item)

struct IntegrationItemMetadata: Codable {
    let integrationId: String
    let integrationName: String
    let sourceIdentifier: String   // MRN, client ID, etc.
    let identifierLabel: String    // "MRN", "Client ID", etc.
    let rawFields: [String: String]
    let lastSynced: Date
}
