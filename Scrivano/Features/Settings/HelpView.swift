import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: "Help", accentColor: .brandCyan, onBack: { dismiss() })

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {

                        // Hero
                        VStack(alignment: .leading, spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.brandCyan.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandCyan.opacity(0.3), lineWidth: 1))
                                    .shadow(color: Color.brandCyan.opacity(0.15), radius: 8)
                                Text("?")
                                    .font(.inter(22, weight: .heavy))
                                    .foregroundColor(.brandCyan)
                            }

                            Text("How can we help?")
                                .font(.inter(16, weight: .heavy))
                                .foregroundColor(.textPrimary)
                            Text("Find answers, watch tutorials, and connect with the Scrivano community.")
                                .font(.inter(12))
                                .foregroundColor(.textTertiary)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(
                            LinearGradient(colors: [Color.brandBlue.opacity(0.15), Color.brandNavy.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 22).stroke(Color.brandBlue.opacity(0.25), lineWidth: 1)
                                LinearGradient(colors: [Color.brandCyan.opacity(0.65), Color.brandBlue.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(height: 1)
                                    .padding(.horizontal, 20)
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .padding(.horizontal, 14).padding(.top, 14)

                        // Help cards
                        helpCard(icon: "book.fill", iconColor: .brandCyan, title: "Knowledge Base", subtitle: "Guides, tutorials and full documentation")
                        helpCard(icon: "play.circle.fill", iconColor: .stageText, title: "Quick Start Video", subtitle: "Get up and running in minutes")
                        helpCard(icon: "bubble.left.and.bubble.right.fill", iconColor: Color(hex: "#a78bfa"), title: "Support Group", subtitle: "Community forum and discussions")
                        helpCard(icon: "doc.text.fill", iconColor: .textTertiary, title: "Legal Agreements", subtitle: "Terms of service · Privacy policy")

                        // Social
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connect with us")
                                .font(.inter(10, weight: .heavy))
                                .tracking(1)
                                .foregroundColor(.textQuaternary)
                                .textCase(.uppercase)

                            HStack(spacing: 10) {
                                socialBtn(icon: "globe", color: .brandCyan)
                                socialBtn(icon: "camera.fill", color: Color(hex: "#ec4899"))
                                socialBtn(icon: "play.rectangle.fill", color: Color.red)
                                socialBtn(icon: "hand.thumbsup.fill", color: Color(hex: "#1877F2"))
                            }
                        }
                        .padding(16)
                        .background(
                            LinearGradient(colors: [Color.brandCyan.opacity(0.07), Color.brandBlue.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.brandCyan.opacity(0.16), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .padding(.horizontal, 14)

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func helpCard(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 44, height: 44)
                .background(iconColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(iconColor.opacity(0.2), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.inter(13.5, weight: .bold)).foregroundColor(.textPrimary)
                Text(subtitle).font(.inter(11)).foregroundColor(.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textQuaternary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 14)
    }

    private func socialBtn(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 20))
            .foregroundColor(color)
            .frame(width: 54, height: 54)
            .background(Color.brandCyan.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.brandCyan.opacity(0.18), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
