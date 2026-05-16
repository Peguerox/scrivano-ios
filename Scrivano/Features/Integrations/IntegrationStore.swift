import Foundation

@MainActor
final class IntegrationStore: ObservableObject {
    static let shared = IntegrationStore()

    @Published private(set) var installed: [InstalledIntegration] = []
    @Published private(set) var log: [IntegrationLogEntry] = []

    private let installedKey = "integrations.installed"
    private let logKey       = "integrations.log"

    private init() {
        installed = load(key: installedKey) ?? []
        log       = load(key: logKey) ?? []
        seedMockDataIfNeeded()
    }

    private func seedMockDataIfNeeded() {
        guard installed.isEmpty else { return }
        let epic   = IntegrationStore.catalog.first(where: { $0.id == "epic_mychart" })!
        let sf     = IntegrationStore.catalog.first(where: { $0.id == "clio" })!

        var epicInstalled = InstalledIntegration(id: epic.id, config: epic)
        epicInstalled.connectionState    = .connected
        epicInstalled.accountEmail       = "jpeguero@mhs.net"
        epicInstalled.accountOrganization = "Memorial Cardiac Institute"
        epicInstalled.tokenPreview       = "ey7f…xK9p"
        epicInstalled.tokenExpiry        = Date().addingTimeInterval(6 * 3600)
        epicInstalled.tokenScopes        = "patient/*.read write"
        epicInstalled.lastAuthDate       = Date()

        var clioInstalled = InstalledIntegration(id: sf.id, config: sf)
        clioInstalled.connectionState    = .expired
        clioInstalled.accountEmail       = "jpeguero@lawfirm.com"
        clioInstalled.accountOrganization = "Peguero Law Group"
        clioInstalled.tokenPreview       = "cl9a…mZ3q"
        clioInstalled.tokenExpiry        = Date().addingTimeInterval(-3600)
        clioInstalled.lastAuthDate       = Calendar.current.date(byAdding: .day, value: -2, to: Date())

        installed = [epicInstalled, clioInstalled]
        save(installed, key: installedKey)

        // Seed some log entries
        let now = Date()
        log = [
            IntegrationLogEntry(id: UUID().uuidString, integrationId: epic.id, integrationName: epic.name,
                                action: .pull, targetLabel: "Patient list", contentLabels: ["Notes", "Medications"],
                                destinationName: "Epic MyChart · May 16", resultSummary: "48 patients · 96 transcripts",
                                status: .success, errorMessage: nil,
                                date: now.addingTimeInterval(-7200)),
            IntegrationLogEntry(id: UUID().uuidString, integrationId: epic.id, integrationName: epic.name,
                                action: .push, targetLabel: "Full collection", contentLabels: [],
                                destinationName: "Morning Rounds", resultSummary: "12 notes pushed",
                                status: .success, errorMessage: nil,
                                date: Calendar.current.date(byAdding: .day, value: -1, to: now)!),
            IntegrationLogEntry(id: UUID().uuidString, integrationId: epic.id, integrationName: epic.name,
                                action: .pull, targetLabel: "Patient list", contentLabels: ["Notes", "Labs", "Diagnoses"],
                                destinationName: "Cardiology Clinic", resultSummary: nil,
                                status: .error, errorMessage: "Token expired during request · Tap to retry",
                                date: Calendar.current.date(byAdding: .day, value: -2, to: now)!),
            IntegrationLogEntry(id: UUID().uuidString, integrationId: epic.id, integrationName: epic.name,
                                action: .pull, targetLabel: "Specific patient", contentLabels: ["Notes"],
                                destinationName: "Cardiology Clinic", resultSummary: "1 patient",
                                status: .success, errorMessage: nil,
                                date: Calendar.current.date(byAdding: .day, value: -3, to: now)!),
            IntegrationLogEntry(id: UUID().uuidString, integrationId: sf.id, integrationName: sf.name,
                                action: .pull, targetLabel: "Client list", contentLabels: ["Notes"],
                                destinationName: "Peguero Law · May 12", resultSummary: "31 clients · 31 notes",
                                status: .success, errorMessage: nil,
                                date: Calendar.current.date(byAdding: .day, value: -4, to: now)!),
        ]
        save(log, key: logKey)
    }

