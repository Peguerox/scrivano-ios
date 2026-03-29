import Foundation
import Combine

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var currentUser: User?
    @Published var isLoggedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let api = APIClient.shared
    private let keychain = KeychainService.shared

    private init() {
        // Restore session from keychain
        if let user = keychain.getUser(), keychain.getToken() != nil {
            self.currentUser = user
            self.isLoggedIn = true
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
                self.currentUser = user
                self.isLoggedIn = true
            } else {
                errorMessage = res.message ?? "Login failed."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Register
    func register(email: String, password: String, firstName: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        struct RegisterBody: Encodable {
            let email: String
            let password: String
            let firstName: String
            enum CodingKeys: String, CodingKey {
                case email, password
                case firstName = "first_name"
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
                body: RegisterBody(email: email, password: password, firstName: firstName),
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

    // MARK: - Logout
    func logout() {
        keychain.clearAll()
        currentUser = nil
        isLoggedIn = false
    }

    // MARK: - Update user locally (after credit deduction etc.)
    func updateUser(_ user: User) {
        self.currentUser = user
        keychain.saveUser(user)
    }
}
