import Foundation
import Combine

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var currentUser: User?
    @Published var isLoggedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var hasOpenAIKey: Bool = false
    /// Set to the email when login fails because the account isn't verified yet.
    @Published var unverifiedEmail: String?

    /// Set to true before opening BackupView from the logout flow.
    /// BackupView reads this directly after share sheet dismisses.
    var pendingLogoutAfterBackup = false

    private let api = APIClient.shared
    private let keychain = KeychainService.shared

    private init() {
        // Restore session from keychain
        if let user = keychain.getUser(), keychain.getToken() != nil {
            self.currentUser = user
            self.isLoggedIn = true
            Task { await RevenueCatManager.shared.login(userId: user.email) }
        }
    }

    // MARK: - Login
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        unverifiedEmail = nil
        defer { isLoading = false }

        struct LoginBody: Encodable {
            let email: String
            let password: String
        }

        do {
            let res = try await api.request(
                path: "/api/auth/login",
                method: "POST",
                body: LoginBody(email: email, password: password),
                responseType: LoginResponse.self
            )

            if res.success, let token = res.token, let user = res.user {
                keychain.saveToken(token)
                if let refresh = res.refreshToken {
                    keychain.saveRefreshToken(refresh)
                    appLog("[AUTH] Refresh token saved", level: .success)
                } else {
                    appLog("[AUTH] No refresh token in login response — silent refresh will not work", level: .warning)
                }
                keychain.saveUser(user)
                keychain.saveLoginProvider("email")
                completeLogin(user: user)
            } else if isUnverifiedResponse(confirmedEmail: res.confirmedEmail, message: res.message) {
                unverifiedEmail = email
            } else {
                errorMessage = res.message ?? "Login failed."
            }
        } catch {
            let msg = error.localizedDescription
            if isUnverifiedMessage(msg) {
                unverifiedEmail = email
            } else {
                errorMessage = msg
            }
        }
    }

    private func isUnverifiedResponse(confirmedEmail: Bool?, message: String?) -> Bool {
        if confirmedEmail == false { return true }
        return isUnverifiedMessage(message ?? "")
    }

    private func isUnverifiedMessage(_ msg: String) -> Bool {
        let lower = msg.lowercased()
        return lower.contains("not confirmed") || lower.contains("verify") || lower.contains("confirmed")
    }

    // MARK: - Register
    func register(email: String, password: String, firstName: String, lastName: String = "") async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        struct RegisterBody: Encodable {
            let email: String
            let password: String
            let firstName: String
            let lastName: String
            enum CodingKeys: String, CodingKey {
                case email, password
                case firstName = "first_name"
                case lastName  = "last_name"
            }
        }

        do {
            struct RegisterResponse: Decodable {
                let success: Bool
                let message: String?
            }
            let res = try await api.request(
                path: "/api/auth/register",
                method: "POST",
                body: RegisterBody(email: email, password: password, firstName: firstName, lastName: lastName),
                responseType: RegisterResponse.self
            )
            if !res.success {
                errorMessage = res.message ?? "Registration failed."
            }
            // On success the caller can show a verification prompt
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Forgot password
    func forgotPassword(email: String) async -> Bool {
        struct Body: Encodable { let email: String }
        struct Res: Decodable { let success: Bool; let message: String? }
        do {
            let res = try await api.request(
                path: "/api/auth/forgot-password",
                method: "POST",
                body: Body(email: email),
                responseType: Res.self
            )
            return res.success
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Reset password (verify code + set new password)
    // POST /api/auth/reset-password { email, confirmation_code, new_password }
    func verifyResetCode(email: String, code: String, newPassword: String) async -> Bool {
        struct Body: Encodable {
            let email: String
            let confirmation_code: String
            let new_password: String
        }
        guard let url = URL(string: api.baseURL + "/api/auth/reset-password") else { return false }
        do {
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(Body(email: email, confirmation_code: code, new_password: newPassword))
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let success = json["success"] as? Bool ?? false
                if !success {
                    errorMessage = (json["message"] as? String) ?? "Invalid code or password"
                }
                return success
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Resend code
    // POST /api/auth/resend-code { email, type: 'password_reset' }
    func resendResetCode(email: String) async -> Bool {
        struct Body: Encodable { let email: String; let type: String }
        guard let url = URL(string: api.baseURL + "/api/auth/resend-code") else { return false }
        do {
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(Body(email: email, type: "password_reset"))
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json["success"] as? Bool ?? false
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Complete login (shared by email + social flows)
    /// Detects user switch, clears local data if needed, then sets the logged-in state.
    func completeLogin(user: User) {
        let lastId = keychain.getLastUserId()
        if let lastId, lastId != user.id {
            clearLocalDataForUserSwitch()
        }
        keychain.saveLastUserId(user.id)
        currentUser = user
        isLoggedIn = true
        Task { await RevenueCatManager.shared.login(userId: user.email) }
        Task { await refreshUser() }

        // Seed a default collection so the dashboard is never in a ghost state
        if LocalCollectionStore.shared.collections.isEmpty {
            let defaultCollection = ScrivanoCollection(id: UUID().uuidString, name: "My Collection")
            LocalCollectionStore.shared.save(defaultCollection)
        }
    }

    // MARK: - Clear local data on user switch
    private func clearLocalDataForUserSwitch() {
        LocalCollectionStore.shared.clearAll()
        LocalItemStore.shared.clearAll()
        LocalTranscriptStore.shared.clearAll()
        LocalNoteStore.shared.clearAll()
        LocalRecordingStore.shared.clearAll()
        LocalImageStore.shared.clearAll()
        TrashStore.shared.empty()
        PendingTaskStore.shared.clearAll()
        UserDefaults.standard.removeObject(forKey: "transcribedRecordingIds")
        appLog("[AUTH] Local data cleared for user switch", level: .info)
    }

    // MARK: - Logout
    func logout() {
        guard !AudioRecorderManager.shared.isRecording else {
            appLog("logout() suppressed — recording in progress", level: .warning)
            return
        }
        keychain.clearAll()
        currentUser = nil
        isLoggedIn = false
        errorMessage = nil
        unverifiedEmail = nil
        Task { await RevenueCatManager.shared.logout() }
    }

    /// Force-logout regardless of recording state — use only from explicit user action.
    func forceLogout() {
        keychain.clearAll()
        currentUser = nil
        isLoggedIn = false
        errorMessage = nil
        unverifiedEmail = nil
        Task { await RevenueCatManager.shared.logout() }
    }

    // MARK: - Refresh user from server (credits, plan, etc.)
    func refreshUser() async {
        struct Res: Decodable {
            let success: Bool
            let userCredit: Double?
            let freeCredit: Double?
            let currentPlan: String?
            let hasOpenAIKey: Bool?
            enum CodingKeys: String, CodingKey {
                case success
                case userCredit   = "user_credit"
                case freeCredit   = "free_credit"
                case currentPlan  = "current_plan"
                case hasOpenAIKey = "has_openai_key"
            }
        }
        do {
            let res = try await api.request(
                path: "/api/user/credits",
                method: "GET",
                responseType: Res.self
            )
            guard res.success else {
                appLog("[AUTH] refreshUser: server returned success=false", level: .warning)
                return
            }
            guard var user = currentUser else { return }
            if let paid = res.userCredit { user.credit = paid }
            if let free = res.freeCredit { user.freeCredit = free }
            if let plan = res.currentPlan { user.plan = plan }
            updateUser(user)
            if let keySet = res.hasOpenAIKey { hasOpenAIKey = keySet }
            appLog("[AUTH] refreshUser: paid=\(String(format: "%.4f", user.credit)) free=\(String(format: "%.4f", user.freeCredit))", level: .success)
        } catch {
            appLog("[AUTH] refreshUser: \(error.localizedDescription)", level: .error)
        }
    }

    // MARK: - Update user locally (after credit deduction etc.)
    func updateUser(_ user: User) {
        self.currentUser = user
        keychain.saveUser(user)
    }

    /// Update only the credit balances from a task result response.
    func updateCredits(paid: Double, free: Double) {
        guard var user = currentUser else { return }
        user.credit = paid
        user.freeCredit = free
        updateUser(user)
    }
}
