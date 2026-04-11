import Foundation
import RevenueCat

// MARK: - Product IDs
// These must match exactly what is configured in App Store Connect and RevenueCat dashboard.
enum RCProduct {
    // One-time credit packs
    static let credits50  = "com.scrivano.recorderapp.credit1"
    static let credits125 = "com.scrivano.recorderapp.credit2"
    static let credits300 = "com.scrivano.recorderapp.credit3"
    // Subscriptions
    static let unlimited  = "com.scrivano.recorderapp.unlimited1"
    static let bringapi   = "com.scrivano.recorderapp.bringapi"
}

// MARK: - RevenueCatManager

@MainActor
final class RevenueCatManager: ObservableObject {
    static let shared = RevenueCatManager()
    private init() {}

    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var productPrices: [String: String] = [:]

    func fetchPrices() async {
        let ids = [RCProduct.credits50, RCProduct.credits125, RCProduct.credits300,
                   RCProduct.unlimited, RCProduct.bringapi]
        let products = (try? await Purchases.shared.products(ids)) ?? []
        var prices: [String: String] = [:]
        for p in products { prices[p.productIdentifier] = p.localizedPriceString }
        productPrices = prices
    }

    // MARK: - Configure (call once in ScrivanoApp.init)
    static func configure() {
        Purchases.configure(withAPIKey: "appl_NUSyubKMglBdwxSYLmqmZxOwtTy")
        Purchases.logLevel = .warn
    }

    // MARK: - Identity
    // Call after login so RevenueCat links purchases to the Supabase user UUID.
    func login(userId: String) async {
        do {
            _ = try await Purchases.shared.logIn(userId)
            appLog("[RC] Logged in: \(userId)", level: .info)
        } catch {
            appLog("[RC] Login failed: \(error.localizedDescription)", level: .warning)
        }
    }

    func logout() async {
        do {
            _ = try await Purchases.shared.logOut()
            appLog("[RC] Logged out", level: .info)
        } catch {
            appLog("[RC] Logout failed: \(error.localizedDescription)", level: .warning)
        }
    }

    // MARK: - Purchase

    /// Buy a one-time credit pack or subscribe to a plan.
    func purchase(productId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let products = try await Purchases.shared.products([productId])
            guard let product = products.first else {
                errorMessage = "Product not available. Please try again later."
                return
            }
            let result = try await Purchases.shared.purchase(product: product)
            guard !result.userCancelled else { return }
            // Refresh user from server so credits/plan reflect the purchase
            await AuthManager.shared.refreshUser()
            appLog("[RC] Purchase complete: \(productId)", level: .success)
        } catch {
            errorMessage = error.localizedDescription
            appLog("[RC] Purchase failed: \(error.localizedDescription)", level: .error)
        }
    }

    // MARK: - Restore
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await Purchases.shared.restorePurchases()
            await AuthManager.shared.refreshUser()
            appLog("[RC] Purchases restored", level: .success)
        } catch {
            errorMessage = error.localizedDescription
            appLog("[RC] Restore failed: \(error.localizedDescription)", level: .error)
        }
    }
}
