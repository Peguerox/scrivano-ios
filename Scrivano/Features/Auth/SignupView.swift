import SwiftUI

struct SignupView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var firstName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var agreed = false
    @State private var registered = false

    var canSubmit: Bool { !firstName.isEmpty && !email.isEmpty && password.count >= 6 && agreed }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            LinearGradient(colors: [Color.brandBlue.opacity(0.25), .clear], startPoint: .top, endPoint: .center).ignoresSafeArea()

            if registered {
                // Success state
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.success.opacity(0.12))
                            .frame(width: 100, height: 100)
                            .overlay(Circle().stroke(Color.success.opacity(0.4), lineWidth: 1))
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.success)
                    }
                    Text("Check your email")
                        .font(.inter(20, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Text("We've sent a confirmation link to \(email).\nClick it to activate your account.")
                        .font(.inter(13))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    Button("Done") { dismiss() }
                        .primaryButtonStyle()
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                }
                .padding(32)
            } else {
                ScrollView(showsIndicators: false) {
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
                            Text("Create Account")
                                .font(.inter(16, weight: .heavy))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Spacer().frame(width: 36)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                        // Form card
                        VStack(alignment: .leading, spacing: 13) {
                            Text("Join Scrivano")
                                .font(.inter(23, weight: .heavy))
                                .foregroundColor(.textPrimary)
                            Text("Start transcribing and generating notes with AI")
                                .font(.inter(13))
                                .foregroundColor(.textSecondary)
                                .padding(.bottom, 11)

                            ScrivanoTextField(label: "First Name", text: $firstName, placeholder: "Your name")

                            ScrivanoTextField(label: "Email", text: $email, placeholder: "you@example.com", keyboardType: .emailAddress)

                            ScrivanoTextField(label: "Password", text: $password, placeholder: "Min 6 characters", isSecure: true)

                            if let err = auth.errorMessage {
                                Text(err)
                                    .font(.inter(12))
                                    .foregroundColor(.danger)
                                    .padding(.vertical, 2)
                            }

                            // Legal checkbox
                            HStack(alignment: .top, spacing: 10) {
                                Spacer()
                                Button { agreed.toggle() } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(agreed ? LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [Color.brandBlue.opacity(0.06), Color.brandBlue.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.brandBlue.opacity(0.55), lineWidth: 1.5))
                                            .frame(width: 18, height: 18)
                                        if agreed {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .heavy))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                Text("I agree to the ")
                                    .font(.inter(12))
                                    .foregroundColor(.textQuaternary) +
                                Text("Terms of Service")
                                    .font(.inter(12, weight: .semibold))
                                    .foregroundColor(.brandCyan) +
                                Text(" and ")
                                    .font(.inter(12))
                                    .foregroundColor(.textQuaternary) +
                                Text("Privacy Policy")
                                    .font(.inter(12, weight: .semibold))
                                    .foregroundColor(.brandCyan)
                            }
                            .padding(.top, 4)

                            Button {
                                Task {
                                    await auth.register(email: email, password: password, firstName: firstName)
                                    if auth.errorMessage == nil { registered = true }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if auth.isLoading { ProgressView().tint(.white).scaleEffect(0.8) }
                                    Text(auth.isLoading ? "Creating…" : "Create Account")
                                }
                            }
                            .primaryButtonStyle()
                            .disabled(!canSubmit || auth.isLoading)
                            .padding(.top, 8)
                            .padding(.bottom, 36)
                        }
                        .padding(.horizontal, 26)
                    }
                }
            }
        }
    }
}
