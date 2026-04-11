import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var showHelp = false
    @State private var showCredits = false
    @State private var showAutomation = false
    @State private var showPrompts = false
    @State private var showRecorder = false
    @State private var showAccount = false
    @EnvironmentObject var lockMgr: SecurityLockManager
    @State private var showPinSetup = false
    @State private var showDisableConfirm = false
    @State private var showLogout = false
    @State private var showDeleteAccount = false
    @State private var showLog = false
    @State private var showTrash = false
    @State private var trashCount = 0
    @State private var showBackup = false
    @State private var showAPIKey = false

    var user: User? { auth.currentUser }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.phoneBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Fixed top bar
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.brandCyan)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.07))
                                .clipShape(Circle())
                        }
                        Spacer()
                        Text("Settings")
                            .font(.inter(16, weight: .heavy))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Button("?") { showHelp = true }
                            .font(.inter(14, weight: .bold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                    ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Account hero
                        accountHero
                            .padding(.horizontal, 14)
                            .padding(.bottom, 6)

                        // Content section
                        SectionLabel(text: "Content")
                        settingsGroup {
                            NavRow(icon: "✦", iconColor: Color(hex: "#a78bfa"), title: "Prompt Database", subtitle: "Manage AI prompt library") { showPrompts = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "🤖", iconColor: .brandBlue, title: "Automation", subtitle: "Auto-process pipeline stages") { showAutomation = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "🗑", iconColor: .danger, title: "Recycle Bin",
                                   subtitle: trashCount > 0 ? "\(trashCount) item\(trashCount == 1 ? "" : "s") in trash" : "Empty") { showTrash = true }
                        }

                        // System section
                        SectionLabel(text: "System")
                        settingsGroup {
                            NavRow(icon: "🎙️", iconColor: .stageMedia, title: "Recorder Settings", subtitle: "Format · Quality · Bit depth") { showRecorder = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "📋", iconColor: .brandCyan, title: "Connection Log", subtitle: "Server connection history") { showLog = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            ToggleRow(icon: "🔒", iconColor: .textSecondary, title: "Security Lock", subtitle: "Passcode lock",
                                      isOn: Binding(
                                          get: { lockMgr.isEnabled },
                                          set: { newVal in
                                              if newVal { showPinSetup = true }
                                              else { showDisableConfirm = true }
                                          }
                                      ))
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "☁️", iconColor: .brandBlue, title: "Backup", subtitle: "Export · Restore data") { showBackup = true }
                        }

                        // Account section
                        SectionLabel(text: "Account")
                        settingsGroup {
                            NavRow(icon: "🚪", iconColor: .textTertiary, title: "Logout", subtitle: nil) { showLogout = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "⚠️", iconColor: .danger, title: "Delete Account", subtitle: "Permanent action", isDanger: true) { showDeleteAccount = true }
                        }

                        Spacer().frame(height: 40)
                    }
                    }
                    .refreshable { await auth.refreshUser() }
                }

                // Logout confirm card
                if showLogout {
                    Color.black.opacity(0.65).ignoresSafeArea().zIndex(10)
                    VStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 30))
                                .foregroundColor(.textTertiary)
                                .shadow(color: Color.white.opacity(0.15), radius: 10)

                            Text("Log Out")
                                .font(.inter(16, weight: .heavy))
                                .foregroundColor(.textPrimary)

                            Text("You'll need to sign in again to access your account.")
                                .font(.inter(13))
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 10) {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showLogout = false }
                                } label: {
                                    Text("Cancel")
                                        .font(.inter(14, weight: .semibold))
                                        .foregroundColor(.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Color.white.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showLogout = false }
                                    auth.forceLogout()
                                } label: {
                                    Text("Log Out")
                                        .font(.inter(14, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Color.danger.opacity(0.85))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                        }
                        .padding(24)
                        .background(Color(hex: "#081221"))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.1), lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.4), radius: 20)
                        .padding(.horizontal, 24)
                        Spacer()
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(11)
                }

                // Delete account confirm card
                if showDeleteAccount {
                    Color.black.opacity(0.65).ignoresSafeArea().zIndex(10)
                    VStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.badge.minus")
                                .font(.system(size: 30))
                                .foregroundColor(.danger)
                                .shadow(color: Color.danger.opacity(0.7), radius: 10)

                            Text("Delete Account")
                                .font(.inter(16, weight: .heavy))
                                .foregroundColor(.textPrimary)

                            Text("This is permanent and cannot be undone. All your data will be deleted.")
                                .font(.inter(13))
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 10) {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteAccount = false }
                                } label: {
                                    Text("Cancel")
                                        .font(.inter(14, weight: .semibold))
                                        .foregroundColor(.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Color.white.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteAccount = false }
                                    // TODO: implement account deletion
                                } label: {
                                    Text("Delete Account")
                                        .font(.inter(14, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Color.danger.opacity(0.85))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                        }
                        .padding(24)
                        .background(Color(hex: "#081221"))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.danger.opacity(0.35), lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: Color.danger.opacity(0.15), radius: 20)
                        .padding(.horizontal, 24)
                        Spacer()
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(11)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showLogout)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDeleteAccount)
            .navigationBarHidden(true)
        }
        .fullScreenCover(isPresented: $showHelp) { HelpView() }
        .fullScreenCover(isPresented: $showCredits) { CreditsView() }
        .fullScreenCover(isPresented: $showAutomation) { AutomationView() }
        .fullScreenCover(isPresented: $showPrompts) { PromptsView(context: .browse) }
        .fullScreenCover(isPresented: $showRecorder) { RecorderSettingsView() }
        .fullScreenCover(isPresented: $showLog) { ConnectionLogView() }
        .fullScreenCover(isPresented: $showTrash) {
            TrashView()
                .onDisappear { trashCount = TrashStore.shared.count }
        }
        .task {
            trashCount = TrashStore.shared.count
            await auth.refreshUser()
        }
        .sheet(isPresented: $showPinSetup) {
            PinSetupView().environmentObject(lockMgr)
        }
        .sheet(isPresented: $showDisableConfirm) {
            PinVerifyView().environmentObject(lockMgr)
        }
        .fullScreenCover(isPresented: $showBackup) { BackupView() }
        .fullScreenCover(isPresented: $showAPIKey) { APIKeyView().environmentObject(auth) }
    }

    // MARK: - Account Hero
    private var accountHero: some View {
        VStack(spacing: 12) {
            // Row 1: avatar + name/email + plan badge
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: "#081526"), Color(hex: "#030c1a")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 50, height: 50)
                        .overlay(Circle().stroke(Color.brandCyan.opacity(0.45), lineWidth: 2))
                        .shadow(color: Color.brandCyan.opacity(0.5), radius: 10)
                    Image("ScrivanoLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .shadow(color: Color.brandCyan.opacity(0.8), radius: 6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(user?.firstName ?? "User")
                        .font(.inter(15, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(user?.email ?? "")
                        .font(.inter(11))
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                Text((user?.plan ?? "free").uppercased())
                    .font(.inter(11, weight: .heavy))
                    .foregroundColor(.brandCyan)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(
                        LinearGradient(colors: [Color.brandBlue.opacity(0.28), Color.brandCyan.opacity(0.15)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.brandCyan.opacity(0.38), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }

            // Row 2: credit boxes
            HStack(spacing: 7) {
                creditBox(label: "Paid Credits", value: String(format: "%.2f", user?.credit ?? 0), isPaid: true)
                creditBox(label: "Free Credits", value: String(format: "%.0f", user?.freeCredit ?? 0), isPaid: false)
            }

            // Row 3: Plans button
            Button { showCredits = true } label: {
                Text("＋  Plans")
                    .font(.inter(12, weight: .heavy))
                    .tracking(0.3)
                    .foregroundColor(.brandCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [Color.brandBlue.opacity(0.35), Color.brandCyan.opacity(0.15)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandCyan.opacity(0.30), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Conditionally show API key button when user has BYOK plan
            if auth.currentUser?.hasBYOK == true {
                Button { showAPIKey = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: auth.hasOpenAIKey ? "checkmark.shield.fill" : "key.fill")
                            .font(.system(size: 13))
                        Text(auth.hasOpenAIKey ? "API Key Connected" : "Connect API Key")
                            .font(.inter(12, weight: .heavy))
                            .tracking(0.3)
                    }
                    .foregroundColor(Color(hex: "#22c55e"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#22c55e").opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#22c55e").opacity(0.35), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .blueBorderCard()
    }

    private func creditBox(label: String, value: String, isPaid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.inter(18, weight: .heavy))
                .foregroundColor(isPaid ? Color(hex: "#f59e0b") : .textPrimary)
            Text(label)
                .font(.inter(9, weight: .bold))
                .foregroundColor(.textQuaternary)
                .tracking(0.7)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isPaid ? Color(hex: "#f59e0b").opacity(0.09) : Color.white.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(isPaid ? Color(hex: "#f59e0b").opacity(0.24) : Color.white.opacity(0.10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}

// MARK: - ConnectionLogView

struct ConnectionLogView: View {
    @ObservedObject private var logger = AppLogger.shared
    @Environment(\.dismiss) var dismiss
    @State private var showCopied = false

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Bar
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
                    Text("Connection Log")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = logger.allText
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
                        } label: {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(showCopied ? Color(hex: "#34d399") : .textSecondary)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.07))
                                .clipShape(Circle())
                        }
                        Button { logger.clear() } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.danger)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.07))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }

                // Stats bar
                HStack(spacing: 10) {
                    logStatPill("Total", "\(logger.entries.count)", .textTertiary)
                    logStatPill("OK",   "\(logger.entries.filter { $0.level == .success }.count)", Color(hex: "#34d399"))
                    logStatPill("ERR",  "\(logger.entries.filter { $0.level == .error }.count)",   Color(hex: "#f87171"))
                    logStatPill("WARN", "\(logger.entries.filter { $0.level == .warning }.count)", Color(hex: "#fbbf24"))
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(Color.white.opacity(0.02))

                if logger.entries.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 32)).foregroundColor(.textQuaternary)
                        Text("No log entries yet")
                            .font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                        Text("Transcription activity will appear here")
                            .font(.inter(12)).foregroundColor(.textQuaternary)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(logger.entries.reversed()) { entry in
                                logEntryRow(entry)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func logEntryRow(_ entry: AppLogger.Entry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timeString)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.textQuaternary)
                .frame(width: 80, alignment: .leading)
                .padding(.top, 1)
            Text(entry.level.rawValue)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(entry.level.color)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(entry.level.badge)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 36).padding(.top, 1)
            Text(entry.message)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(entry.level.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(entry.level == .error   ? Color(hex: "#f87171").opacity(0.04) :
                    entry.level == .success ? Color(hex: "#34d399").opacity(0.03) : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1) }
    }

    private func logStatPill(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.inter(9, weight: .bold)).foregroundColor(.textQuaternary).tracking(0.5).textCase(.uppercase)
            Text(value).font(.inter(11, weight: .heavy)).foregroundColor(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
