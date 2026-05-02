import Foundation
import GoogleSignIn
import AuthenticationServices
import CryptoKit

private struct SocialAuthResponse: Decodable {
    let success: Bool
    let token: String?
    let refreshToken: String?
    let user: User?
    let message: String?
    enum CodingKeys: String, CodingKey {
        case success, token, user, message
        case refreshToken = "refresh_token"
    }
}

@MainActor
final class SocialAuthManager: NSObject, ObservableObject {

    static let shared = SocialAuthManager()
    private override init() {}

    // MARK: - Google Sign In

    func signInWithGoogle(presenting viewController: UIViewController) async throws -> User {
        let config = GIDConfiguration(
            clientID: "834233245975-a5kv77upuj67ksnckn0i4g8vjcs066ob.apps.googleusercontent.com"
        )
        GIDSignIn.sharedInstance.configuration = config

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw APIClientError.serverError("Google ID token missing.")
        }

        struct Body: Encodable {
            let idToken: String
            let source: String
            enum CodingKeys: String, CodingKey {
                case idToken = "id_token"
                case source
            }
        }

        return try await authenticateWithBackend(
            path: "/api/auth/google",
            body: Body(idToken: idToken, source: "ios")
        )
    }

    // MARK: - Apple Sign In

    private var appleSignInContinuation: CheckedContinuation<ASAuthorization, Error>?
    private var currentNonce: String?

    func signInWithApple() async throws -> User {
        let rawNonce = randomNonceString()
        currentNonce = rawNonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(rawNonce)

        let authorization = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
            self.appleSignInContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleIDCredential.identityToken,
              let idToken = String(data: identityTokenData, encoding: .utf8) else {
            throw APIClientError.serverError("Apple ID token missing.")
        }

        let authCode = appleIDCredential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
        let firstName = appleIDCredential.fullName?.givenName
        let lastName  = appleIDCredential.fullName?.familyName

        struct Body: Encodable {
            let idToken: String
            let nonce: String
            let authorizationCode: String?
            let firstName: String?
            let lastName: String?
            enum CodingKeys: String, CodingKey {
                case idToken = "id_token"
                case nonce
                case authorizationCode = "authorization_code"
                case firstName = "first_name"
                case lastName  = "last_name"
            }
        }

        return try await authenticateWithBackend(
            path: "/api/auth/apple",
            body: Body(idToken: idToken, nonce: rawNonce, authorizationCode: authCode, firstName: firstName, lastName: lastName)
        )
    }

    // MARK: - Shared backend handler

    private func authenticateWithBackend<B: Encodable>(path: String, body: B) async throws -> User {
        guard let url = URL(string: APIClient.shared.baseURL + path) else {
            throw APIClientError.invalidURL
        }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: req)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIClientError.serverError("Social login failed.")
        }
        guard json["success"] as? Bool == true,
              let token = json["token"] as? String else {
            throw APIClientError.serverError(json["message"] as? String ?? "Social login failed.")
        }

        let userJson = json["user"] as? [String: Any]
        let user = User(
            id:          userJson?["id"] as? String ?? "",
            email:       userJson?["email"] as? String ?? "",
            firstName:   userJson?["first_name"] as? String ?? "",
            lastName:    userJson?["last_name"] as? String ?? "",
            plan:        userJson?["plan"] as? String ?? "free",
            credit:      userJson?["credit"] as? Double ?? 0,
            freeCredit:  userJson?["free_credit"] as? Double ?? 0
        )

        KeychainService.shared.saveToken(token)
        if let refresh = json["refresh_token"] as? String {
            KeychainService.shared.saveRefreshToken(refresh)
        }
        KeychainService.shared.saveUser(user)
        KeychainService.shared.saveLoginProvider(path.contains("google") ? "google" : "apple")
        return user
    }

    // MARK: - Silent Google re-authentication (no UI shown)
    /// Restores the previous Google sign-in silently and exchanges it for
    /// a fresh backend token pair. Called automatically when the backend
    /// refresh token is expired but the user originally signed in with Google.
    func silentGoogleReauth() async throws {
        let result = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        guard let idToken = result.idToken?.tokenString else {
            throw APIClientError.serverError("Google silent re-auth: no ID token.")
        }
        struct Body: Encodable {
            let idToken: String
            let source: String
            enum CodingKeys: String, CodingKey {
                case idToken = "id_token"
                case source
            }
        }
        _ = try await authenticateWithBackend(
            path: "/api/auth/google",
            body: Body(idToken: idToken, source: "ios")
        )
    }

    // MARK: - Nonce helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension SocialAuthManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            appleSignInContinuation?.resume(returning: authorization)
            appleSignInContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            appleSignInContinuation?.resume(throwing: error)
            appleSignInContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension SocialAuthManager: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }
}
