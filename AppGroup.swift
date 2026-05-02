import Foundation

enum AppGroup {
    static let id = "group.com.scrivano.ScrivanoRecorder"

    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    static func mirrorCollections() {
        guard let data = try? JSONEncoder().encode(LocalCollectionStore.shared.collections) else { return }
        defaults?.set(data, forKey: "scrivano.collections")
    }

    static func mirrorItems() {
        guard let data = try? JSONEncoder().encode(LocalItemStore.shared.items) else { return }
        defaults?.set(data, forKey: "scrivano.items")
    }

    static func setLoggedIn(_ value: Bool) {
        defaults?.set(value, forKey: "scrivano.isLoggedIn")
    }
}
