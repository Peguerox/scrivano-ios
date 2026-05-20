import SwiftUI
import UIKit

struct CreditsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @StateObject private var rc = RevenueCatManager.shared

    private var currentPlan: String { auth.currentUser?.plan.lowercased() ?? "free" }
    private var isFreePlan:      Bool { currentPlan == "free" }
    private var isPaygo:         Bool { currentPlan == "paygo" }
    private var isUnlimited:     Bool { currentPlan == "unlimited" }
    private var isBringAPI:      Bool { currentPlan == "bringapi" || currentPlan.contains("api") }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            VStack(spacing: 0) {
                SubScreenBar(
                    title: "Plans",
                    accentColor: .brandCyan,
                    onBack: { dismiss() },
                    trailingSystemIcon: "house.fill",
                    onTrailing: { NotificationCenter.default.post(name: .navigateToDashboard, object: nil) }
                )
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        balanceCard.padding(.top, 14)
                        freePlanRow.padding(.top, 14)
                        paygoGroup.padding(.top, 14)
                        unlimitedCard.padding(.top, 14)
                        apiCard.padding(.top, 14)
                        restoreButton
                        Spacer().frame(height: 40)
                    }
                }
            }

            // Loading overlay
            if rc.isLoading {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().progressViewStyle(.circular).tint(.brandCyan).scaleEffect(1.3)
                    Text("Processing…")
                        .font(.inter(13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                .padding(28)
                .background(Color(hex: "#081221"))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.brandCyan.opacity(0.25), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .navigationBarHidden(true)
        .task { await rc.fetchPrices() }
        .alert("Purchase Error", isPresented: .init(
            get: { rc.errorMessage != nil },
            set: { if !$0 { rc.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { rc.errorMessage = nil }
        } message: {
            Text(rc.errorMessage ?? "")
        }
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.brandCyan.opacity(0.65), Color.brandBlue.opacity(0.5), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .zIndex(1)

            VStack(alignment: .leading, spacing: 10) {
                Text("Current Balance")
                    .font(.inter(10, weight: .heavy))
                    .foregroundColor(.textQuaternary)
                    .tracking(1)
                    .textCase(.uppercase)

                HStack(spacing: 7) {
                    balItem(value: String(format: "%.2f", auth.currentUser?.credit ?? 0),
                            label: "Paid credits", isPaid: true)
                    balItem(value: String(format: "%.0f", auth.currentUser?.freeCredit ?? 0),
                            label: "Free credits", isPaid: false)
                }
            }
            .padding(16)
        }
        .background(
            LinearGradient(colors: [Color.brandBlue.opacity(0.18), Color.brandNavy.opacity(0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.brandBlue.opacity(0.28), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 18)
    }

    private func balItem(value: String, label: String, isPaid: Bool) -> some View {
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

    // MARK: - Free Plan Row

    private var freePlanRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Free Plan")
                        .font(.inter(13, weight: .bold))
                        .foregroundColor(isFreePlan ? .textPrimary : Color.white.opacity(0.6))
                    if isFreePlan { activeBadge }
                }
                Text("Monthly credits refreshed daily")
                    .font(.inter(11))
                    .foregroundColor(.textQuaternary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                ZStack(alignment: .trailing) {
                    Capsule()
                        .fill(LinearGradient(colors: [Color.brandBlue, Color.brandCyan],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: 46, height: 27)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 21, height: 21)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .padding(.trailing, 3)
                }
                Text("Always On")
                    .font(.inter(10, weight: .bold))
                    .foregroundColor(.textQuaternary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(isFreePlan ? Color.brandCyan.opacity(0.06) : Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(isFreePlan ? Color.brandCyan.opacity(0.30) : Color.white.opacity(0.08), lineWidth: isFreePlan ? 1.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
    }

    // MARK: - Pay As You Go Group

    private var paygoGroup: some View {
        VStack(spacing: 0) {
            Text("Pay as you go")
                .font(.inter(10, weight: .heavy))
                .foregroundColor(.textQuaternary)
                .tracking(0.7)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 2)
            tierRow(productId: RCProduct.credits50,  credits: "50",  name: "Starter Pack",  price: rc.productPrices[RCProduct.credits50]  ?? "$4.99",  isBest: false, glowLevel: 0)
            Divider().background(Color.white.opacity(0.05)).padding(.leading, 76)
            tierRow(productId: RCProduct.credits125, credits: "125", name: "Standard Pack", price: rc.productPrices[RCProduct.credits125] ?? "$9.99",  isBest: false, glowLevel: 1)
            Divider().background(Color.white.opacity(0.05)).padding(.leading, 76)
            tierRow(productId: RCProduct.credits300, credits: "300", name: "Plus Pack",     price: rc.productPrices[RCProduct.credits300] ?? "$19.99", isBest: true,  glowLevel: 2)
        }
        .background(Color.white.opacity(0.045))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 18)
    }

    // MARK: - Active Plan Badge
    private var activeBadge: some View {
        Text("CURRENT PLAN")
            .font(.inter(8, weight: .heavy))
            .foregroundColor(.brandCyan)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.brandCyan.opacity(0.15))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.brandCyan.opacity(0.40), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func tierRow(productId: String, credits: String, name: String, price: String, isBest: Bool, glowLevel: Int) -> some View {
        let bgOpacity:     [Double] = [0.20, 0.28, 0.38]
        let blueOpacity:   [Double] = [0.12, 0.18, 0.26]
        let borderOpacity: [Double] = [0.30, 0.40, 0.55]
        let glowOpacity:   [Double] = [0.12, 0.18, 0.25]

        return HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(credits)
                    .font(.inter(15, weight: .heavy))
                    .foregroundColor(isBest ? .white : .brandCyan)
                Text("credits")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isBest ? Color.white.opacity(0.8) : Color.brandCyan.opacity(0.7))
                    .textCase(.uppercase)
                    .tracking(0.3)
            }
            .frame(width: 46, height: 46)
            .background(
                LinearGradient(colors: [Color.brandCyan.opacity(bgOpacity[glowLevel]),
                                        Color.brandBlue.opacity(blueOpacity[glowLevel])],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color.brandCyan.opacity(borderOpacity[glowLevel]), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.brandCyan.opacity(glowOpacity[glowLevel]), radius: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.inter(13, weight: .bold))
                        .foregroundColor(.textPrimary)
                    if isBest {
                        Text("BEST VALUE")
                            .font(.inter(8, weight: .heavy))
                            .foregroundColor(.brandCyan)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.brandCyan.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                Text("One-time purchase")
                    .font(.inter(11))
                    .foregroundColor(.textQuaternary)
            }

            Spacer()

            Text(price)
                .font(.inter(15, weight: .heavy))
                .foregroundColor(.textPrimary)
                .padding(.trailing, 10)

            Button {
                Task { await rc.purchase(productId: productId) }
            } label: {
                Text("+")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.brandCyan)
                    .frame(width: 32, height: 32)
                    .background(Color.brandCyan.opacity(0.10))
                    .overlay(Circle().stroke(Color.brandCyan.opacity(0.50), lineWidth: 1.5))
                    .clipShape(Circle())
            }
            .disabled(rc.isLoading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: - Unlimited Card

    private var unlimitedCard: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.brandCyan.opacity(0.80), Color.brandBlue.opacity(0.60), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .zIndex(1)

            VStack(alignment: .leading, spacing: 0) {
                Text("Unlimited Access")
                    .font(.inter(10, weight: .heavy))
                    .foregroundColor(.textQuaternary)
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                HStack(spacing: 8) {
                    Text("Most Popular")
                        .font(.inter(9, weight: .heavy))
                        .tracking(0.8)
                        .foregroundColor(Color(hex: "#060e1e"))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.brandCyan)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    if isUnlimited { activeBadge }
                }
                .padding(.bottom, 12)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("∞ Unlimited Access")
                            .font(.inter(14, weight: .heavy))
                            .foregroundColor(.brandCyan)
                        Text(rc.productPrices[RCProduct.unlimited] ?? "$20.00")
                            .font(.inter(22, weight: .heavy))
                            .foregroundColor(.textPrimary)
                        Text("per month · cancel anytime")
                            .font(.inter(11))
                            .foregroundColor(.textTertiary)
                    }
                    Spacer()
                    Text("∞")
                        .font(.system(size: 38, weight: .heavy))
                        .foregroundColor(Color.brandCyan.opacity(0.18))
                        .padding(.top, -4)
                }
                .padding(.bottom, 16)

                HStack(spacing: 10) {
                    Button {
                        Task { await rc.purchase(productId: RCProduct.unlimited) }
                    } label: {
                        Text(isUnlimited ? "Active Plan ✓" : "Subscribe Now →")
                            .font(.inter(13, weight: .heavy))
                            .foregroundColor(isUnlimited ? .brandCyan : Color(hex: "#060e1e"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isUnlimited
                                ? LinearGradient(colors: [Color.brandCyan.opacity(0.12), Color.brandCyan.opacity(0.12)],
                                                 startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.brandBlue, Color.brandCyan],
                                                 startPoint: .leading, endPoint: .trailing))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(isUnlimited ? Color.brandCyan.opacity(0.50) : Color.clear, lineWidth: 1.5))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color.brandCyan.opacity(isUnlimited ? 0 : 0.30), radius: 8, y: 4)
                    }
                    .disabled(rc.isLoading || isUnlimited)

                    if isUnlimited {
                        Button {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Manage →")
                                .font(.inter(13, weight: .heavy))
                                .foregroundColor(Color.brandCyan)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 18)
                                .background(Color.brandCyan.opacity(0.10))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.brandCyan.opacity(0.45), lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(
            LinearGradient(colors: [Color.brandCyan.opacity(0.13), Color.brandBlue.opacity(0.18), Color.brandNavy.opacity(0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(RoundedRectangle(cornerRadius: 22)
            .stroke(Color.brandCyan.opacity(isUnlimited ? 0.70 : 0.38), lineWidth: isUnlimited ? 1.5 : 1))
        .overlay(alignment: .topTrailing) {
            if isUnlimited {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
                    .padding(.trailing, 18).padding(.top, 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color.brandCyan.opacity(isUnlimited ? 0.22 : 0.12), radius: 28)
        .padding(.horizontal, 18)
    }

    // MARK: - Bring Your Own API Card

    private var apiCard: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color(hex: "#a78bfa").opacity(0.60), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .zIndex(1)

            VStack(spacing: 10) {
                Text("Bring Your Own API")
                    .font(.inter(10, weight: .heavy))
                    .foregroundColor(.textQuaternary)
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "#a78bfa"))
                        .frame(width: 40, height: 40)
                        .background(Color(hex: "#a78bfa").opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#a78bfa").opacity(0.30), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Bring your own API")
                                .font(.inter(13, weight: .heavy))
                                .foregroundColor(Color(hex: "#a78bfa"))
                            if isBringAPI {
                                Text("CURRENT PLAN")
                                    .font(.inter(8, weight: .heavy))
                                    .foregroundColor(Color(hex: "#a78bfa"))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color(hex: "#a78bfa").opacity(0.15))
                                    .overlay(RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color(hex: "#a78bfa").opacity(0.40), lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                        Text("Use your OpenAI key · unlimited integrations")
                            .font(.inter(11))
                            .foregroundColor(.textQuaternary)
                    }
                    Spacer()
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rc.productPrices[RCProduct.bringapi] ?? "$10.00")
                            .font(.inter(20, weight: .heavy))
                            .foregroundColor(.textPrimary)
                        Text("per month")
                            .font(.inter(11))
                            .foregroundColor(.textQuaternary)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Button {
                            Task { await rc.purchase(productId: RCProduct.bringapi) }
                        } label: {
                            Text(isBringAPI ? "Active Plan ✓" : "Connect API →")
                                .font(.inter(12, weight: .heavy))
                                .foregroundColor(Color(hex: "#a78bfa"))
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .background(Color(hex: "#a78bfa").opacity(isBringAPI ? 0.18 : 0.10))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: "#a78bfa").opacity(isBringAPI ? 0.70 : 0.50), lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(rc.isLoading || isBringAPI)

                        if isBringAPI {
                            Button {
                                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Text("Manage →")
                                    .font(.inter(12, weight: .heavy))
                                    .foregroundColor(Color(hex: "#a78bfa"))
                                    .padding(.horizontal, 18).padding(.vertical, 9)
                                    .background(Color(hex: "#a78bfa").opacity(0.08))
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(hex: "#a78bfa").opacity(0.45), lineWidth: 1.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(
            LinearGradient(colors: [Color(hex: "#a78bfa").opacity(isBringAPI ? 0.18 : 0.10),
                                    Color(hex: "#6d28d9").opacity(isBringAPI ? 0.14 : 0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(RoundedRectangle(cornerRadius: 22)
            .stroke(Color(hex: "#a78bfa").opacity(isBringAPI ? 0.55 : 0.30), lineWidth: isBringAPI ? 1.5 : 1))
        .overlay(alignment: .topTrailing) {
            if isBringAPI {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
                    .padding(.trailing, 18).padding(.top, 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 18)
    }

    // MARK: - Restore Button

    private var restoreButton: some View {
        Button {
            Task { await rc.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.inter(12, weight: .semibold))
                .foregroundColor(.textQuaternary)
        }
        .disabled(rc.isLoading)
        .padding(.top, 20)
    }


}
