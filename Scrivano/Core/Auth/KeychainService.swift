import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    private let tokenKey     = "scrivano.auth.token"
    private let refreshKey   = "scrivano.auth.refresh"
    private let userKey      = "scrivano.auth.user"

    // MARK: - Token
    func saveToken(_ token: String) {
        save(key: tokenKey, value: token)
    }
    func getToken() -> String? {
        load(key: tokenKey)
    }
    func saveRefreshToken(_ token: String) {
        save(key: refreshKey, value: token)
    }
    func getRefreshToken() -> String? {
        load(key: refreshKey)
    }

    // MARK: - User
    func saveUser(_ user: User) {
        if let data = try? JSONEncoder().encode(user) {
            saveData(key: userKey, data: data)
        }
    }
    func getUser() -> User? {
        guard let data = loadData(key: userKey) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    // MARK: - Last logged-in user ID (for user-switch detection)
    private let lastUserIdKey = "scrivano.auth.lastUserId"
    func saveLastUserId(_ id: String) { save(key: lastUserIdKey, value: id) }
    func getLastUserId() -> String? { load(key: lastUserIdKey) }

    // MARK: - Clear
    func clearAll() {
        delete(key: tokenKey)
        delete(key: refreshKey)
        delete(key: userKey)
    }

    // MARK: - Login provider ("google", "apple", "email")
    private let providerKey = "scrivano.auth.provider"
    func saveLoginProvider(_ provider: String) { save(key: providerKey, value: provider) }
    func getLoginProvider() -> String? { load(key: providerKey) }

    // MARK: - OpenAI API Key
    private let openAIKeyKey = "scrivano.openai.key"
    func saveOpenAIKey(_ key: String) { save(key: openAIKeyKey, value: key) }
    func getOpenAIKey() -> String? { load(key: openAIKeyKey) }
    func deleteOpenAIKey() { delete(key: openAIKeyKey) }

    // MARK: - Private helpers
    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        saveData(key: key, data: data)
    }

    private func saveData(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func load(key: String) -> String? {
        guard let data = loadData(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func loadData(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