    // MARK: - Installed integrations

    func install(_ config: IntegrationConfig) {
        guard !installed.contains(where: { $0.id == config.id }) else { return }
        installed.append(InstalledIntegration(id: config.id, config: config))
        save(installed, key: installedKey)
    }

    func uninstall(id: String) {
        installed.removeAll { $0.id == id }
        save(installed, key: installedKey)
    }

    func updateConnection(_ integration: InstalledIntegration) {
        if let idx = installed.firstIndex(where: { $0.id == integration.id }) {
            installed[idx] = integration
            save(installed, key: installedKey)
        }
    }

    func disconnect(id: String) {
        if let idx = installed.firstIndex(where: { $0.id == id }) {
            installed[idx].connectionState = .disconnected
            installed[idx].accountEmail = nil
            installed[idx].accountOrganization = nil
            installed[idx].tokenPreview = nil
            installed[idx].tokenExpiry = nil
            installed[idx].tokenScopes = nil
            installed[idx].lastAuthDate = nil
            save(installed, key: installedKey)
        }
    }

    // MARK: - Log

    func appendLog(_ entry: IntegrationLogEntry) {
        log.insert(entry, at: 0)
        if log.count > 200 { log = Array(log.prefix(200)) }
        save(log, key: logKey)
    }

    func clearLog(for integrationId: String) {
        log.removeAll { $0.integrationId == integrationId }
        save(log, key: logKey)
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

// MARK: - Catalog (hardcoded until Supabase is ready)

extension IntegrationStore {
    static let catalog: [IntegrationConfig] = [
        IntegrationConfig(
            id: "epic_mychart",
            name: "Epic MyChart",
            type: .medical,
            description: "Patient lists, notes, labs and medications from Epic's EHR system",
            logoEmoji: "🏥",
            logoColorStart: "#1a3a6e",
            logoColorEnd: "#0e2348",
            authType: .oauth2,
            baseURL: "https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4",
            tokenURL: "https://fhir.epic.com/interconnect-fhir-oauth/oauth2/token",
            scopes: ["patient/*.read", "launch/patient"],
            pullTargets: [
                IntegrationOption(id: "patient_list",    label: "Patient list",    subtitle: "All patients available from this integration"),
                IntegrationOption(id: "specific_patient",label: "Specific patient",subtitle: "Look up by identifier"),
                IntegrationOption(id: "existing_item",   label: "Existing item",   subtitle: "Update a record already in a collection"),
            ],
            pullContent: [
                IntegrationOption(id: "notes",      label: "Notes",        subtitle: "Most recent clinical notes"),
                IntegrationOption(id: "labs",       label: "Labs",         subtitle: "Results and values"),
                IntegrationOption(id: "medications",label: "Medications",  subtitle: "Active and past prescriptions"),
                IntegrationOption(id: "diagnoses",  label: "Diagnoses",    subtitle: "Problem list and ICD codes"),
                IntegrationOption(id: "allergies",  label: "Allergies",    subtitle: "Reactions and severity"),
                IntegrationOption(id: "history",    label: "Past history", subtitle: "Prior conditions and procedures"),
                IntegrationOption(id: "visits",     label: "Visits",       subtitle: "Encounter and appointment history"),
            ],
            pushTargets: [
                IntegrationOption(id: "full_collection",  label: "Full collection",  subtitle: "Push all items from a collection"),
                IntegrationOption(id: "specific_items",   label: "Specific items",   subtitle: "Choose individual items to push"),
            ],
            identifierLabel: "MRN",
            identifierPlaceholder: "Enter MRN…"
        ),
        IntegrationConfig(
            id: "cerner",
            name: "Cerner",
            type: .medical,
            description: "Patient lists, notes, labs and medications from Oracle Cerner",
            logoEmoji: "⚕️",
            logoColorStart: "#1a3a6e",
            logoColorEnd: "#0e2348",
            authType: .oauth2,
            baseURL: "https://fhir-myrecord.cerner.com/r4",
            tokenURL: nil,
            scopes: ["patient/*.read"],
            pullTargets: [
                IntegrationOption(id: "patient_list",    label: "Patient list",    subtitle: "All patients from Cerner"),
                IntegrationOption(id: "specific_patient",label: "Specific patient",subtitle: "Look up by identifier"),
            ],
            pullContent: [
                IntegrationOption(id: "notes",      label: "Notes",       subtitle: "Most recent clinical notes"),
                IntegrationOption(id: "labs",       label: "Labs",        subtitle: "Results and values"),
                IntegrationOption(id: "medications",label: "Medications", subtitle: "Active prescriptions"),
                IntegrationOption(id: "diagnoses",  label: "Diagnoses",   subtitle: "Problem list"),
            ],
            pushTargets: [
                IntegrationOption(id: "full_collection", label: "Full collection", subtitle: "Push all items"),
            ],
            identifierLabel: "MRN",
            identifierPlaceholder: "Enter MRN…"
        ),
        IntegrationConfig(
            id: "clio",
            name: "Clio",
            type: .legal,
            description: "Client lists, matters, and case notes from Clio legal",
            logoEmoji: "⚖️",
            logoColorStart: "#2a1a3a",
            logoColorEnd: "#1a0e2a",
            authType: .oauth2,
            baseURL: "https://app.clio.com/api/v4",
            tokenURL: "https://app.clio.com/oauth/token",
            scopes: ["contacts:read", "matters:read"],
            pullTargets: [
                IntegrationOption(id: "client_list",    label: "Client list",    subtitle: "All clients from Clio"),
                IntegrationOption(id: "specific_client",label: "Specific client",subtitle: "Look up by ID"),
            ],
            pullContent: [
                IntegrationOption(id: "notes",   label: "Notes",   subtitle: "Case notes and communications"),
                IntegrationOption(id: "matters", label: "Matters", subtitle: "Open and closed matters"),
            ],
            pushTargets: [
                IntegrationOption(id: "full_collection", label: "Full collection", subtitle: "Push all items"),
            ],
            identifierLabel: "Client ID",
            identifierPlaceholder: "Enter Client ID…"
        ),
        IntegrationConfig(
            id: "hubspot",
            name: "HubSpot",
            type: .crm,
            description: "Contacts and company lists with activity history",
            logoEmoji: "📊",
            logoColorStart: "#1a3320",
            logoColorEnd: "#0e2018",
            authType: .oauth2,
            baseURL: "https://api.hubapi.com",
            tokenURL: "https://api.hubapi.com/oauth/v1/token",
            scopes: ["contacts", "crm.objects.contacts.read"],
            pullTargets: [
                IntegrationOption(id: "contact_list",    label: "Contact list",    subtitle: "All contacts from HubSpot"),
                IntegrationOption(id: "specific_contact",label: "Specific contact",subtitle: "Look up by ID"),
            ],
            pullContent: [
                IntegrationOption(id: "notes",    label: "Notes",    subtitle: "Contact notes and calls"),
                IntegrationOption(id: "activity", label: "Activity", subtitle: "Recent interactions"),
            ],
            pushTargets: [
                IntegrationOption(id: "full_collection", label: "Full collection", subtitle: "Push all items"),
                IntegrationOption(id: "specific_items",  label: "Specific items",  subtitle: "Choose items to push"),
            ],
            identifierLabel: "Contact ID",
            identifierPlaceholder: "Enter Contact ID…"
        ),
        IntegrationConfig(
            id: "custom_api",
            name: "Custom API",
            type: .custom,
            description: "Connect any REST or FHIR endpoint with a config file",
            logoEmoji: "⚙️",
            logoColorStart: "#1a1a1a",
            logoColorEnd: "#0e0e0e",
            authType: .apiKey,
            baseURL: "",
            tokenURL: nil,
            scopes: [],
            pullTargets: [
                IntegrationOption(id: "list",     label: "List",          subtitle: "Pull the full available list"),
                IntegrationOption(id: "specific", label: "Specific item", subtitle: "Look up by identifier"),
            ],
            pullContent: [
                IntegrationOption(id: "data", label: "Data", subtitle: "Available data from this endpoint"),
            ],
            pushTargets: [
                IntegrationOption(id: "full_collection", label: "Full collection", subtitle: "Push all items"),
            ],
            identifierLabel: "ID",
            identifierPlaceholder: "Enter identifier…"
        ),
    ]
}
