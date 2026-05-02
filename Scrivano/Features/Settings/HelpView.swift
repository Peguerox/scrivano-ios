import SwiftUI

struct HelpView: View {
    @ObservedObject private var langMgr = LanguageManager.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: langMgr.t("help.screenTitle"), accentColor: .brandCyan, onBack: { dismiss() })

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {

                        // Hero
                        ZStack(alignment: .bottomTrailing) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(langMgr.t("help.title"))
                                    .font(.inter(20, weight: .heavy))
                                    .foregroundColor(.textPrimary)
                                Text(langMgr.t("help.tutorials"))
                                    .font(.inter(12))
                                    .foregroundColor(.textTertiary)
                                    .lineSpacing(4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)

                            Text("?")
                                .font(.system(size: 80, weight: .heavy))
                                .foregroundColor(Color.brandCyan.opacity(0.07))
                                .padding(.trailing, 20).padding(.bottom, 8)
                        }
                        .background(
                            LinearGradient(colors: [Color.brandBlue.opacity(0.22), Color.brandNavy.opacity(0.10)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 22).stroke(Color.brandCyan.opacity(0.22), lineWidth: 1)
                                LinearGradient(colors: [.clear, Color.brandCyan.opacity(0.70), Color.brandBlue.opacity(0.50), .clear],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(height: 1).padding(.horizontal, 30)
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .padding(.horizontal, 14).padding(.top, 14)

                        // Section label
                        sectionLabel(langMgr.t("help.section.resources"))

                        // Help cards
                        helpCard(
                            icon: "book.fill", iconColor: .brandCyan,
                            title: langMgr.t("help.knowledgeBase"),
                            subtitle: langMgr.t("help.knowledgeBase.subtitle"),
                            url: "https://app.scrivano.net/knowledge-base"
                        )
                        helpCard(
                            icon: "play.circle.fill", iconColor: Color(hex: "#f59e0b"),
                            title: langMgr.t("help.quickStart"),
                            subtitle: langMgr.t("help.quickStart.subtitle"),
                            url: "https://youtube.com/shorts/BSp70_wfooc?feature=share"
                        )
                        helpCard(
                            icon: "doc.text.fill", iconColor: .textTertiary,
                            title: langMgr.t("help.legalAgreements"),
                            subtitle: langMgr.t("help.legalAgreements.subtitle"),
                            url: "https://app.scrivano.net/#legal"
                        )

                        // Section label
                        sectionLabel(langMgr.t("help.section.connect"))

                        helpCard(
                            icon: "globe",
                            iconColor: .brandCyan,
                            title: langMgr.t("help.website"),
                            subtitle: langMgr.t("help.website.subtitle"),
                            url: "https://app.scrivano.net/"
                        )
                        helpCard(
                            icon: "play.rectangle.fill",
                            iconColor: Color.red,
                            title: langMgr.t("help.youtube"),
                            subtitle: langMgr.t("help.youtube.subtitle"),
                            url: "https://www.youtube.com/@ScrivanoTube"
                        )
                        helpCard(
                            icon: "camera.fill",
                            iconColor: Color(hex: "#ec4899"),
                            title: langMgr.t("help.instagram"),
                            subtitle: "@scrivanosocial",
                            url: "https://www.instagram.com/scrivanosocial/"
                        )

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Section Label
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.inter(10, weight: .heavy))
            .tracking(1)
            .foregroundColor(.textQuaternary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 4)
    }

    // MARK: - Help Card
    private func helpCard(icon: String, iconColor: Color, title: String, subtitle: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            HStack(spacing: 14) {
                // Colored left accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(iconColor)
                    .frame(width: 3, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(iconColor)
                    .frame(width: 40, height: 40)
                    .background(iconColor.opacity(0.13))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(iconColor.opacity(0.25), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: iconColor.opacity(0.18), radius: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.inter(13.5, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(subtitle)
                        .font(.inter(11))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textQuaternary)
                    .padding(7)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(
                LinearGradient(colors: [iconColor.opacity(0.06), Color.clear],
                               startPoint: .leading, endPoint: .trailing)
            )
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(iconColor.opacity(0.14), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
    }

}
