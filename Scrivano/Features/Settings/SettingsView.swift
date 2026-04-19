import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var langMgr: LanguageManager
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
    @State private var deleteStep = 0        // 0 = confirm, 1 = enter code
    @State private var deleteCode = ""
    @State private var deleteLoading = false
    @State private var deleteError: String? = nil
    @State private var showLog = false
    @State private var showTrash = false
    @State private var showLanguage = false
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
                        Text(langMgr.t("settings.title"))
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
                            .padding(.bottom, 4)

                        // Content section
                        settingsGroup(title: langMgr.t("settings.section.content")) {
                            NavRow(icon: "✦", iconColor: Color(hex: "#a78bfa"), title: langMgr.t("settings.promptDatabase.title"), subtitle: langMgr.t("settings.promptDatabase.subtitle")) { showPrompts = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "🤖", iconColor: .brandBlue, title: langMgr.t("settings.automation.title"), subtitle: langMgr.t("settings.automation.subtitle")) { showAutomation = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "🗑", iconColor: .danger, title: langMgr.t("settings.recycleBin.title"),
                                   subtitle: trashCount > 0 ? "\(trashCount) \(trashCount == 1 ? "item" : "items")" : langMgr.t("settings.recycleBin.subtitle.empty")) { showTrash = true }
                        }
                        .padding(.top, 14)

                        // System section
                        settingsGroup(title: langMgr.t("settings.section.system")) {
                            NavRow(icon: "🎙️", iconColor: .stageMedia, title: langMgr.t("settings.recorderSettings.title"), subtitle: langMgr.t("settings.recorderSettings.subtitle")) { showRecorder = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "📋", iconColor: .brandCyan, title: langMgr.t("settings.connectionLog.title"), subtitle: langMgr.t("settings.connectionLog.subtitle")) { showLog = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            ToggleRow(icon: "🔒", iconColor: .textSecondary, title: langMgr.t("settings.securityLock.title"), subtitle: langMgr.t("settings.securityLock.subtitle"),
                                      isOn: Binding(
                                          get: { lockMgr.isEnabled },
                                          set: { newVal in
                                              if newVal { showPinSetup = true }
                                              else { showDisableConfirm = true }
                                          }
                                      ))
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "☁️", iconColor: .brandBlue, title: langMgr.t("settings.backup.title"), subtitle: langMgr.t("settings.backup.subtitle")) { showBackup = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "🌐", iconColor: .brandCyan, title: langMgr.t("settings.language.title"), subtitle: langMgr.t("settings.language.subtitle")) { showLanguage = true }
                        }
                        .padding(.top, 14)

                        // Account section
                        settingsGroup(title: langMgr.t("settings.section.account")) {
                            NavRow(icon: "🚪", iconColor: .textTertiary, title: langMgr.t("settings.logout.title"), subtitle: nil) { showLogout = true }
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            NavRow(icon: "⚠️", iconColor: .danger, title: langMgr.t("settings.deleteAccount.title"), subtitle: langMgr.t("settings.deleteAccount.subtitle"), isDanger: true) { showDeleteAccount = true }
                        }
                        .padding(.top, 14)

                        Spacer().frame(height: 30)
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

                            Text(langMgr.t("settings.logout.card.title"))
                                .font(.inter(16, weight: .heavy))
                                .foregroundColor(.textPrimary)

                            Text(langMgr.t("settings.logout.card.warning"))
                                .font(.inter(13))
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)

                            // Export & Logout
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showLogout = false }
                                AuthManager.shared.pendingLogoutAfterBackup = true
                                showBackup = true
                            } label: {
                                Text(langMgr.t("settings.logout.card.exportLogout"))
                                    .font(.inter(14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(
                                        LinearGradient(colors: [.brandBlue, .brandNavy],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            HStack(spacing: 10) {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showLogout = false }
                                } label: {
                                    Text(langMgr.t("common.cancel"))
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
                                    Text(langMgr.t("settings.logout.card.logout"))
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
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.brandBlue.opacity(0.45), lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: Color.brandBlue.opacity(0.2), radius: 20)
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

                            Text(langMgr.t("settings.deleteAccount.card.title"))
                                .font(.inter(16, weight: .heavy))
                                .foregroundColor(.textPrimary)

                            if deleteStep == 0 {
                                Text(langMgr.t("settings.deleteAccount.card.warning"))
                                    .font(.inter(13))
                                    .foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.center)

                                HStack(spacing: 10) {
                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            showDeleteAccount = false
                                            deleteStep = 0; deleteCode = ""; deleteError = nil
                                        }
                                    } label: {
                                        Text(langMgr.t("common.cancel"))
                                            .font(.inter(14, weight: .semibold))
                                            .foregroundColor(.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 13)
                                            .background(Color.white.opacity(0.07))
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    Button {
                                        deleteLoading = true
                                        deleteError = nil
                                        Task {
                                            do {
                                                struct Res: Decodable { let success: Bool; let message: String? }
                                                let res = try await APIClient.shared.request(
                                                    path: "/api/auth/request-delete-account",
                                                    method: "POST",
                                                    responseType: Res.self
                                                )
                                                await MainActor.run {
                                                    deleteLoading = false
                                                    if res.success {
                                                        withAnimation { deleteStep = 1 }
                                                    } else {
                                                        deleteError = res.message ?? "Failed to send code."
                                                    }
                                                }
                                            } catch {
                                                await MainActor.run {
                                                    deleteLoading = false
                                                    deleteError = error.localizedDescription
                                                }
                                            }
                                        }
                                    } label: {
                                        Group {
                                            if deleteLoading {
                                                ProgressView().tint(.white)
                                            } else {
                                                Text(langMgr.t("settings.deleteAccount.card.sendCode"))
                                                    .font(.inter(14, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Color.danger.opacity(0.85))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    .disabled(deleteLoading)
                                }
                            } else {
                                Text(langMgr.t("settings.deleteAccount.card.codeHint"))
                                    .font(.inter(13))
                                    .foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.center)

                                TextField("Confirmation code", text: $deleteCode)
                                    .font(.inter(15, weight: .semibold))
                                    .multilineTextAlignment(.center)
                                    .keyboardType(.numberPad)
                                    .padding(.vertical, 13)
                                    .padding(.horizontal, 16)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.danger.opacity(0.4), lineWidth: 1))

                                if let err = deleteError {
                                    Text(err)
                                        .font(.inter(12))
                                        .foregroundColor(.danger)
                                        .multilineTextAlignment(.center)
                                }

                                HStack(spacing: 10) {
                                    Button {
                                        withAnimation { deleteStep = 0; deleteCode = ""; deleteError = nil }
                                    } label: {
                                        Text(langMgr.t("settings.deleteAccount.card.back"))
                                            .font(.inter(14, weight: .semibold))
                                            .foregroundColor(.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 13)
                                            .background(Color.white.opacity(0.07))
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    Button {
                                        guard !deleteCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                        deleteLoading = true
                                        deleteError = nil
                                        Task {
                                            do {
                                                struct Body: Encodable { let confirmation_code: String }
                                                struct Res: Decodable { let success: Bool; let message: String? }
                                                let res = try await APIClient.shared.request(
                                                    path: "/api/auth/confirm-delete-account",
                                                    method: "POST",
                                                    body: Body(confirmation_code: deleteCode.trimmingCharacters(in: .whitespaces)),
                                                    responseType: Res.self
                                                )
                                                await MainActor.run {
                                                    deleteLoading = false
                                                    if res.success {
                                                        showDeleteAccount = false
                                                        deleteStep = 0; deleteCode = ""
                                                        auth.forceLogout()
                                                    } else {
                                                        deleteError = res.message ?? "Invalid code."
                                                    }
                                                }
                                            } catch {
                                                await MainActor.run {
                                                    deleteLoading = false
                                                    deleteError = error.localizedDescription
                                                }
                                            }
                                        }
                                    } label: {
                                        Group {
                                            if deleteLoading {
                                                ProgressView().tint(.white)
                                            } else {
                                                Text(langMgr.t("settings.deleteAccount.card.delete"))
                                                    .font(.inter(14, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Color.danger.opacity(0.85))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    .disabled(deleteLoading || deleteCode.trimmingCharacters(in: .whitespaces).isEmpty)
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
        }
        .sheet(isPresented: $showPinSetup) {
            PinSetupView().environmentObject(lockMgr)
        }
        .sheet(isPresented: $showDisableConfirm) {
            PinVerifyView().environmentObject(lockMgr)
        }
        .fullScreenCover(isPresented: $showBackup) {
            BackupView()
        }
        .fullScreenCover(isPresented: $showAPIKey) { APIKeyView().environmentObject(auth) }
        .fullScreenCover(isPresented: $showLanguage) { LanguagePickerView() }
    }

    // MARK: - Account Hero
    private var accountHero: some View {
        VStack(spacing: 8) {
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

                VStack(alignment: .trailing, spacing: 8) {
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

                    let plan = (user?.plan ?? "free").lowercased()
                    if plan == "unlimited" || plan.contains("api") {
                        Button {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text(langMgr.t("settings.managePlan"))
                                .font(.inter(11, weight: .heavy))
                                .foregroundColor(Color(hex: "#a78bfa"))
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .background(Color(hex: "#a78bfa").opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "#a78bfa").opacity(0.38), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }

            // Row 2: credit boxes
            HStack(spacing: 7) {
                creditBox(label: langMgr.t("plan.paidCredits"), value: String(format: "%.2f", user?.credit ?? 0), isPaid: true)
                creditBox(label: langMgr.t("plan.freeCredits"), value: String(format: "%.2f", user?.freeCredit ?? 0), isPaid: false)
            }

            // Row 3: Plans button
            Button { showCredits = true } label: {
                Text(langMgr.t("settings.plans"))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isPaid ? Color(hex: "#f59e0b").opacity(0.09) : Color.white.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(isPaid ? Color(hex: "#f59e0b").opacity(0.24) : Color.white.opacity(0.10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.inter(10, weight: .heavy))
                .foregroundColor(.textQuaternary)
                .tracking(0.7)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 0)
            content()
            Spacer().frame(height: 2)
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
    @EnvironmentObject var langMgr: LanguageManager
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
                    Text(langMgr.t("settings.connectionLog.title"))
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
                        Text(langMgr.t("settings.connectionLog.empty"))
                            .font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                        Text(langMgr.t("settings.connectionLog.emptySubtitle"))
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
