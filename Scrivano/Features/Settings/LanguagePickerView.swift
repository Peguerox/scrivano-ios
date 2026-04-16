import SwiftUI

struct LanguagePickerView: View {
    @EnvironmentObject var langMgr: LanguageManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.brandCyan)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text(langMgr.t("settings.language.title"))
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    // Balance the back button
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, lang in
                                Button {
                                    langMgr.set(lang)
                                } label: {
                                    HStack(spacing: 14) {
                                        Text(lang.flag)
                                            .font(.system(size: 28))
                                            .frame(width: 44, height: 44)

                                        Text(lang.displayName)
                                            .font(.inter(15, weight: .semibold))
                                            .foregroundColor(.textPrimary)

                                        Spacer()

                                        if langMgr.language == lang {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(.brandCyan)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if index < AppLanguage.allCases.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.05))
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
                        .padding(.horizontal, 14)
                        .padding(.top, 16)

                        Text(langMgr.t("settings.language.hint"))
                            .font(.inter(12))
                            .foregroundColor(.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .padding(.top, 20)
                    }
                }
            }
        }
    }
}
