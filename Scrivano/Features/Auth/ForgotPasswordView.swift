import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var sent = false
    @State private var loading = false

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            LinearGradient(colors: [Color.brandBlue.opacity(0.2), .clear], startPoint: .top, endPoint: .center).ignoresSafeArea()

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
                    Text("Reset Password")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Spacer().frame(width: 36)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)

                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: "#081526"), Color.appBg], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle().stroke(Color.brandCyan.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: Color.brandBlue.opacity(0.35), radius: 25, y: 10)
                    Image(systemName: sent ? "checkmark.circle.fill" : "lock.rotation")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [Color.brandCyan, Color.brandBlue], startPoint: .top, endPoint: .bottom))
                }
                .padding(.bottom, 28)

                Text(sent ? "Email sent!" : "Forgot your password?")
                    .font(.inter(18, weight: .heavy))
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 8)

                Text(sent
                    ? "Check your inbox for a reset link.\nYou can close this screen."
                    : "Enter your email and we'll send you\na link to reset your password.")
                    .font(.inter(13))
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Spacer()

                // Card
                VStack(spacing: 16) {
                    TopGlowBar()

                    if !sent {
                        VStack(spacing: 16) {
                            ScrivanoTextField(label: "Email", text: $email, placeholder: "you@example.com", keyboardType: .emailAddress)

                            Button {
                                Task {
                                    loading = true
                                    sent = await auth.forgotPassword(email: email)
                                    loading = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if loading { ProgressView().tint(.white).scaleEffect(0.8) }
                                    Text(loading ? "Sending…" : "Send Reset Link")
                                }
                            }
                            .primaryButtonStyle()
                            .disabled(email.isEmpty || loading)
                        }
                        .padding(.horizontal, 26)
                        .padding(.vertical, 28)
                    } else {
                        Button("Back to Login") { dismiss() }
                            .primaryButtonStyle()
                            .padding(.horizontal, 26)
                            .padding(.vertical, 28)
                    }
                }
                .background(Color.phoneBg.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
        }
    }
}
