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
                if let refresh = res.refreshToken { keychain.saveRefreshToken(refresh) }
                keychain.saveUser(user)
                keychain.saveLoginProvider("email")
                self.currentUser = user
                self.isLoggedIn = true
                Task { await RevenueCatManager.shared.login(userId: user.email) }
            } else {
                errorMessage = res.message ?? "Login failed."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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

    // MARK: - Logout
    func logout() {
        guard !AudioRecorderManager.shared.isRecording else {
            appLog("logout() suppressed — recording in progress", level: .warning)
            return
        }
        keychain.clearAll()
        currentUser = nil
        isLoggedIn = false
        Task { await RevenueCatManager.shared.logout() }
    }

    /// Force-logout regardless of recording state — use only from explicit user action.
    func forceLogout() {
        keychain.clearAll()
        currentUser = nil
        isLoggedIn = false
        Task { await RevenueCatManager.shared.logout() }
    }

    // MARK: - Refresh user from server (credits, plan, etc.)
    func refreshUser() async {
        struct Res: Decodable {
            let success: Bool
            let user: User?
        }
        guard let res = try? await api.request(path: "/api/auth/me", responseType: Res.self),
              res.success, let user = res.user else { return }
        updateUser(user)
    }

    // MARK: - Update user locally (after credit deduction etc.)
    func updateUser(_ user: User) {
        self.currentUser = user
        keychain.saveUser(user)
    }
}
