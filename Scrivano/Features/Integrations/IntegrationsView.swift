import SwiftUI
import SafariServices

struct IntegrationsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var store = IntegrationStore.shared

    @State private var selectedId: String? = nil
    @State private var showDropdown = false
    @State private var activeTab: IntTab = .request
    @State private var oauthURL: URL? = nil
    @State private var oauthResultMessage: String? = nil
    @State private var oauthResultSuccess: Bool = true

    private var selected: InstalledIntegration? {
        guard let id = selectedId else { return store.installed.first }
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
            if showDropdown {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { showDropdown = false } }
            }
        }
        .onAppear {
            if selectedId == nil { selectedId = store.installed.first?.id }
            Task {
                await store.fetchCatalog()
                // Load full config (with pull targets & content types) for selected integration
                if let id = selectedId ?? store.installed.first?.id {
                    try? await store.fetchDetail(integrationId: id)
                }
            }
        }
        .onChange(of: store.installed.count) { _ in
            if selectedId == nil { selectedId = store.installed.first?.id }
        }
        .onChange(of: selectedId) { id in
            // Fetch full config whenever user switches integration
            if let id { Task { try? await store.fetchDetail(integrationId: id) } }
        }
        .sheet(item: $oauthURL) { url in
            SafariView(url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .integrationOAuthCallback)) { note in
            let info = note.userInfo ?? [:]
            let success = info["success"] as? Bool ?? false
            let integrationId = info["integrationId"] as? String ?? ""
            let errorMsg = info["error"] as? String ?? ""

            // Dismiss the Safari sheet
            oauthURL = nil

            // Switch to the newly connected integration
            if success, !integrationId.isEmpty {
                selectedId = integrationId
                activeTab = .auth
                oauthResultSuccess = true
                oauthResultMessage = "Connected successfully"
            } else {
                oauthResultSuccess = false
                oauthResultMessage = errorMsg.isEmpty ? "Authentication failed" : errorMsg
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
            Text("Integrations")
                .font(.inter(16, weight: .heavy))
                .foregroundColor(.textPrimary)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.phoneBg)
    }

    // MARK: - Dropdown

    private var integrationDropdown: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Selected row (or placeholder when nothing installed)
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
                                Text("\(sel.config.type.label) · \(sel.accountOrganization ?? "Not connected")")
                                    .font(.inter(10))
                                    .foregroundColor(.textTertiary)
                            }
                            Spacer()
                            stateBadge(sel.connectionState)
                            Image(systemName: showDropdown ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.textTertiary)
                        } else {
                            Image(systemName: "link")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textTertiary)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("No integration selected")
                                .font(.inter(13, weight: .semibold))
                                .foregroundColor(.textTertiary)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(showDropdown ? Color.brandCyan.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .zIndex(10)

            // Dropdown list
            if showDropdown {
                VStack(spacing: 0) {
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
                                    Text("✓")
                                        .font(.inter(13, weight: .bold))
                                        .foregroundColor(.brandCyan)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        Divider().background(Color.white.opacity(0.05))
                    }
                    // Add integration — always at the bottom of the dropdown
                    CatalogPillView(onInstall: { url in oauthURL = url })
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.brandCyan.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 18)
                .padding(.top, 60)
                .zIndex(20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .zIndex(100)
    }

    private var accountOrganization: String? { selected?.accountOrganization }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(IntTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.label)
                            .font(.inter(12, weight: .bold))
                            .foregroundColor(activeTab == tab ? .brandCyan : .textTertiary)
                            .padding(.vertical, 11)
                        Rectangle()
                            .fill(activeTab == tab ? Color.brandCyan : Color.clear)
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
                RequestTabView(integration: integration)
            case .log:
                LogTabView(integrationId: integration.id)
                    .onAppear { Task { await store.fetchLogs(integrationId: integration.id) } }
            }
        } else {
            Spacer()
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
    var label: String {
        switch self {
        case .auth:    return "Auth"
        case .request: return "Request"
        case .log:     return "Log"
        }
    }
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

                actionButton("Uninstall", style: .ghost, loading: isUninstalling) { showUninstallConfirm = true }

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .onAppear {
            baseUrl = integration.baseUrl ?? integration.config.baseUrlDefault ?? ""
        }
        .confirmationDialog("Disconnect \(integration.config.name)?",
                            isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { store.disconnect(id: integration.id) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Uninstall \(integration.config.name)?",
                            isPresented: $showUninstallConfirm, titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) {
                isUninstalling = true
                Task {
                    try? await store.uninstall(integrationId: integration.id)
                    isUninstalling = false
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Connected section

    @ViewBuilder
    private var connectedSection: some View {
        infoCard(label: "Account") {
            if let email = integration.accountEmail {
                infoRow(label: "User", value: email)
            }
            if let org = integration.accountOrganization {
                infoRow(label: "Organization", value: org, isLast: false)
            }
            if let date = integration.lastAuthDate {
                infoRow(label: "Last auth", value: timeFmt.string(from: date), badge: "Active", isLast: true)
            }
        }
        if integration.tokenPreview != nil || integration.tokenExpiry != nil {
            infoCard(label: "Token") {
                if let preview = integration.tokenPreview {
                    infoRow(label: "Bearer", value: preview, mono: true, isLast: integration.tokenExpiry == nil)
                }
                if let expiry = integration.tokenExpiry {
                    let hrs = max(0, Int(expiry.timeIntervalSince(Date()) / 3600))
                    infoRow(label: "Expires", value: "\(dateTimeFmt.string(from: expiry)) · \(hrs) hrs", isLast: true)
                }
            }
        }
        if authType.isOAuth {
            actionButton("Reconnect via Browser", style: .ghost, loading: isConnecting) { triggerConnect() }
        } else {
            credentialsForm(reconnect: true)
        }
        actionButton("Disconnect", style: .danger) { showDisconnectConfirm = true }
    }

    // MARK: - Disconnected section

    @ViewBuilder
    private var disconnectedSection: some View {
        if authType.isOAuth {
            VStack(spacing: 14) {
                Text(integration.connectionState == .expired ? "🔑" : "🔌").font(.system(size: 36))
                Text(integration.connectionState == .expired ? "Session Expired" : "Not Connected")
                    .font(.inter(15, weight: .bold)).foregroundColor(.textPrimary)
                Text(integration.connectionState == .expired
                     ? "Your session has expired. Reconnect to continue."
                     : "You'll be taken to \(integration.config.name)'s login page.")
                    .font(.inter(13)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
            }
            .padding(.vertical, 20)

            if integration.config.requiresBaseUrl {
                baseUrlField
            }
            actionButton("Connect via Browser", style: .primary, loading: isConnecting) { triggerConnect() }
        } else {
            VStack(spacing: 8) {
                Text("🔑").font(.system(size: 32))
                Text("Enter Credentials")
                    .font(.inter(15, weight: .bold)).foregroundColor(.textPrimary)
                Text("Credentials are sent securely to the server and never stored on device.")
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
        actionButton(reconnect ? "Update Credentials" : "Connect",
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
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            content()
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func infoRow(label: String, value: String, mono: Bool = false, badge: String? = nil, actionLabel: String? = nil, isLast: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.inter(11, weight: .bold))
                .foregroundColor(.textTertiary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 11, design: .monospaced) : .inter(12.5, weight: .semibold))
                .foregroundColor(mono ? Color.brandCyan.opacity(0.85) : .textSecondary)
                .lineLimit(1)
            Spacer()
            if let badge = badge {
                Text(badge)
                    .font(.inter(10, weight: .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 2)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        if !isLast {
            Divider().background(Color.white.opacity(0.05)).padding(.leading, 16)
        }
    }

    enum AuthButtonStyle { case ghost, danger, primary }

    @ViewBuilder
    private func actionButton(_ title: String, style: AuthButtonStyle, loading: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if loading { ProgressView().tint(style == .primary ? .white : .brandCyan).scaleEffect(0.8) }
                else {
                    Text(title).font(.inter(13, weight: .bold))
                        .foregroundColor(style == .danger ? Color(hex: "#f87171") : style == .primary ? .white : Color.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
        }
        .disabled(loading || disabled)
        .opacity(disabled && !loading ? 0.4 : 1)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(style == .danger ? Color(hex: "#f87171").opacity(0.08) :
                      style == .primary ? Color.brandBlue.opacity(0.5) : Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(style == .danger ? Color(hex: "#f87171").opacity(0.2) :
                            style == .primary ? Color.brandCyan.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1))
        )
    }
}

// MARK: - CATALOG PILL

struct CatalogPillView: View {
    var onInstall: ((URL?) -> Void)? = nil
    @ObservedObject private var store = IntegrationStore.shared
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
                        Text("Add integration")
                            .font(.inter(13, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("Browse available integrations")
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
                        TextField("Search integrations…", text: $searchText)
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
                        Text(store.installed.count == store.catalog.count ? "All integrations installed" : "No results")
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
                    onInstall?(oauthUrl)
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

    @State private var mode: RequestMode = .pull
    @State private var pill1Open = false
    @State private var pill2Open = false
    @State private var pill3Open = false
    @State private var selectedTarget: String = ""
    @State private var identifier: String = ""
    @State private var selectedContent: Set<String> = []
    @State private var destMode: DestMode = .newCollection
    @State private var selectedPushTarget: String = ""
    @State private var isRequesting = false
    // Browse list dropdown
    @State private var availableLists: [BrowseItem] = []
    @State private var selectedListId: String = ""
    @State private var isLoadingLists = false
    @State private var showListDropdown = false

    private var isPull: Bool { mode == .pull }
    private var pullTargets: [IntegrationOption] { integration.config.pullTargets }
    private var pushTargets: [IntegrationOption] { integration.config.pushTargets }
    private var pullContent: [IntegrationOption] { integration.config.pullContent }
    private var listSourceEntity: String? { integration.config.listSourceEntity }

    private var selectedEntity: IntegrationOption? {
        pullTargets.first(where: { $0.id == selectedTarget })
    }
    private var selectedListName: String {
        availableLists.first(where: { $0.id == selectedListId })?.name ?? "Select a list"
    }

    private var pill1Summary: String {
        isPull
            ? (pullTargets.first(where: { $0.id == selectedTarget })?.label ?? "Select option")
            : (pushTargets.first(where: { $0.id == selectedPushTarget })?.label ?? "Select option")
    }
    private var pill2Summary: String {
        selectedContent.isEmpty ? "None — list only"
            : pullContent.filter { selectedContent.contains($0.id) }.map(\.label).joined(separator: ", ")
    }
    private var pill3Summary: String {
        isPull ? (destMode == .newCollection ? "New collection" : "Existing collection") : "Select collection"
    }
    private var canSubmit: Bool {
        guard integration.connectionState == .connected else { return false }
        if isPull {
            guard !selectedTarget.isEmpty else { return false }
            if listSourceEntity != nil { return !selectedListId.isEmpty }
            return true
        }
        return !selectedPushTarget.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    segmentedControl
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    // List dropdown — shown above "What to pull" when config has list_source_entity
                    if isPull, let _ = listSourceEntity {
                        listDropdownPill
                    }

                    pill(icon: isPull ? "📥" : "📤",
                         title: isPull ? "What to pull" : "What to push",
                         summary: pill1Summary, isOpen: pill1Open, disabled: false) {
                        pill1Open.toggle()
                    } content: {
                        if isPull {
                            ForEach(pullTargets) { opt in
                                IntRadioRow(label: opt.label, subtitle: opt.subtitle, icon: nil,
                                            selected: selectedTarget == opt.id,
                                            isLast: opt.id == pullTargets.last?.id) {
                                    selectedTarget = opt.id
                                    if !opt.requiresId { identifier = "" }
                                }
                                if selectedTarget == opt.id && opt.requiresId {
                                    identifierField
                                }
                            }
                        } else {
                            ForEach(pushTargets) { opt in
                                IntRadioRow(label: opt.label, subtitle: opt.subtitle, icon: nil,
                                            selected: selectedPushTarget == opt.id,
                                            isLast: opt.id == pushTargets.last?.id) {
                                    selectedPushTarget = opt.id
                                }
                            }
                        }
                    }

                    pill(icon: "📋", title: "Pull content", summary: pill2Summary,
                         isOpen: pill2Open, disabled: !isPull) {
                        if isPull { pill2Open.toggle() }
                    } content: {
                        ForEach(pullContent) { opt in
                            IntCheckRow(label: opt.label, subtitle: opt.subtitle,
                                        checked: selectedContent.contains(opt.id),
                                        isLast: opt.id == pullContent.last?.id) {
                                if selectedContent.contains(opt.id) { selectedContent.remove(opt.id) }
                                else { selectedContent.insert(opt.id) }
                            }
                        }
                    }

                    pill(icon: isPull ? "📁" : "📤",
                         title: isPull ? "Destination" : "Source",
                         summary: pill3Summary, isOpen: pill3Open, disabled: false) {
                        pill3Open.toggle()
                    } content: {
                        if isPull {
                            IntRadioRow(label: "New collection",
                                        subtitle: "\(integration.config.name) · \(shortDate())",
                                        icon: "✨", selected: destMode == .newCollection, isLast: false) {
                                destMode = .newCollection
                            }
                            IntRadioRow(label: "Existing collection",
                                        subtitle: "Choose from your collections",
                                        icon: "📁", selected: destMode == .existing, isLast: true) {
                                destMode = .existing
                            }
                        } else {
                            HStack(spacing: 12) {
                                Text("📂").font(.system(size: 17))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Select collection").font(.inter(13, weight: .semibold)).foregroundColor(.textPrimary)
                                    Text("Choose which collection to push from").font(.inter(11)).foregroundColor(.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 14)).foregroundColor(.textTertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }
                    }

                    Spacer().frame(height: 110)
                }
            }

            VStack(spacing: 0) {
                LinearGradient(colors: [Color.phoneBg.opacity(0), Color.phoneBg], startPoint: .top, endPoint: .bottom)
                    .frame(height: 32)
                Button { submitRequest() } label: {
                    Group {
                        if isRequesting { ProgressView().tint(.white) }
                        else { Text("Request").font(.inter(15, weight: .bold)).foregroundColor(.white) }
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
        .onAppear {
            selectedTarget = pullTargets.first?.id ?? ""
            selectedPushTarget = pushTargets.first?.id ?? ""
            if let entity = listSourceEntity {
                fetchLists(entityId: entity)
            }
        }
    }

    // MARK: - List dropdown pill

    private var listDropdownPill: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showListDropdown.toggle() }
            } label: {
                HStack(spacing: 10) {
                    if isLoadingLists {
                        ProgressView().scaleEffect(0.7).tint(.brandCyan)
                    } else {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.brandCyan)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("List").font(.inter(11, weight: .heavy)).foregroundColor(.textTertiary).tracking(0.8)
                        Text(selectedListId.isEmpty ? "Select a list" : selectedListName)
                            .font(.inter(13, weight: .semibold))
                            .foregroundColor(selectedListId.isEmpty ? .textTertiary : .textPrimary)
                    }
                    Spacer()
                    Image(systemName: showListDropdown ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if showListDropdown {
                Divider().background(Color.white.opacity(0.07))
                if availableLists.isEmpty {
                    Text(isLoadingLists ? "Loading…" : "No lists available")
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
                if selectedListId.isEmpty { selectedListId = items.first?.id ?? "" }
            }
            isLoadingLists = false
        }
    }

    // MARK: - Segmented control

    private var segmentedControl: some View {
        HStack(spacing: 3) {
            ForEach(RequestMode.allCases, id: \.self) { m in
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
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(Color.black.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.brandCyan.opacity(0.3), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.brandBlue.opacity(0.06))
    }

    // MARK: - Helpers

    private func resetSelections() {
        selectedTarget = pullTargets.first?.id ?? ""
        selectedPushTarget = pushTargets.first?.id ?? ""
        selectedContent = []
        identifier = ""
        destMode = .newCollection
        selectedListId = availableLists.first?.id ?? ""
    }

    private func submitRequest() {
        guard canSubmit else { return }
        isRequesting = true
        Task {
            do {
                if isPull {
                    let collectionName = selectedListName == "Select a list"
                        ? "\(integration.config.name) — \(shortDate())"
                        : "\(selectedListName) — \(shortDate())"
                    _ = try await IntegrationStore.shared.pull(
                        integrationId: integration.id,
                        entityId: selectedTarget,
                        listId: listSourceEntity != nil ? selectedListId : nil,
                        entityRecordId: identifier.isEmpty ? nil : identifier,
                        content: Array(selectedContent),
                        collectionName: collectionName
                    )
                } else {
                    _ = try await IntegrationStore.shared.push(
                        integrationId: integration.id,
                        noteText: "Note pushed from Scrivano",
                        noteTitle: "Scrivano Note",
                        metadata: identifier.isEmpty ? [:] : ["mrn": identifier]
                    )
                }
            } catch {
                IntegrationStore.shared.appendLog(IntegrationLogEntry(
                    id: UUID().uuidString, integrationId: integration.id,
                    integrationName: integration.config.name,
                    action: isPull ? .pull : .push,
                    targetLabel: isPull ? selectedTarget : selectedPushTarget,
                    contentLabels: Array(selectedContent),
                    destinationName: nil, resultSummary: nil,
                    status: .error, errorMessage: error.localizedDescription, date: Date()
                ))
            }
            isRequesting = false
        }
    }

    private func shortDate() -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: Date())
    }
}

enum RequestMode: CaseIterable {
    case pull, push
    var label: String { self == .pull ? "Pull" : "Push" }
}

enum DestMode { case newCollection, existing }

// MARK: - LOG TAB

struct LogTabView: View {
    let integrationId: String
    @ObservedObject private var store = IntegrationStore.shared

    private var entries: [IntegrationLogEntry] { store.logEntries(for: integrationId) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if entries.isEmpty {
                    VStack(spacing: 12) {
                        Text("📋").font(.system(size: 36)).padding(.top, 48)
                        Text("No requests yet")
                            .font(.inter(14, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("Pull and push activity will appear here")
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
                Text(entry.action == .pull ? "Pull" : "Push")
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
        let diff = Date().timeIntervalSince(date)
        if diff < 3600 { return "\(Int(diff/60))m ago" }
        if diff < 86400 { return "\(Int(diff/3600))h ago" }
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
