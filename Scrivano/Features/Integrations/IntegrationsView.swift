import SwiftUI
import SafariServices

struct IntegrationsView: View {
    var initialTab: IntTab = .request
    var isRootPresentation: Bool = false  // true when opened directly from Dashboard

    @Environment(\.dismiss) var dismiss
    @ObservedObject private var store = IntegrationStore.shared
    @ObservedObject private var langMgr = LanguageManager.shared

    @AppStorage("lastSelectedIntegrationId") private var lastSelectedId: String = ""
    @State private var selectedId: String? = nil
    @State private var showDropdown = false
    @State private var showCatalogSheet = false
    @State private var activeTab: IntTab = .request
    @State private var oauthURL: URL? = nil
    @State private var pendingOAuthIntegrationId: String? = nil
    @State private var oauthResultMessage: String? = nil
    @State private var oauthResultSuccess: Bool = true

    private var selected: InstalledIntegration? {
        guard let id = selectedId else { return nil }
        return store.installed.first(where: { $0.id == id })
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.phoneBg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if store.isLoadingCatalog && store.catalog.isEmpty && store.installed.isEmpty {
                    Spacer()
                    ProgressView().tint(.brandCyan)
                    Spacer()
                } else {
                    integrationDropdown
                    if let msg = oauthResultMessage {
                        HStack(spacing: 8) {
                            Image(systemName: oauthResultSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(oauthResultSuccess ? .green : .danger)
                            Text(msg)
                                .font(.inter(12, weight: .semibold))
                                .foregroundColor(oauthResultSuccess ? .green : .danger)
                            Spacer()
                            Button { oauthResultMessage = nil } label: {
                                Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.textTertiary)
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(oauthResultSuccess ? Color.green.opacity(0.08) : Color.danger.opacity(0.08))
                    }
                    tabBar
                        .opacity(store.installed.isEmpty ? 0.35 : 1)
                        .disabled(store.installed.isEmpty)
                    tabContent
                }
            }
        }
        .onAppear {
            activeTab = initialTab
            if selectedId == nil && !lastSelectedId.isEmpty {
                // Restore last explicitly selected integration only
                selectedId = store.installed.first(where: { $0.id == lastSelectedId })?.id
            }
            Task {
                await store.fetchCatalog()
                if let id = selectedId {
                    try? await store.fetchDetail(integrationId: id)
                }
            }
        }
        .onChange(of: selectedId) { id in
            if let id {
                lastSelectedId = id
                // Force auth tab if not connected
                let integration = store.installed.first(where: { $0.id == id })
                if integration?.connectionState != .connected {
                    activeTab = .auth
                }
                Task {
                    try? await store.fetchDetail(integrationId: id)
                    // Re-check after fetch in case server state came back as disconnected
                    let updated = store.installed.first(where: { $0.id == id })
                    if updated?.connectionState != .connected {
                        activeTab = .auth
                    }
                }
            }
        }
        .sheet(item: $oauthURL, onDismiss: {
            // Safari dismissed without deep-link callback — restore the pending integration
            if let pendingId = pendingOAuthIntegrationId {
                selectedId = pendingId
                activeTab = .auth
                pendingOAuthIntegrationId = nil
            }
        }) { url in
            SafariView(url: url)
        }
        .sheet(isPresented: $showCatalogSheet) {
            CatalogSheetView(onInstall: { integrationId, url in
                showCatalogSheet = false
                pendingOAuthIntegrationId = integrationId
                oauthURL = url
                if let integrationId {
                    selectedId = integrationId
                    activeTab = .auth
                }
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: .integrationOAuthCallback)) { note in
            let info = note.userInfo ?? [:]
            let success = info["success"] as? Bool ?? false
            let integrationId = info["integrationId"] as? String ?? ""
            let errorMsg = info["error"] as? String ?? ""

            // Dismiss the Safari sheet — clear pending so onDismiss doesn't override
            pendingOAuthIntegrationId = nil
            oauthURL = nil

            // Switch to the newly connected integration
            if success, !integrationId.isEmpty {
                selectedId = integrationId
                activeTab = .auth
                oauthResultSuccess = true
                oauthResultMessage = langMgr.t("integrations.connected")
            } else {
                oauthResultSuccess = false
                oauthResultMessage = errorMsg.isEmpty ? langMgr.t("integrations.authFailed") : errorMsg
            }

            // Auto-hide banner after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                oauthResultMessage = nil
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.brandCyan)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
            }
            Spacer()
            Text(langMgr.t("integrations.title"))
                .font(.inter(16, weight: .heavy))
                .foregroundColor(.textPrimary)
            Spacer()
            Button {
                if isRootPresentation { dismiss() }
                else { NotificationCenter.default.post(name: .navigateToDashboard, object: nil) }
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.brandCyan)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.phoneBg)
    }

    // MARK: - Dropdown

    private var integrationDropdown: some View {
        VStack(spacing: 0) {
            // Selected row
            Button {
                guard !store.installed.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.18)) { showDropdown.toggle() }
            } label: {
                HStack(spacing: 10) {
                    if let sel = selected {
                        logoView(emoji: sel.config.logoEmoji,
                                 start: sel.config.logoColorStart,
                                 end: sel.config.logoColorEnd, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sel.config.name)
                                .font(.inter(13, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text("\(sel.config.type.label) · \(sel.accountOrganization ?? LanguageManager.shared.t("integrations.auth.notConnected"))")
                                .font(.inter(10))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        stateBadge(sel.connectionState)
                        Image(systemName: showDropdown ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textTertiary)
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(langMgr.t("integrations.noSelection"))
                            .font(.inter(13, weight: .semibold))
                            .foregroundColor(.textTertiary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // List expands directly below the button
            if showDropdown {
                Divider().background(Color.brandCyan.opacity(0.2))

                ForEach(store.installed) { integration in
                    Button {
                        selectedId = integration.id
                        withAnimation(.easeInOut(duration: 0.18)) { showDropdown = false }
                    } label: {
                        HStack(spacing: 10) {
                            logoView(emoji: integration.config.logoEmoji,
                                     start: integration.config.logoColorStart,
                                     end: integration.config.logoColorEnd, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(integration.config.name)
                                    .font(.inter(13, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(integration.config.type.label)
                                    .font(.inter(10))
                                    .foregroundColor(.textTertiary)
                            }
                            Spacer()
                            if integration.id == selectedId {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.brandCyan)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.white.opacity(0.05))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showDropdown = false }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.brandCyan)
                        Text(langMgr.t("integrations.addIntegration"))
                            .font(.inter(13, weight: .semibold))
                            .foregroundColor(.brandCyan)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(showDropdown ? Color.brandCyan.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var accountOrganization: String? { selected?.accountOrganization }

    // MARK: - Tabs

    private var tabBar: some View {
        let isConnected = selected?.connectionState == .connected
        return HStack(spacing: 0) {
            ForEach(IntTab.allCases, id: \.self) { tab in
                let locked = !isConnected && tab != .auth
                Button {
                    guard !locked else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.label)
                            .font(.inter(12, weight: .bold))
                            .foregroundColor(locked ? .textTertiary.opacity(0.35) : activeTab == tab ? .brandCyan : .textTertiary)
                            .padding(.vertical, 11)
                        Rectangle()
                            .fill(activeTab == tab && !locked ? Color.brandCyan : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        if let integration = selected {
            switch activeTab {
            case .auth:
                AuthTabView(integration: integration, onOAuthURL: { url in oauthURL = url })
            case .request:
                RequestTabView(integration: integration, onGoToCollection: { col in
                    NotificationCenter.default.post(
                        name: .integrationCollectionCreated,
                        object: nil,
                        userInfo: ["collectionId": col.id]
                    )
                    // DashboardView receives notification and dismisses the full Settings stack
                })
            case .log:
                LogTabView(integrationId: integration.id)
                    .onAppear { Task { await store.fetchLogs(integrationId: integration.id) } }
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if let err = store.catalogError {
                        Text(err).font(.inter(12)).foregroundColor(.danger)
                            .multilineTextAlignment(.center).padding(.top, 24)
                        Button(langMgr.t("integrations.result.tryAgain")) { Task { await store.fetchCatalog() } }
                            .font(.inter(13, weight: .bold)).foregroundColor(.brandCyan)
                    } else if store.isLoadingCatalog {
                        ProgressView().tint(.brandCyan).padding(.top, 32)
                    } else {
                        Text(langMgr.t("integrations.catalog.browse"))
                            .font(.inter(13)).foregroundColor(.textSecondary)
                            .padding(.top, 24)
                    }
                    CatalogPillView(onInstall: { _, url in oauthURL = url })
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    func logoView(emoji: String, start: String, end: String, size: CGFloat) -> some View {
        Text(emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [Color(hex: start), Color(hex: end)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(size * 0.3)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3)
                    .stroke(Color.brandCyan.opacity(0.28), lineWidth: 1)
            )
    }

    @ViewBuilder
    func stateBadge(_ state: ConnectionState) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.dotColor)
                .frame(width: 6, height: 6)
                .shadow(color: state.dotColor.opacity(0.5), radius: 3)
            Text(state.label)
                .font(.inter(10, weight: .bold))
                .foregroundColor(state.dotColor)
        }
    }
}

// MARK: - Tab enum

enum IntTab: CaseIterable {
    case auth, request, log
    var labelKey: String {
        switch self {
        case .auth:    return "integrations.tab.auth"
        case .request: return "integrations.tab.request"
        case .log:     return "integrations.tab.log"
        }
    }
    var label: String { LanguageManager.shared.t(labelKey) }
}

// MARK: - ConnectionState colors

extension ConnectionState {
    var dotColor: Color {
        switch self {
        case .connected:    return Color(hex: "#4ade80")
        case .expired:      return Color(hex: "#fbbf24")
        case .error:        return Color(hex: "#f87171")
        case .disconnected: return .textTertiary
        }
    }
}

// MARK: - AUTH TAB

struct AuthTabView: View {
    let integration: InstalledIntegration
    var onOAuthURL: ((URL?) -> Void)? = nil
    @ObservedObject private var store = IntegrationStore.shared
    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var showDisconnectConfirm = false
    @State private var showUninstallConfirm = false
    @State private var isConnecting = false
    @State private var isUninstalling = false
    @State private var actionError: String? = nil
    // Credential fields (api-key / basic auth)
    @State private var credUsername = ""
    @State private var credPassword = ""
    @State private var credApiKey = ""
    // Base URL field (for integrations that require it)
    @State private var baseUrl = ""

    private var authType: AuthType { integration.config.authType }

    private var timeFmt: DateFormatter {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }
    private var dateTimeFmt: DateFormatter {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 11) {

                // Auth type badge
                HStack(spacing: 6) {
                    Image(systemName: authType.isOAuth ? "safari" : "key.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(authType.credentialLabel)
                        .font(.inter(11, weight: .bold))
                }
                .foregroundColor(.brandCyan.opacity(0.8))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.brandCyan.opacity(0.1))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)

                if integration.connectionState == .connected {
                    connectedSection
                } else {
                    disconnectedSection
                }

                if let err = actionError {
                    Text(err).font(.inter(11)).foregroundColor(.danger).multilineTextAlignment(.center)
                }

                actionButton(langMgr.t("integrations.auth.uninstall"), style: .danger, loading: isUninstalling) { showUninstallConfirm = true }

                CatalogPillView(onInstall: { _, url in onOAuthURL?(url) })
                    .padding(.top, 8)

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .onAppear {
            baseUrl = integration.baseUrl ?? integration.config.baseUrlDefault ?? ""
        }
        .confirmationDialog(String(format: langMgr.t("integrations.auth.disconnectConfirm"), integration.config.name),
                            isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button(langMgr.t("integrations.auth.disconnect"), role: .destructive) { store.disconnect(id: integration.id) }
            Button(langMgr.t("common.cancel"), role: .cancel) {}
        }
        .confirmationDialog(String(format: langMgr.t("integrations.auth.uninstallConfirm"), integration.config.name),
                            isPresented: $showUninstallConfirm, titleVisibility: .visible) {
            Button(langMgr.t("integrations.auth.uninstall"), role: .destructive) {
                isUninstalling = true
                Task {
                    try? await store.uninstall(integrationId: integration.id)
                    isUninstalling = false
                }
            }
            Button(langMgr.t("common.cancel"), role: .cancel) {}
        }
    }

    // MARK: - Connected section

    @ViewBuilder
    private var connectedSection: some View {
        // Build the list of rows to show so we can set isLast correctly
        let rows: [(String, String, Bool, String?)] = {
            var r: [(String, String, Bool, String?)] = []
            if let email = integration.accountEmail        { r.append((langMgr.t("integrations.auth.user"),         email, false, nil)) }
            if let org   = integration.accountOrganization { r.append((langMgr.t("integrations.auth.organization"), org,   false, nil)) }
            if let date  = integration.lastAuthDate        { r.append((langMgr.t("integrations.auth.lastAuth"),     timeFmt.string(from: date), false, langMgr.t("integrations.auth.active"))) }
            if let tok   = integration.tokenPreview        { r.append((langMgr.t("integrations.auth.token"),        tok,   true,  nil)) }
            if let exp   = integration.tokenExpiry {
                let hrs = max(0, Int(exp.timeIntervalSince(Date()) / 3600))
                r.append((langMgr.t("integrations.auth.expires"), "\(dateTimeFmt.string(from: exp)) · \(hrs) hrs", false, nil))
            }
            return r
        }()

        if !rows.isEmpty {
            infoCard(label: langMgr.t("integrations.auth.account")) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    infoRow(label: row.0, value: row.1, mono: row.2, badge: row.3, isLast: idx == rows.count - 1)
                }
            }
        }

        if authType.isOAuth {
            actionButton(langMgr.t("integrations.auth.reconnectBrowser"), style: .success, loading: isConnecting) { triggerConnect() }
        } else {
            credentialsForm(reconnect: true)
        }
        actionButton(langMgr.t("integrations.auth.disconnect"), style: .ghost) { showDisconnectConfirm = true }
    }

    // MARK: - Disconnected section

    @ViewBuilder
    private var disconnectedSection: some View {
        if authType.isOAuth {
            VStack(spacing: 14) {
                Text(integration.connectionState == .expired ? "🔑" : "🔌").font(.system(size: 36))
                Text(integration.connectionState == .expired ? langMgr.t("integrations.auth.sessionExpired") : langMgr.t("integrations.auth.notConnected"))
                    .font(.inter(15, weight: .bold)).foregroundColor(.textPrimary)
                Text(integration.connectionState == .expired
                     ? langMgr.t("integrations.auth.sessionExpiredMsg")
                     : String(format: langMgr.t("integrations.auth.oauthRedirect"), integration.config.name))
                    .font(.inter(13)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
            }
            .padding(.vertical, 20)

            if integration.config.requiresBaseUrl {
                baseUrlField
            }
            actionButton(langMgr.t("integrations.auth.connectBrowser"), style: .primary, loading: isConnecting) { triggerConnect() }
        } else {
            VStack(spacing: 8) {
                Text("🔑").font(.system(size: 32))
                Text(langMgr.t("integrations.auth.enterCredentials"))
                    .font(.inter(15, weight: .bold)).foregroundColor(.textPrimary)
                Text(langMgr.t("integrations.auth.credentialsNotice"))
                    .font(.inter(12)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
            }
            .padding(.vertical, 12)
            credentialsForm(reconnect: false)
        }
    }

    // MARK: - Base URL field

    private var baseUrlField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((integration.config.baseUrlLabel ?? "Base URL").uppercased())
                .font(.inter(10, weight: .heavy))
                .foregroundColor(.textTertiary)
                .tracking(0.8)
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                TextField(integration.config.baseUrlDefault ?? "https://", text: $baseUrl)
                    .font(.inter(13))
                    .foregroundColor(.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Credentials form (api-key / basic)

    @ViewBuilder
    private func credentialsForm(reconnect: Bool) -> some View {
        if integration.config.requiresBaseUrl {
            baseUrlField
        }

        VStack(spacing: 0) {
            if authType == .apiKey {
                credentialField(icon: "key.fill", label: "API Key", text: $credApiKey, secure: true, isLast: true)
            } else {
                credentialField(icon: "person.fill", label: "Username", text: $credUsername, secure: false, isLast: false)
                Divider().background(Color.white.opacity(0.06))
                credentialField(icon: "lock.fill", label: "Password", text: $credPassword, secure: true, isLast: true)
            }
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        let canSubmit = authType == .apiKey ? !credApiKey.isEmpty : (!credUsername.isEmpty && !credPassword.isEmpty)
        actionButton(reconnect ? langMgr.t("integrations.auth.updateCredentials") : langMgr.t("integrations.auth.connect"),
                     style: .primary,
                     loading: isConnecting,
                     disabled: !canSubmit) {
            triggerConnect()
        }
    }

    @ViewBuilder
    private func credentialField(icon: String, label: String, text: Binding<String>, secure: Bool, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textTertiary)
                .frame(width: 20)
            Text(label)
                .font(.inter(13, weight: .semibold))
                .foregroundColor(.textSecondary)
                .frame(width: 72, alignment: .leading)
            if secure {
                SecureField("••••••••", text: text)
                    .font(.inter(13)).foregroundColor(.textPrimary)
                    .textContentType(label == "Password" ? .password : .none)
                    .autocorrectionDisabled()
            } else {
                TextField("Enter \(label.lowercased())", text: text)
                    .font(.inter(13)).foregroundColor(.textPrimary)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }

    // MARK: - Connect action

    private func triggerConnect() {
        isConnecting = true
        actionError = nil
        Task {
            do {
                let url = try await store.install(
                    integrationId: integration.id,
                    baseUrl: integration.config.requiresBaseUrl ? baseUrl : nil,
                    username: authType == .basic ? credUsername : nil,
                    password: authType == .basic ? credPassword : nil,
                    apiKey: authType == .apiKey ? credApiKey : nil
                )
                if let url {
                    onOAuthURL?(url)
                } else {
                    // Credentials-based: server confirmed active, clear sensitive fields
                    credPassword = ""
                    credApiKey = ""
                }
            } catch {
                actionError = error.localizedDescription
            }
            isConnecting = false
        }
    }

    @ViewBuilder
    private func infoCard(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.inter(10, weight: .heavy))
                .foregroundColor(.textTertiary)
                .tracking(0.8)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)
            content()
        }
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func infoRow(label: String, value: String, mono: Bool = false, badge: String? = nil, actionLabel: String? = nil, isLast: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.inter(12, weight: .bold))
                .foregroundColor(.textTertiary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .inter(13, weight: .semibold))
                .foregroundColor(mono ? Color.brandCyan.opacity(0.85) : .textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let badge = badge {
                Text(badge)
                    .font(.inter(10, weight: .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: "#4ade80").opacity(0.15))
                    .overlay(Capsule().stroke(Color(hex: "#4ade80").opacity(0.28), lineWidth: 1))
                    .clipShape(Capsule())
                    .foregroundColor(Color(hex: "#4ade80"))
            }
            if let action = actionLabel {
                Button(action) {}
                    .font(.inter(11, weight: .bold))
                    .foregroundColor(.brandCyan)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        if !isLast {
            Divider().background(Color.white.opacity(0.05)).padding(.leading, 18)
        }
    }

    enum AuthButtonStyle { case ghost, danger, primary, success }

    @ViewBuilder
    private func actionButton(_ title: String, style: AuthButtonStyle, loading: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if loading {
                    ProgressView()
                        .tint(style == .primary ? .white : style == .success ? Color(hex: "#4ade80") : .brandCyan)
                        .scaleEffect(0.8)
                } else {
                    Text(title)
                        .font(.inter(13, weight: .bold))
                        .foregroundColor(
                            style == .danger  ? Color(hex: "#f87171") :
                            style == .primary ? .white :
                            style == .success ? Color(hex: "#4ade80") :
                            Color.white.opacity(0.6)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .disabled(loading || disabled)
        .opacity(disabled && !loading ? 0.4 : 1)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    style == .danger   ? Color(hex: "#f87171").opacity(0.08) :
                    style == .primary  ? Color.brandBlue.opacity(0.5) :
                    style == .success  ? Color(hex: "#4ade80").opacity(0.08) :
                    Color.white.opacity(0.05)
                )
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        style == .danger   ? Color(hex: "#f87171").opacity(0.2) :
                        style == .primary  ? Color.brandCyan.opacity(0.3) :
                        style == .success  ? Color(hex: "#4ade80").opacity(0.25) :
                        Color.white.opacity(0.1), lineWidth: 1
                    ))
        )
    }
}

// MARK: - CATALOG SHEET

struct CatalogSheetView: View {
    var onInstall: ((String?, URL?) -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langMgr = LanguageManager.shared

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(langMgr.t("integrations.catalog.title"))
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView(showsIndicators: false) {
                    CatalogPillView(onInstall: onInstall, startExpanded: true)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 32)
                }
            }
        }
    }
}

// MARK: - CATALOG PILL

struct CatalogPillView: View {
    var onInstall: ((String?, URL?) -> Void)? = nil
    var startExpanded: Bool = false
    @ObservedObject private var store = IntegrationStore.shared
    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var isOpen = false
    @State private var searchText = ""
    @State private var installingId: String? = nil
    @State private var installError: String? = nil

    private var filteredCatalog: [IntegrationConfig] {
        let notInstalled = store.catalog.filter { cfg in
            !store.installed.contains(where: { $0.id == cfg.id })
        }
        guard !searchText.isEmpty else { return notInstalled }
        return notInstalled.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.type.label.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header pill
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text("＋").font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(langMgr.t("integrations.catalog.pill"))
                            .font(.inter(13, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(langMgr.t("integrations.catalog.browse"))
                            .font(.inter(11))
                            .foregroundColor(.textTertiary)
                    }
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: isOpen ? 0 : 14, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: isOpen ? 0 : 14, style: .continuous))

            // Body
            if isOpen {
                VStack(spacing: 0) {
                    // Search
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(.textTertiary)
                        TextField(langMgr.t("integrations.catalog.search"), text: $searchText)
                            .font(.inter(13))
                            .foregroundColor(.textPrimary)
                            .tint(.brandCyan)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if filteredCatalog.isEmpty {
                        Text(store.installed.count == store.catalog.count ? langMgr.t("integrations.catalog.allInstalled") : langMgr.t("integrations.catalog.noResults"))
                            .font(.inter(12))
                            .foregroundColor(.textTertiary)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(filteredCatalog) { config in
                            Divider().background(Color.white.opacity(0.05))
                            catalogRow(config)
                        }
                    }
                }
                .background(Color.white.opacity(0.03))
                .overlay(
                    Rectangle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear { if startExpanded { isOpen = true } }
    }

    @ViewBuilder
    private func catalogRow(_ config: IntegrationConfig) -> some View {
        HStack(spacing: 11) {
            Text(config.logoEmoji)
                .font(.system(size: 18))
                .frame(width: 38, height: 38)
                .background(LinearGradient(colors: [Color(hex: config.logoColorStart), Color(hex: config.logoColorEnd)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.brandCyan.opacity(0.2), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name).font(.inter(13, weight: .bold)).foregroundColor(.textPrimary)
                Text(config.description).font(.inter(11)).foregroundColor(.textTertiary).lineLimit(2)
                if let err = installError, installingId == config.id {
                    Text(err).font(.inter(10)).foregroundColor(.danger)
                }
            }
            Spacer()
            if installingId == config.id {
                ProgressView().tint(.brandCyan).scaleEffect(0.8)
            } else {
                typeBadge(config.type)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            guard installingId == nil else { return }
            installingId = config.id
            installError = nil
            Task {
                do {
                    let oauthUrl = try await store.install(integrationId: config.id)
                    withAnimation { isOpen = false }
                    onInstall?(config.id, oauthUrl)
                } catch {
                    installError = error.localizedDescription
                }
                installingId = nil
            }
        }
    }

    @ViewBuilder
    private func typeBadge(_ type: IntegrationType) -> some View {
        Text(type.label)
            .font(.inter(10, weight: .heavy))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(type.badgeBackground)
            .overlay(Capsule().stroke(type.badgeBorder, lineWidth: 1))
            .clipShape(Capsule())
            .foregroundColor(type.badgeColor)
    }
}

extension IntegrationType {
    var badgeBackground: Color {
        switch self {
        case .medical:  return Color(hex: "#1e8ae0").opacity(0.18)
        case .legal:    return Color(hex: "#8b5cf6").opacity(0.18)
        case .crm:      return Color(hex: "#f59e0b").opacity(0.15)
        case .finance:  return Color(hex: "#4ade80").opacity(0.15)
        case .custom:   return Color.white.opacity(0.08)
        }
    }
    var badgeBorder: Color {
        switch self {
        case .medical:  return Color(hex: "#38d9f5").opacity(0.25)
        case .legal:    return Color(hex: "#8b5cf6").opacity(0.3)
        case .crm:      return Color(hex: "#f59e0b").opacity(0.28)
        case .finance:  return Color(hex: "#4ade80").opacity(0.28)
        case .custom:   return Color.white.opacity(0.15)
        }
    }
    var badgeColor: Color {
        switch self {
        case .medical:  return Color(hex: "#38d9f5")
        case .legal:    return Color(hex: "#c4b5fd")
        case .crm:      return Color(hex: "#fbbf24")
        case .finance:  return Color(hex: "#4ade80")
        case .custom:   return Color.white.opacity(0.6)
        }
    }
}

// MARK: - Reusable row structs (proper structs = SwiftUI can diff and skip unchanged rows)

struct IntRadioRow: View, Equatable {
    let label: String
    let subtitle: String
    let icon: String?
    let selected: Bool
    let isLast: Bool
    let action: () -> Void

    static func == (l: Self, r: Self) -> Bool {
        l.label == r.label && l.selected == r.selected && l.isLast == r.isLast
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon { Text(icon).font(.system(size: 17)).frame(width: 22) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.inter(13, weight: .semibold)).foregroundColor(.textPrimary)
                    Text(subtitle).font(.inter(11)).foregroundColor(.textTertiary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(selected ? Color.brandCyan : Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if selected {
                        Circle().fill(Color.brandCyan.opacity(0.15)).frame(width: 20, height: 20)
                        Circle().fill(Color.brandCyan).frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        if !isLast { Divider().background(Color.white.opacity(0.05)) }
    }
}

struct IntCheckRow: View, Equatable {
    let label: String
    let subtitle: String
    let checked: Bool
    let isLast: Bool
    let action: () -> Void

    static func == (l: Self, r: Self) -> Bool {
        l.label == r.label && l.checked == r.checked && l.isLast == r.isLast
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.inter(13, weight: .semibold)).foregroundColor(.textPrimary)
                    Text(subtitle).font(.inter(11)).foregroundColor(.textTertiary)
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(checked ? Color.brandCyan : Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if checked {
                        RoundedRectangle(cornerRadius: 6).fill(Color.brandBlue.opacity(0.3)).frame(width: 20, height: 20)
                        Text("✓").font(.system(size: 11, weight: .black)).foregroundColor(.brandCyan)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        if !isLast { Divider().background(Color.white.opacity(0.05)) }
    }
}

// MARK: - REQUEST TAB

struct RequestTabView: View {
    let integration: InstalledIntegration
    var onGoToCollection: ((ScrivanoCollection) -> Void)? = nil
    @ObservedObject private var store = IntegrationStore.shared
    @ObservedObject private var langMgr = LanguageManager.shared

    @State private var mode: RequestMode = .pull
    @State private var pill1Open = false
    @State private var pill2Open = false
    @State private var pill3Open = false
    @State private var selectedTarget: String = ""
    @State private var identifier: String = ""
    @State private var selectedContent: Set<String> = []
    @State private var contentCounts: [String: Int] = [:]   // per-type count, defaults from server
    @State private var destMode: DestMode = .newCollection
    @State private var selectedExistingCollectionId: String = ""
    @State private var selectedPushTarget: String = ""
    @State private var pushCollectionId: String = ""
    @State private var pushSelectedItems: Set<String> = []
    @State private var pushNotePerItem: [String: String] = [:]
    @State private var pushAll: Bool = false
    @State private var pushConfig: SavedPushConfig = SavedPushConfig()
    @State private var pushSuccess = false
    @State private var isRequesting = false
    @State private var pendingPullResponse: PullResponse? = nil
    @State private var pendingCollectionName: String = ""
    @State private var pendingEntityRecordId: String = ""
    @State private var showCollectionNameAlert = false
    @State private var createdCollection: ScrivanoCollection? = nil
    @State private var requestError: String? = nil
    @State private var existingPatientWarning: String? = nil  // collection name when duplicate detected
    // Browse list dropdown
    @State private var availableLists: [BrowseItem] = []
    @State private var listsLoaded = false       // true once browse call completes
    @State private var selectedListId: String = ""
    @State private var isLoadingLists = false
    @State private var showListDropdown = false
    @FocusState private var identifierFocused: Bool

    private var isPull: Bool { mode == .pull }
    private var pullTargets: [IntegrationOption] { integration.config.pullTargets }
    private var pushTargets: [IntegrationOption] { integration.config.pushTargets }
    private var pullContent: [IntegrationOption] { integration.config.pullContent }
    private var listSourceEntity: String? { integration.config.listSourceEntity }

    // Always show list picker when integration uses a list source entity
    private var showListPicker: Bool { listSourceEntity != nil }

    // Only patients that (a) have integration metadata for this integration and
    // (b) still belong to an active collection
    private var pushableItems: [LocalStoredItem] {
        let activeIds = Set(LocalCollectionStore.shared.collections.map(\.id))
        return LocalItemStore.shared.items.filter { item in
            guard let colId = item.collectionId, activeIds.contains(colId),
                  let meta = IntegrationStore.shared.integrationMetadata(for: item.id)
            else { return false }
            return meta.integrationId == integration.id
        }
    }

    @ViewBuilder
    private var pullContentRows: some View {
        ForEach(contentGroups(), id: \.0) { groupName, opts in
            let allSelected = opts.allSatisfy { selectedContent.contains($0.id) }
            Button {
                if allSelected {
                    opts.forEach { selectedContent.remove($0.id) }
                } else {
                    opts.forEach {
                        selectedContent.insert($0.id)
                        if contentCounts[$0.id] == nil { contentCounts[$0.id] = $0.defaultCount ?? 1 }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(allSelected ? .brandCyan : .textTertiary)
                    Text(groupName)
                        .font(.inter(13, weight: .bold)).foregroundColor(.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(opts) { opt in
                HStack(spacing: 0) {
                    IntCheckRow(label: opt.label, subtitle: opt.subtitle,
                                checked: selectedContent.contains(opt.id), isLast: true) {
                        if selectedContent.contains(opt.id) {
                            selectedContent.remove(opt.id)
                        } else {
                            selectedContent.insert(opt.id)
                            if contentCounts[opt.id] == nil { contentCounts[opt.id] = opt.defaultCount ?? 1 }
                        }
                    }
                    if selectedContent.contains(opt.id), opt.defaultCount != nil {
                        HStack(spacing: 0) {
                            Button {
                                let v = contentCounts[opt.id] ?? opt.defaultCount ?? 1
                                if v > 1 { contentCounts[opt.id] = v - 1 }
                            } label: { Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundColor(.brandCyan).frame(width: 28, height: 28) }
                            .buttonStyle(.borderless)
                            Text("\(contentCounts[opt.id] ?? opt.defaultCount ?? 1)")
                                .font(.inter(12, weight: .bold)).foregroundColor(.textPrimary).frame(minWidth: 24, alignment: .center)
                            Button {
                                let v = contentCounts[opt.id] ?? opt.defaultCount ?? 1
                                contentCounts[opt.id] = v + 1
                            } label: { Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundColor(.brandCyan).frame(width: 28, height: 28) }
                            .buttonStyle(.borderless)
                        }
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        .padding(.trailing, 12)
                    }
                }
                if opt.id != opts.last?.id { Divider().background(Color.white.opacity(0.05)) }
            }
            if groupName != contentGroups().last?.0 {
                Divider().background(Color.brandCyan.opacity(0.08)).padding(.top, 4)
            }
        }
    }

    private var availableNoteTypes: [NoteTypeOption] {
        integration.config.noteTypes.isEmpty ? NoteTypeOption.fallback : integration.config.noteTypes
    }

    private var pushOptionsSummary: String {
        var parts: [String] = [pushConfig.noteTypeDisplay]
        if integration.config.supportedPushFormats.contains("pdf") {
            parts.append(pushConfig.pushFormat == "pdf" ? langMgr.t("integrations.push.pdf") : langMgr.t("integrations.push.plainText"))
        }
        if integration.config.supportedNoteStatuses.contains("draft") {
            parts.append(pushConfig.noteStatus == "draft" ? langMgr.t("integrations.push.draft") : langMgr.t("integrations.push.final"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var pushOptionsPicker: some View {
        // Note Type section
        sectionHeader(langMgr.t("integrations.push.noteType"))
        ForEach(availableNoteTypes) { option in
            Button {
                pushConfig.noteTypeCode = option.id
                pushConfig.noteTypeDisplay = option.display
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.display)
                            .font(.inter(13, weight: .semibold)).foregroundColor(.textPrimary)
                        Text(option.id).font(.inter(11)).foregroundColor(.textTertiary)
                    }
                    Spacer()
                    if option.id == pushConfig.noteTypeCode {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.brandCyan)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if option.id != availableNoteTypes.last?.id { Divider().background(Color.white.opacity(0.05)) }
        }

        // Format section — only shown if integration supports PDF
        let supportsPDF = integration.config.supportedPushFormats.contains("pdf")
        if supportsPDF {
            Divider().background(Color.brandCyan.opacity(0.08)).padding(.top, 4)
            sectionHeader(langMgr.t("integrations.push.format"))
            optionToggleRow(label: langMgr.t("integrations.push.plainText"), subtitle: langMgr.t("integrations.push.plainTextSub"), selected: pushConfig.pushFormat == "text") {
                pushConfig.pushFormat = "text"
            }
            Divider().background(Color.white.opacity(0.05))
            optionToggleRow(label: langMgr.t("integrations.push.pdf"), subtitle: langMgr.t("integrations.push.pdfSub"), selected: pushConfig.pushFormat == "pdf") {
                pushConfig.pushFormat = "pdf"
            }
        }

        // Status section — only shown if integration supports draft
        let supportsDraft = integration.config.supportedNoteStatuses.contains("draft")
        if supportsDraft {
            Divider().background(Color.brandCyan.opacity(0.08)).padding(.top, 4)
            sectionHeader(langMgr.t("integrations.push.status"))
            optionToggleRow(label: langMgr.t("integrations.push.final"), subtitle: langMgr.t("integrations.push.finalSub"), selected: pushConfig.noteStatus == "final") {
                pushConfig.noteStatus = "final"
            }
            Divider().background(Color.white.opacity(0.05))
            optionToggleRow(label: langMgr.t("integrations.push.draft"), subtitle: langMgr.t("integrations.push.draftSub"), selected: pushConfig.noteStatus == "draft") {
                pushConfig.noteStatus = "draft"
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.inter(10, weight: .heavy)).foregroundColor(.textTertiary).tracking(0.8)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionToggleRow(label: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.inter(13, weight: .semibold)).foregroundColor(.textPrimary)
                    Text(subtitle).font(.inter(11)).foregroundColor(.textTertiary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.brandCyan)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pushItemSummary: String {
        if pushAll {
            let multiNoteCount = itemsInPushCollection.filter {
                LocalNoteStore.shared.notes(for: $0.id).count >= 2
            }.count
            return multiNoteCount > 0 ? String(format: langMgr.t("integrations.push.selectNoteFor"), multiNoteCount) : langMgr.t("integrations.push.allNotes")
        }
        let count = pushSelectedItems.count
        if count == 0 { return langMgr.t("integrations.push.selectItems") }
        if count == 1, let item = LocalItemStore.shared.items.first(where: { pushSelectedItems.contains($0.id) }) {
            return item.name
        }
        return String(format: langMgr.t("integrations.push.itemsSelected"), count)
    }

    // "Patient List" is only selectable when a list is chosen; otherwise only Specific Patient
    private func isEntityDisabled(_ opt: IntegrationOption) -> Bool {
        guard listSourceEntity != nil && listsLoaded && availableLists.isEmpty else { return false }
        return !opt.requiresId  // disable non-specific entities when no lists available
    }

    private var selectedListName: String {
        availableLists.first(where: { $0.id == selectedListId })?.name ?? ""
    }

    private var pill1Summary: String {
        isPull
            ? (pullTargets.first(where: { $0.id == selectedTarget })?.label ?? "Select option")
            : (pushTargets.first(where: { $0.id == selectedPushTarget })?.label ?? "Select option")
    }
    private var pill2Summary: String {
        let checked = pullContent.filter { selectedContent.contains($0.id) }.map(\.label)
        return checked.isEmpty ? langMgr.t("integrations.pull.namesOnly") : checked.joined(separator: ", ")
    }
    private var pill3Summary: String {
        if isPull {
            if destMode == .newCollection { return langMgr.t("integrations.pull.newCollection") }
            let name = LocalCollectionStore.shared.collections.first(where: { $0.id == selectedExistingCollectionId })?.name
            return name ?? langMgr.t("integrations.pull.existingCollection")
        }
        return langMgr.t("integrations.push.selectCollection")
    }
    private var canSubmit: Bool {
        guard integration.connectionState == .connected else { return false }
        if isPull {
            guard !selectedTarget.isEmpty else { return false }
            // Require list selection only when lists are actually available
            if showListPicker && !isLoadingLists && !availableLists.isEmpty && selectedListId.isEmpty { return false }
            // If specific entity, require identifier
            if pullTargets.first(where: { $0.id == selectedTarget })?.requiresId == true {
                if identifier.isEmpty { return false }
            }
            // If existing collection chosen, require selection
            if destMode == .existing && selectedExistingCollectionId.isEmpty { return false }
            return true
        }
        if pushAll {
            guard !pushCollectionId.isEmpty else { return false }
            // All push-all items with 2+ notes need a note chosen
            let pushableInCollection = itemsInPushCollection.filter {
                IntegrationStore.shared.integrationMetadata(for: $0.id)?.integrationId == integration.id &&
                !LocalNoteStore.shared.notes(for: $0.id).isEmpty
            }
            return pushableInCollection.allSatisfy { item in
                let noteCount = LocalNoteStore.shared.notes(for: item.id).count
                return noteCount <= 1 || pushNotePerItem[item.id] != nil
            }
        }
        if pushSelectedItems.isEmpty { return false }
        // All selected items with 2+ notes need a note chosen
        return pushSelectedItems.allSatisfy { itemId in
            let noteCount = LocalNoteStore.shared.notes(for: itemId).count
            return noteCount <= 1 || pushNotePerItem[itemId] != nil
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    segmentedControl
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    if isPull {
                        // List picker — always shown when integration uses a list source entity
                        if showListPicker { listDropdownPill }

                        pill(icon: "📥", title: langMgr.t("integrations.pull.source"), summary: pill1Summary,
                             isOpen: pill1Open, disabled: false) {
                            let opening = !pill1Open
                            pill1Open = opening; pill2Open = false; pill3Open = false; showListDropdown = false
                        } content: {
                            ForEach(pullTargets) { opt in
                                let disabled = isEntityDisabled(opt)
                                IntRadioRow(label: opt.label, subtitle: opt.subtitle, icon: nil,
                                            selected: selectedTarget == opt.id,
                                            isLast: opt.id == pullTargets.last?.id) {
                                    if !disabled { selectedTarget = opt.id; if !opt.requiresId { identifier = "" } }
                                }
                                .opacity(disabled ? 0.35 : 1)
                                if selectedTarget == opt.id && opt.requiresId { identifierField }
                            }
                        }

                        pill(icon: "📋", title: langMgr.t("integrations.pull.content"), summary: pill2Summary,
                             isOpen: pill2Open, disabled: false) {
                            let opening = !pill2Open; pill1Open = false; pill2Open = opening; pill3Open = false; showListDropdown = false
                        } content: {
                            pullContentRows
                        }

                    } else {
                        // Pill 1: Collection
                        let selColName = LocalCollectionStore.shared.collections.first(where: { $0.id == pushCollectionId })?.name ?? langMgr.t("integrations.push.selectCollection")
                        pill(icon: "📁", title: langMgr.t("integrations.push.collection"), summary: selColName,
                             isOpen: pill1Open, disabled: false) {
                            pill1Open = !pill1Open; pill2Open = false; pill3Open = false
                        } content: { pushCollectionPicker }

                        // Pill 2: Items — shown whenever a collection is selected
                        if !pushCollectionId.isEmpty {
                            pill(icon: "👤", title: langMgr.t("integrations.push.items"), summary: pushItemSummary,
                                 isOpen: pill2Open, disabled: false) {
                                pill2Open = !pill2Open; pill1Open = false; pill3Open = false
                            } content: { pushItemPicker }
                        }

                        // Pill 3: Options (note type + format + status) — always shown in push mode
                        pill(icon: "⚙️", title: langMgr.t("integrations.push.options"), summary: pushOptionsSummary,
                             isOpen: pill3Open, disabled: false) {
                            pill3Open = !pill3Open; pill1Open = false; pill2Open = false
                        } content: { pushOptionsPicker }
                    }

                    if isPull {
                        pill(icon: "📁", title: langMgr.t("integrations.pull.destination"), summary: pill3Summary,
                             isOpen: pill3Open, disabled: false) {
                            let opening = !pill3Open
                            pill1Open = false; pill2Open = false; pill3Open = opening; showListDropdown = false
                        } content: {
                            IntRadioRow(label: langMgr.t("integrations.pull.newCollection"),
                                        subtitle: "\(integration.config.name) · \(shortDate())",
                                        icon: "✨", selected: destMode == .newCollection, isLast: false) {
                                destMode = .newCollection
                            }
                            let collections = LocalCollectionStore.shared.collections
                            IntRadioRow(label: langMgr.t("integrations.pull.existingCollection"),
                                        subtitle: collections.isEmpty ? langMgr.t("integrations.pull.noCollections") : langMgr.t("integrations.pull.addToExisting"),
                                        icon: "📁", selected: destMode == .existing, isLast: destMode != .existing) {
                                if !collections.isEmpty { destMode = .existing }
                            }
                            .opacity(collections.isEmpty ? 0.4 : 1)
                            if destMode == .existing {
                                Divider().background(Color.white.opacity(0.05))
                                VStack(spacing: 0) {
                                    ForEach(collections) { col in
                                        Button { selectedExistingCollectionId = col.id } label: {
                                            HStack(spacing: 10) {
                                                Text("📁").font(.system(size: 15))
                                                Text(col.name)
                                                    .font(.inter(13, weight: .semibold))
                                                    .foregroundColor(.textPrimary)
                                                Spacer()
                                                if col.id == selectedExistingCollectionId {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundColor(.brandCyan)
                                                }
                                            }
                                            .padding(.horizontal, 20).padding(.vertical, 11)
                                        }
                                        .buttonStyle(.plain)
                                        if col.id != collections.last?.id {
                                            Divider().background(Color.white.opacity(0.04)).padding(.leading, 20)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Spacer().frame(height: 110)
                }
            }
            .onChange(of: identifierFocused) { focused in
                if focused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation { proxy.scrollTo("identifierField", anchor: .center) }
                    }
                }
            }
            } // ScrollViewReader

            if !identifierFocused {
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color.phoneBg.opacity(0), Color.phoneBg], startPoint: .top, endPoint: .bottom)
                        .frame(height: 32)
                    Button { submitRequest() } label: {
                        Group {
                            if isRequesting { ProgressView().tint(.white) }
                            else { Text(langMgr.t("integrations.request.submit")).font(.inter(15, weight: .bold)).foregroundColor(.white) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(LinearGradient(colors: [Color(hex: "#1e8ae0"), Color(hex: "#0d5faa")],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequesting || !canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .background(Color.phoneBg)
            }

            // MARK: - Centered overlays

            if let existingCol = existingPatientWarning {
                Color.black.opacity(0.65).ignoresSafeArea()
                    .transition(.opacity)
                VStack {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Color(hex: "#fbbf24"))
                            .shadow(color: Color(hex: "#fbbf24").opacity(0.5), radius: 12)
                        VStack(spacing: 6) {
                            Text(langMgr.t("integrations.alert.patientExists"))
                                .font(.inter(18, weight: .heavy))
                                .foregroundColor(.textPrimary)
                            Text(String(format: langMgr.t("integrations.alert.patientExistsMsg"), identifier, existingCol))
                                .font(.inter(13))
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        VStack(spacing: 10) {
                            Button {
                                // Add to the existing collection
                                if let response = pendingPullResponse,
                                   let col = LocalCollectionStore.shared.collections.first(where: { $0.name == existingCol }) {
                                    let saved = IntegrationStore.shared.persistPullResult(
                                        response,
                                        integrationId: integration.id,
                                        collectionName: "",
                                        entityRecordId: pendingEntityRecordId.isEmpty ? nil : pendingEntityRecordId,
                                        existingCollectionId: col.id
                                    )
                                    pendingPullResponse = nil
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        existingPatientWarning = nil
                                        createdCollection = saved
                                    }
                                }
                            } label: {
                                Text(String(format: langMgr.t("integrations.alert.addToExisting"), existingCol))
                                    .font(.inter(14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(LinearGradient(colors: [Color(hex: "#1e8ae0"), Color(hex: "#0d5faa")],
                                                               startPoint: .leading, endPoint: .trailing))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            Button {
                                // Create new anyway — go to name alert
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { existingPatientWarning = nil }
                                pendingCollectionName = integration.config.name
                                showCollectionNameAlert = true
                            } label: {
                                Text(langMgr.t("integrations.alert.createNew"))
                                    .font(.inter(13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .buttonStyle(.plain)
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    existingPatientWarning = nil
                                    pendingPullResponse = nil
                                }
                            } label: {
                                Text(langMgr.t("common.cancel"))
                                    .font(.inter(13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(28)
                    .background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(hex: "#fbbf24").opacity(0.35), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.4), radius: 20)
                    .padding(.horizontal, 28)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            if let col = createdCollection {
                Color.black.opacity(0.65).ignoresSafeArea()
                    .transition(.opacity)
                VStack {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Color(hex: "#4ade80"))
                            .shadow(color: Color(hex: "#4ade80").opacity(0.6), radius: 12)
                        VStack(spacing: 6) {
                            Text(langMgr.t(destMode == .existing ? "integrations.result.itemsAdded" : "integrations.result.collectionCreated"))
                                .font(.inter(18, weight: .heavy))
                                .foregroundColor(.textPrimary)
                            Text(String(format: langMgr.t("integrations.result.collectionReady"), col.name))
                                .font(.inter(13))
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        VStack(spacing: 10) {
                            Button { onGoToCollection?(col) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.right.circle.fill")
                                    Text(langMgr.t("integrations.result.goToDashboard"))
                                        .font(.inter(14, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(LinearGradient(colors: [Color(hex: "#1e8ae0"), Color(hex: "#0d5faa")],
                                                           startPoint: .leading, endPoint: .trailing))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            Button { createdCollection = nil } label: {
                                Text(langMgr.t("integrations.result.stayHere"))
                                    .font(.inter(13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(28)
                    .background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(hex: "#4ade80").opacity(0.3), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.4), radius: 20)
                    .padding(.horizontal, 28)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            // Pull item warnings (e.g. 403 on labs in sandbox)
            if !store.lastPullWarnings.isEmpty && createdCollection != nil {
                // shown alongside success — tap dismiss on success card clears both
            }

            if pushSuccess {
                Color.black.opacity(0.65).ignoresSafeArea()
                    .transition(.opacity)
                VStack {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Color(hex: "#4ade80"))
                            .shadow(color: Color(hex: "#4ade80").opacity(0.6), radius: 12)
                        VStack(spacing: 6) {
                            Text(langMgr.t("integrations.result.notePushed"))
                                .font(.inter(18, weight: .heavy))
                                .foregroundColor(.textPrimary)
                            Text(langMgr.t("integrations.result.notePushedMsg"))
                                .font(.inter(13))
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        Button { pushSuccess = false } label: {
                            Text(langMgr.t("integrations.result.done"))
                                .font(.inter(14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(LinearGradient(colors: [Color(hex: "#1e8ae0"), Color(hex: "#0d5faa")],
                                                           startPoint: .leading, endPoint: .trailing))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(28)
                    .background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(hex: "#4ade80").opacity(0.3), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.4), radius: 20)
                    .padding(.horizontal, 28)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            if let err = requestError {
                Color.black.opacity(0.65).ignoresSafeArea()
                    .transition(.opacity)
                VStack {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.danger)
                            .shadow(color: Color.danger.opacity(0.6), radius: 12)
                        VStack(spacing: 6) {
                            Text(langMgr.t("integrations.result.failed"))
                                .font(.inter(18, weight: .heavy))
                                .foregroundColor(.textPrimary)
                            Text(err)
                                .font(.inter(13))
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        VStack(spacing: 10) {
                            Button { requestError = nil; submitRequest() } label: {
                                Text(langMgr.t("integrations.result.tryAgain"))
                                    .font(.inter(14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.danger.opacity(0.75))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            Button { requestError = nil } label: {
                                Text(langMgr.t("common.dismiss"))
                                    .font(.inter(13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(28)
                    .background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.danger.opacity(0.35), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.4), radius: 20)
                    .padding(.horizontal, 28)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .onAppear {
            selectedTarget = pullTargets.first?.id ?? ""
            selectedPushTarget = pushTargets.first?.id ?? ""
            selectedContent = []
            pushConfig = IntegrationStore.shared.loadPushConfig(integrationId: integration.id)
            if let entity = listSourceEntity {
                fetchLists(entityId: entity)
            }
        }
        .onChange(of: pushConfig) { newConfig in
            IntegrationStore.shared.savePushConfig(newConfig, integrationId: integration.id)
        }
        .alert(langMgr.t("integrations.alert.nameCollection"), isPresented: $showCollectionNameAlert) {
            TextField(langMgr.t("integrations.alert.collectionPlaceholder"), text: $pendingCollectionName)
                .autocorrectionDisabled()
            Button(langMgr.t("integrations.alert.save")) {
                if let response = pendingPullResponse {
                    let name = pendingCollectionName.isEmpty ? integration.config.name : pendingCollectionName
                    let col = IntegrationStore.shared.persistPullResult(
                        response,
                        integrationId: integration.id,
                        collectionName: name,
                        entityRecordId: pendingEntityRecordId.isEmpty ? nil : pendingEntityRecordId
                    )
                    pendingPullResponse = nil
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { createdCollection = col }
                }
            }
            Button(langMgr.t("common.cancel"), role: .cancel) { pendingPullResponse = nil }
        } message: {
            Text(langMgr.t("integrations.alert.saveMsg"))
        }
    }

    // MARK: - Push pickers

    // All items in the selected collection
    private var itemsInPushCollection: [LocalStoredItem] {
        LocalItemStore.shared.items.filter { $0.collectionId == pushCollectionId }
    }

    // Collections that have at least one pushable item (has integration metadata)
    private var pushableCollections: [ScrivanoCollection] {
        let activeIds = Set(pushableItems.compactMap(\.collectionId))
        return LocalCollectionStore.shared.collections.filter { activeIds.contains($0.id) }
    }

    @ViewBuilder
    private var pushCollectionPicker: some View {
        if pushableCollections.isEmpty {
            Text(langMgr.t("integrations.push.noCollections"))
                .font(.inter(12)).foregroundColor(.textTertiary)
                .padding(.horizontal, 16).padding(.vertical, 14)
        } else {
            ForEach(pushableCollections) { col in
                Button {
                    if pushCollectionId != col.id {
                        pushCollectionId = col.id; pushSelectedItems = []; pushNotePerItem = [:]; pushAll = false
                    }
                    pill1Open = false
                } label: {
                    HStack(spacing: 10) {
                        Text("📁").font(.system(size: 15))
                        Text(col.name).font(.inter(13, weight: .semibold)).foregroundColor(.textPrimary)
                        Spacer()
                        if col.id == pushCollectionId {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.brandCyan)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if col.id != pushableCollections.last?.id { Divider().background(Color.white.opacity(0.05)) }
            }
            Divider().background(Color.brandCyan.opacity(0.1)).padding(.top, 4)
            // Toggleable push-all
            Button {
                if !pushCollectionId.isEmpty { pushAll.toggle(); pushSelectedItems = []; pushNotePerItem = [:]; pill1Open = false }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.doc.fill").font(.system(size: 14)).foregroundColor(.brandCyan)
                    Text(langMgr.t("integrations.push.allNotes"))
                        .font(.inter(13, weight: .semibold)).foregroundColor(.brandCyan)
                    Spacer()
                    if pushAll {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundColor(.brandCyan)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .opacity(pushCollectionId.isEmpty ? 0.35 : 1)
        }
    }

    @ViewBuilder
    private var pushItemPicker: some View {
        let items = pushAll ? itemsInPushCollection.filter {
            IntegrationStore.shared.integrationMetadata(for: $0.id)?.integrationId == integration.id &&
            !LocalNoteStore.shared.notes(for: $0.id).isEmpty
        } : itemsInPushCollection

        if items.isEmpty {
            Text(pushAll ? langMgr.t("integrations.push.noPushable") : langMgr.t("integrations.push.noItems"))
                .font(.inter(12)).foregroundColor(.textTertiary)
                .padding(.horizontal, 16).padding(.vertical, 14)
        } else {
            if pushAll {
                Text(langMgr.t("integrations.push.selectNoteInstructions"))
                    .font(.inter(11)).foregroundColor(.textTertiary)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
            }
            ForEach(items) { item in
                let noteCount = LocalNoteStore.shared.notes(for: item.id).count
                let hasMeta = IntegrationStore.shared.integrationMetadata(for: item.id)?.integrationId == integration.id
                let canPush = noteCount > 0 && hasMeta
                let isChecked = pushAll ? true : pushSelectedItems.contains(item.id)

                VStack(spacing: 0) {
                    Button {
                        guard !pushAll else { return }  // non-interactive in push-all mode
                        guard canPush else { return }
                        if isChecked {
                            pushSelectedItems.remove(item.id)
                            pushNotePerItem.removeValue(forKey: item.id)
                        } else {
                            pushSelectedItems.insert(item.id)
                            if noteCount == 1 {
                                pushNotePerItem[item.id] = LocalNoteStore.shared.notes(for: item.id).first?.id
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if pushAll {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 17)).foregroundColor(.brandCyan.opacity(0.6))
                            } else {
                                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 17))
                                    .foregroundColor(isChecked ? .brandCyan : .textTertiary)
                            }
                            Text("👤").font(.system(size: 15))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.inter(13, weight: .semibold))
                                    .foregroundColor(canPush ? .textPrimary : .textTertiary)
                                HStack(spacing: 6) {
                                    Text(noteCount == 0 ? langMgr.t("integrations.push.noNotes") : "\(noteCount) note\(noteCount == 1 ? "" : "s")")
                                        .font(.inter(11)).foregroundColor(.textTertiary)
                                    if let meta = IntegrationStore.shared.integrationMetadata(for: item.id),
                                       meta.integrationId == integration.id {
                                        Text("·").font(.inter(11)).foregroundColor(.textTertiary)
                                        Text(String(format: langMgr.t("integrations.push.pulledDate"), relativeDate(meta.lastSynced)))
                                            .font(.inter(11)).foregroundColor(.textTertiary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(canPush ? 1 : 0.35)

                    // Inline note picker when item is checked/selected and has 2+ notes
                    if isChecked && noteCount >= 2 {
                        let notes = LocalNoteStore.shared.notes(for: item.id)
                        VStack(spacing: 0) {
                            Divider().background(Color.white.opacity(0.04))
                            ForEach(notes) { note in
                                let noteSelected = pushNotePerItem[item.id] == note.id
                                Button {
                                    pushNotePerItem[item.id] = note.id
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: noteSelected ? "largecircle.fill.circle" : "circle")
                                            .font(.system(size: 14))
                                            .foregroundColor(noteSelected ? .brandCyan : .textTertiary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(note.label)
                                                .font(.inter(12, weight: .semibold)).foregroundColor(.textPrimary)
                                            Text(note.text.prefix(60) + (note.text.count > 60 ? "…" : ""))
                                                .font(.inter(10)).foregroundColor(.textTertiary).lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.leading, 44).padding(.trailing, 16).padding(.vertical, 9)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if note.id != notes.last?.id {
                                    Divider().background(Color.white.opacity(0.04)).padding(.leading, 44)
                                }
                            }
                        }
                        .background(Color.white.opacity(0.03))
                    }
                }

                if item.id != items.last?.id { Divider().background(Color.white.opacity(0.05)) }
            }
        }
    }

    // MARK: - List dropdown pill

    private var listDropdownPill: some View {
        VStack(spacing: 0) {
            Button {
                let opening = !showListDropdown
                withAnimation(.easeInOut(duration: 0.15)) {
                    showListDropdown = opening; pill1Open = false; pill2Open = false; pill3Open = false
                }
            } label: {
                HStack(spacing: 10) {
                    if isLoadingLists {
                        ProgressView().scaleEffect(0.7).tint(.brandCyan)
                            .frame(width: 20, height: 20)
                    } else {
                        Text("📋").font(.system(size: 16))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(langMgr.t("integrations.pull.list")).font(.inter(13, weight: .bold)).foregroundColor(.textPrimary)
                        Text(selectedListId.isEmpty ? langMgr.t("integrations.pull.selectList") : selectedListName)
                            .font(.inter(11)).foregroundColor(.textTertiary)
                    }
                    Spacer()
                    Image(systemName: showListDropdown ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if showListDropdown {
                Divider().background(Color.white.opacity(0.07))
                if availableLists.isEmpty {
                    Text(isLoadingLists ? langMgr.t("integrations.pull.loading") : langMgr.t("integrations.pull.noLists"))
                        .font(.inter(12)).foregroundColor(.textTertiary)
                        .padding(.vertical, 14)
                } else {
                    ForEach(availableLists) { item in
                        Button {
                            selectedListId = item.id
                            withAnimation { showListDropdown = false }
                        } label: {
                            HStack {
                                Text(item.name).font(.inter(13)).foregroundColor(.textPrimary)
                                Spacer()
                                if item.id == selectedListId {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.brandCyan)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        if item.id != availableLists.last?.id {
                            Divider().background(Color.white.opacity(0.05))
                        }
                    }
                }
            }
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(
            selectedListId.isEmpty ? Color.brandCyan.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 18).padding(.bottom, 16)
    }

    private func fetchLists(entityId: String) {
        isLoadingLists = true
        Task {
            if let items = try? await IntegrationStore.shared.browse(
                integrationId: integration.id, entityId: entityId) {
                availableLists = items
                // Pre-select first list if available
                if selectedListId.isEmpty { selectedListId = items.first?.id ?? "" }
                // If no lists, force-select the specific entity (requires_id)
                if items.isEmpty, let specificEntity = pullTargets.first(where: { $0.requiresId }) {
                    selectedTarget = specificEntity.id
                }
            }
            listsLoaded = true
            isLoadingLists = false
        }
    }

    // MARK: - Segmented control

    private var segmentedControl: some View {
        let modes = RequestMode.allCases.filter { $0 == .pull || integration.config.canPush }
        return HStack(spacing: 3) {
            ForEach(modes, id: \.self) { m in
                Button {
                    mode = m
                    resetSelections()
                } label: {
                    Text(m.label)
                        .font(.inter(13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundColor(mode == m ? .white : .textTertiary)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(mode == m ? Color.brandBlue.opacity(0.35) : Color.clear)
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(mode == m ? Color.brandCyan.opacity(0.3) : Color.clear, lineWidth: 1))
                        )
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Pill

    @ViewBuilder
    private func pill(icon: String, title: String, summary: String,
                      isOpen: Bool, disabled: Bool,
                      onTap: @escaping () -> Void,
                      @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Text(icon).font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.inter(13, weight: .bold)).foregroundColor(.textPrimary)
                        Text(summary).font(.inter(11)).foregroundColor(.textTertiary)
                    }
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .background(Color.white.opacity(0.06))
            .disabled(disabled).opacity(disabled ? 0.35 : 1)
            .clipShape(RoundedRectangle(cornerRadius: isOpen ? 0 : 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: isOpen ? 0 : 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1))

            if isOpen {
                VStack(spacing: 0) { content() }
                    .background(Color.white.opacity(0.03))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 18).padding(.bottom, 16)
    }

    // MARK: - Identifier field

    private var identifierField: some View {
        let label = pullTargets.first(where: { $0.id == selectedTarget })?.idLabel
            ?? integration.config.identifierLabel ?? "ID"
        return VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(.inter(10, weight: .heavy)).foregroundColor(Color.brandCyan.opacity(0.7)).tracking(0.8)
            TextField("Enter \(label)…", text: $identifier)
                .font(.inter(14, weight: .medium)).foregroundColor(.textPrimary).tint(.brandCyan)
                .focused($identifierFocused)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(Color.black.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.brandCyan.opacity(0.3), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.brandBlue.opacity(0.06))
        .id("identifierField")
    }

    // MARK: - Helpers

    private func resetSelections() {
        selectedTarget = pullTargets.first?.id ?? ""
        selectedPushTarget = pushTargets.first?.id ?? ""
        selectedContent = []
        contentCounts = [:]
        identifier = ""
        destMode = .newCollection
        selectedExistingCollectionId = ""
        selectedListId = availableLists.first?.id ?? ""
        requestError = nil
        createdCollection = nil
        existingPatientWarning = nil
        pushCollectionId = ""
        pushSelectedItems = []
        pushNotePerItem = [:]
        pushAll = false
        pushSuccess = false
    }

    // Returns content types grouped, preserving server order within each group
    private func contentGroups() -> [(String, [IntegrationOption])] {
        var seen: Set<String> = []
        var order: [String] = []
        var map: [String: [IntegrationOption]] = [:]
        for opt in pullContent {
            let g = opt.group ?? "Other"
            if !seen.contains(g) { seen.insert(g); order.append(g) }
            map[g, default: []].append(opt)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func submitRequest() {
        guard canSubmit else { return }
        createdCollection = nil
        requestError = nil
        existingPatientWarning = nil
        isRequesting = true
        Task {
            do {
                if isPull {
                    // Build counts map — only for selected items that have a defaultCount
                    let counts: [String: Int] = Dictionary(uniqueKeysWithValues:
                        pullContent
                            .filter { selectedContent.contains($0.id) && $0.defaultCount != nil }
                            .map { ($0.id, contentCounts[$0.id] ?? $0.defaultCount ?? 1) }
                    )
                    let response = try await IntegrationStore.shared.pull(
                        integrationId: integration.id,
                        entityId: selectedTarget,
                        listId: showListPicker && !selectedListId.isEmpty ? selectedListId : nil,
                        entityRecordId: identifier.isEmpty ? nil : identifier,
                        content: Array(selectedContent),
                        counts: counts.isEmpty ? nil : counts,
                        collectionName: nil
                    )
                    if response.success == false {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            requestError = response.message ?? LanguageManager.shared.t("integrations.result.failed")
                        }
                    } else if response.collection?.items?.isEmpty != false {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            requestError = LanguageManager.shared.t("integrations.result.noItems")
                        }
                    } else if response.collection?.items?.isEmpty == false {
                        if destMode == .existing, !selectedExistingCollectionId.isEmpty {
                            let col = IntegrationStore.shared.persistPullResult(
                                response,
                                integrationId: integration.id,
                                collectionName: "",
                                entityRecordId: identifier.isEmpty ? nil : identifier,
                                existingCollectionId: selectedExistingCollectionId
                            )
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { createdCollection = col }
                        } else if destMode == .newCollection,
                                  let existingCol = IntegrationStore.shared.existingCollectionName(
                                    for: response, entityRecordId: identifier.isEmpty ? nil : identifier) {
                            // Patient already exists — warn before creating a duplicate
                            pendingPullResponse = response
                            pendingEntityRecordId = identifier
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                existingPatientWarning = existingCol
                            }
                        } else {
                            pendingPullResponse = response
                            pendingCollectionName = integration.config.name
                            pendingEntityRecordId = identifier
                            showCollectionNameAlert = true
                        }
                    }
                } else {
                    let delayNs = UInt64(integration.config.rateLimitMs ?? 0) * 1_000_000
                    let maxLen = integration.config.maxNoteLength

                    func pushNote(itemId: String, note: LocalNoteEntry) async throws {
                        if let max = maxLen, note.text.count > max {
                            throw NSError(domain: "push", code: 400, userInfo: [
                                NSLocalizedDescriptionKey: String(format: LanguageManager.shared.t("integrations.result.noteExceedsLimit"), note.label, max, note.text.count)
                            ])
                        }
                        _ = try await IntegrationStore.shared.push(
                            integrationId: integration.id,
                            itemId: itemId,
                            noteText: note.text,
                            noteTitle: note.label,
                            noteTypeCode: pushConfig.noteTypeCode,
                            noteTypeDisplay: pushConfig.noteTypeDisplay,
                            noteStatus: pushConfig.noteStatus,
                            pushFormat: pushConfig.pushFormat
                        )
                        if delayNs > 0 { try await Task.sleep(nanoseconds: delayNs) }
                    }

                    if pushAll {
                        for item in itemsInPushCollection {
                            let notes = LocalNoteStore.shared.notes(for: item.id)
                            guard !notes.isEmpty,
                                  IntegrationStore.shared.integrationMetadata(for: item.id) != nil
                            else { continue }
                            let noteId = pushNotePerItem[item.id] ?? notes.first?.id ?? ""
                            guard let note = notes.first(where: { $0.id == noteId }) else { continue }
                            try await pushNote(itemId: item.id, note: note)
                        }
                    } else {
                        for itemId in pushSelectedItems {
                            let notes = LocalNoteStore.shared.notes(for: itemId)
                            guard !notes.isEmpty else { continue }
                            let noteId = pushNotePerItem[itemId] ?? notes.first?.id ?? ""
                            guard let note = notes.first(where: { $0.id == noteId }) else { continue }
                            try await pushNote(itemId: itemId, note: note)
                        }
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { pushSuccess = true }
                }
            } catch {
                let msg = error.localizedDescription
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { requestError = msg }
                IntegrationStore.shared.appendLog(IntegrationLogEntry(
                    id: UUID().uuidString, integrationId: integration.id,
                    integrationName: integration.config.name,
                    action: isPull ? .pull : .push,
                    targetLabel: isPull ? selectedTarget : selectedPushTarget,
                    contentLabels: Array(selectedContent),
                    destinationName: nil, resultSummary: nil,
                    status: .error, errorMessage: msg, date: Date()
                ))
            }
            isRequesting = false
        }
    }

    private func shortDate() -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: Date())
    }

    private func relativeDate(_ date: Date) -> String {
        let lm = LanguageManager.shared
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return lm.t("integrations.date.justNow") }
        if seconds < 3600 { return String(format: lm.t("integrations.date.minutesAgo"), seconds / 60) }
        if seconds < 86400 { return String(format: lm.t("integrations.date.hoursAgo"), seconds / 3600) }
        return String(format: lm.t("integrations.date.daysAgo"), seconds / 86400)
    }
}

enum RequestMode: CaseIterable {
    case pull, push
    var label: String { self == .pull ? LanguageManager.shared.t("integrations.request.pull") : LanguageManager.shared.t("integrations.request.push") }
}

enum DestMode { case newCollection, existing }

// MARK: - LOG TAB

struct LogTabView: View {
    let integrationId: String
    @ObservedObject private var store = IntegrationStore.shared
    @ObservedObject private var langMgr = LanguageManager.shared

    private var entries: [IntegrationLogEntry] { store.logEntries(for: integrationId) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if entries.isEmpty {
                    VStack(spacing: 12) {
                        Text("📋").font(.system(size: 36)).padding(.top, 48)
                        Text(langMgr.t("integrations.log.empty"))
                            .font(.inter(14, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(langMgr.t("integrations.log.emptyHint"))
                            .font(.inter(12))
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            logRow(entry)
                            if entry.id != entries.last?.id {
                                Divider().background(Color.white.opacity(0.05))
                            }
                        }
                    }
                    .background(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.09), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 18)
                }
                Spacer().frame(height: 40)
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func logRow(_ entry: IntegrationLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(entry.status == .success ? Color(hex: "#4ade80") : Color(hex: "#f87171"))
                .frame(width: 7, height: 7)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(rowTitle(entry))
                    .font(.inter(12.5, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Text(rowSubtitle(entry))
                    .font(.inter(10.5))
                    .foregroundColor(.textTertiary)
                    .lineSpacing(3)
                if let err = entry.errorMessage {
                    Text(err)
                        .font(.inter(10.5))
                        .foregroundColor(Color(hex: "#f87171"))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(relativeDate(entry.date))
                    .font(.inter(10))
                    .foregroundColor(.textTertiary)
                Text(entry.action == .pull ? langMgr.t("integrations.request.pull") : langMgr.t("integrations.request.push"))
                    .font(.inter(9, weight: .heavy))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(entry.action == .pull
                                ? Color.brandCyan.opacity(0.15)
                                : Color(hex: "#8b5cf6").opacity(0.15))
                    .overlay(Capsule().stroke(
                        entry.action == .pull ? Color.brandCyan.opacity(0.25) : Color(hex: "#8b5cf6").opacity(0.25),
                        lineWidth: 1))
                    .clipShape(Capsule())
                    .foregroundColor(entry.action == .pull ? .brandCyan : Color(hex: "#c4b5fd"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func rowTitle(_ e: IntegrationLogEntry) -> String {
        let content = e.contentLabels.isEmpty ? "" : " · \(e.contentLabels.joined(separator: ", "))"
        return "\(e.targetLabel)\(content)"
    }

    private func rowSubtitle(_ e: IntegrationLogEntry) -> String {
        var parts: [String] = []
        if let dest = e.destinationName { parts.append("→ \(dest)") }
        if let summary = e.resultSummary { parts.append(summary) }
        return parts.joined(separator: " · ")
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return langMgr.t("integrations.date.justNow") }
        if diff < 3600 { return String(format: langMgr.t("integrations.date.minutesAgo"), diff / 60) }
        if diff < 86400 { return String(format: langMgr.t("integrations.date.hoursAgo"), diff / 3600) }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Safari WebView for OAuth

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
