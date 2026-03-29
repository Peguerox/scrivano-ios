import SwiftUI

struct CreditsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: "Plans", accentColor: .brandCyan, onBack: { dismiss() })

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {

                        // Current balance
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Current Balance")
                                .font(.inter(12, weight: .heavy))
                                .foregroundColor(.textQuaternary)
                                .tracking(0.5)
                                .textCase(.uppercase)
                            HStack(spacing: 8) {
                                balanceItem(label: "Paid Credits", value: String(format: "%.2f", auth.currentUser?.credit ?? 0), highlight: true)
                                balanceItem(label: "Free Credits", value: String(format: "%.0f", auth.currentUser?.freeCredit ?? 0), highlight: false)
                            }
                        }
                        .padding(16)
                        .blueBorderCard()
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                        // Free plan
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Free Plan").font(.inter(14, weight: .bold)).foregroundColor(.textPrimary)
                                    Text("Monthly credits refreshed daily")
                                        .font(.inter(11)).foregroundColor(.textTertiary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Toggle("", isOn: .constant(true)).labelsHidden().tint(.brandBlue).disabled(true)
                                    Text("Always On").font(.inter(9, weight: .bold)).foregroundColor(.textQuaternary)
                                }
                            }
                        }
                        .padding(16)
                        .cardStyle()
                        .padding(.horizontal, 14)

                        // Pay as you go
                        SectionLabel(text: "Pay As You Go")
                        HStack(spacing: 8) {
                            paygoCard(credits: "50", name: "Starter", price: "$4.99", isBest: false)
                            paygoCard(credits: "80", name: "Standard", price: "$6.99", isBest: false)
                            paygoCard(credits: "125", name: "Plus", price: "$9.99", isBest: true)
                        }
                        .padding(.horizontal, 14)

                        // Unlimited
                        SectionLabel(text: "Unlimited Access")
                        VStack(spacing: 12) {
                            HStack {
                                Text("Most Popular")
                                    .font(.inter(9, weight: .heavy))
                                    .tracking(1)
                                    .foregroundColor(.brandCyan)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.brandBlue.opacity(0.2))
                                    .clipShape(Capsule())
                                Spacer()
                            }

                            HStack {
                                Text("∞")
                                    .font(.system(size: 40, weight: .heavy))
                                    .foregroundColor(.brandCyan)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("$34.99")
                                        .font(.inter(22, weight: .heavy))
                                        .foregroundColor(.textPrimary)
                                    Text("per month · cancel anytime")
                                        .font(.inter(11)).foregroundColor(.textTertiary)
                                }
                            }

                            Button {
                            } label: {
                                Text("Subscribe Now →")
                                    .font(.inter(14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .leading, endPoint: .trailing))
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                                    .shadow(color: Color.brandBlue.opacity(0.4), radius: 8, y: 4)
                            }
                        }
                        .padding(16)
                        .background(
                            LinearGradient(colors: [Color.brandBlue.opacity(0.15), Color.brandNavy.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.brandBlue.opacity(0.3), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 14)

                        // Bring your own API
                        SectionLabel(text: "Bring Your Own API")
                        HStack(spacing: 14) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "#a78bfa"))
                                .frame(width: 44, height: 44)
                                .background(Color(hex: "#a78bfa").opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Bring your own API")
                                    .font(.inter(14, weight: .bold)).foregroundColor(.textPrimary)
                                Text("Use your OpenAI key · unlimited integrations")
                                    .font(.inter(11)).foregroundColor(.textTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$19.99")
                                    .font(.inter(14, weight: .heavy)).foregroundColor(.textPrimary)
                                Text("/month")
                                    .font(.inter(10)).foregroundColor(.textQuaternary)
                            }
                        }
                        .padding(14)
                        .cardStyle(padding: 0)
                        .padding(.horizontal, 14)

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func balanceItem(label: String, value: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.inter(9, weight: .bold)).foregroundColor(.textQuaternary).tracking(0.3).textCase(.uppercase)
            Text(value).font(.inter(18, weight: .heavy)).foregroundColor(highlight ? .brandCyan : .textPrimary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(highlight ? Color.brandBlue.opacity(0.3) : Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func paygoCard(credits: String, name: String, price: String, isBest: Bool) -> some View {
        VStack(spacing: 8) {
            if isBest {
                Text("BEST VALUE")
                    .font(.inter(7, weight: .heavy))
                    .tracking(0.8)
                    .foregroundColor(.brandCyan)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.brandBlue.opacity(0.2))
                    .clipShape(Capsule())
            } else {
                Spacer().frame(height: 14)
            }
            Text(credits)
                .font(.inter(22, weight: .heavy))
                .foregroundColor(.textPrimary)
            Text("credits")
                .font(.inter(9, weight: .bold))
                .foregroundColor(.textQuaternary)
            Text(name)
                .font(.inter(11, weight: .semibold))
                .foregroundColor(.textTertiary)
            Text(price)
                .font(.inter(13, weight: .heavy))
                .foregroundColor(.textPrimary)
            Button {
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .top, endPoint: .bottom))
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(isBest
            ? LinearGradient(colors: [Color.brandBlue.opacity(0.2), Color.brandNavy.opacity(0.1)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isBest ? Color.brandBlue.opacity(0.4) : Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
