import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var showHelp = false
    @State private var showCredits = false
    @State private var showAutomation = false
    @State private var showPrompts = false
    @State private var showRecorder = false
    @State private var showPlayer = false
    @State private var showAccount = false
    @State private var securityLock = false
    @State private var showLogout = false
    @State private var showDeleteAccount = false

    var user: User? { auth.currentUser }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.phoneBg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Bar
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
                            NavRow(icon: "🗑", iconColor: .danger, title: "Clear All Data", subtitle: nil) {}
                        }

                        // Recording section
                        SectionLabel(text: "Recording")
                        settingsGroup {
                            NavRow(icon: "🎙️", iconColor: .stageMedia, title: "Recorder Settings", subtitle: "Format · Quality · Bit depth") { showRecorder = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "▶️", iconColor: .stageText, title: "Player Settings", subtitle: "Rewind & forward timing") { showPlayer = true }
                        }

                        // System section
                        SectionLabel(text: "System")
                        settingsGroup {
                            NavRow(icon: "📋", iconColor: .brandCyan, title: "Connection Log", subtitle: "Server connection history") {}
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            ToggleRow(icon: "🔒", iconColor: .textSecondary, title: "Security Lock", subtitle: "Passcode lock", isOn: $securityLock)
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "☁️", iconColor: .brandBlue, title: "Backup", subtitle: "Export all data") {}
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "📥", iconColor: .brandBlue, title: "Restore Backup", subtitle: nil) {}
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
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showHelp) { HelpView() }
        .sheet(isPresented: $showCredits) { CreditsView() }
        .sheet(isPresented: $showAutomation) { AutomationView() }
        .sheet(isPresented: $showPrompts) { PromptsView(context: .browse) }
        .sheet(isPresented: $showRecorder) { RecorderSettingsView() }
        .sheet(isPresented: $showPlayer) { PlayerSettingsView() }
        .confirmationDialog("Logout", isPresented: $showLogout) {
            Button("Logout", role: .destructive) { auth.logout() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete Account", isPresented: $showDeleteAccount, titleVisibility: .visible) {
            Button("Delete My Account", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is permanent and cannot be undone. All your data will be deleted.")
        }
    }

    // MARK: - Account Hero
    private var accountHero: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.brandBlue.opacity(0.3), Color.brandNavy.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                        .overlay(Circle().stroke(Color.brandBlue.opacity(0.3), lineWidth: 1))
                    Text(String(user?.firstName.prefix(1).uppercased() ?? "?"))
                        .font(.inter(20, weight: .heavy))
                        .foregroundColor(.textPrimary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(user?.firstName ?? "User")
                        .font(.inter(15, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(user?.email ?? "")
                        .font(.inter(12))
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                Text((user?.plan ?? "free").uppercased())
                    .font(.inter(9, weight: .heavy))
                    .tracking(1)
                    .foregroundColor(.brandCyan)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.brandBlue.opacity(0.2))
                    .overlay(Capsule().stroke(Color.brandCyan.opacity(0.3), lineWidth: 1))
                    .clipShape(Capsule())
            }

            // Credits
            HStack(spacing: 7) {
                creditBox(label: "Paid Credits", value: String(format: "%.2f", user?.credit ?? 0))
                creditBox(label: "Free Credits", value: String(format: "%.0f", user?.freeCredit ?? 0))
                Spacer()
                Button { } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Credits")
                    }
                    .font(.inter(12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
                    .shadow(color: Color.brandBlue.opacity(0.4), radius: 8, y: 3)
                }
                .onTapGesture { showCredits = true }
            }
        }
        .padding(16)
        .blueBorderCard()
    }

    private func creditBox(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.inter(9, weight: .bold)).foregroundColor(.textQuaternary).tracking(0.3).textCase(.uppercase)
            Text(value).font(.inter(15, weight: .heavy)).foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
