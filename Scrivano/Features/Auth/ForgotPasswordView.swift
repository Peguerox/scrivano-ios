import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var codeSent = false
    @State private var loading = false
    @State private var verified = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#060e1e"), Color(hex: "#040a16")],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                // Back button bar
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
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Hero
                        ZStack {
                            RadialGradient(colors: [Color.brandBlue.opacity(0.22), .clear], center: .init(x: 0.5, y: 0.8), startRadius: 0, endRadius: 200).ignoresSafeArea()

                            GeometryReader { _ in
                                Canvas { ctx, size in
                                    let spacing: CGFloat = 28
                                    let cols = Int(size.width / spacing) + 1
                                    let rows = Int(size.height / spacing) + 1
                                    var path = Path()
                                    for c in 0...cols {
                                        let x = CGFloat(c) * spacing
                                        path.move(to: CGPoint(x: x, y: 0))
                                        path.addLine(to: CGPoint(x: x, y: size.height))
                                    }
                                    for r in 0...rows {
                                        let y = CGFloat(r) * spacing
                                        path.move(to: CGPoint(x: 0, y: y))
                                        path.addLine(to: CGPoint(x: size.width, y: y))
                                    }
                                    ctx.stroke(path, with: .color(Color.brandBlue.opacity(0.22)), lineWidth: 1)
                                }
                                .mask(
                                    RadialGradient(colors: [.black, .clear], center: .center, startRadius: 0, endRadius: 220)
                                )
                            }
                            .frame(height: 240)

                            VStack {
                                Spacer()
                                LinearGradient(colors: [.clear, Color(hex: "#040a16")], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 100)
                            }

                            VStack(spacing: 0) {
                                ZStack {
                                    Circle()
                                        .fill(Color.brandBlue.opacity(0.18))
                                        .frame(width: 112, height: 112)
                                        .blur(radius: 14)
                                    Circle()
                                        .fill(Color.brandCyan.opacity(0.08))
                                        .frame(width: 90, height: 90)
                                        .blur(radius: 8)
                                    Circle()
                                        .fill(LinearGradient(
                                            colors: [Color(hex: "#081526"), Color(hex: "#03080f")],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ))
                                        .frame(width: 84, height: 84)
                                        .overlay(Circle().stroke(Color.brandBlue.opacity(0.5), lineWidth: 1))
                                        .shadow(color: Color.brandBlue.opacity(0.6), radius: 16, y: 0)
                                        .shadow(color: Color.brandCyan.opacity(0.25), radius: 32, y: 0)
                                    Image(systemName: codeSent ? "checkmark.circle" : "envelope.open.fill")
                                        .font(.system(size: 30, weight: .medium))
                                        .foregroundStyle(
                                            LinearGradient(colors: [Color.brandCyan, Color.brandBlue], startPoint: .top, endPoint: .bottom)
                                        )
                                }

                                Text(codeSent ? "CHECK YOUR INBOX" : "RESET PASSWORD")
                                    .font(.system(size: 20, weight: .heavy))
                                    .tracking(4)
                                    .foregroundStyle(
                                        LinearGradient(colors: [.white, Color(hex: "#7dd3fc"), Color.brandCyan], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .padding(.top, 8)

                                Text(codeSent ? "CODE SENT · ENTER BELOW" : "WE'LL SEND A CODE TO YOUR EMAIL")
                                    .font(.inter(9, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(Color.brandCyan.opacity(0.45))
                                    .padding(.top, 5)
                            }
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, 28)
                        }
                        .frame(height: 240)

                        // Card
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack(alignment: .top) {
                                Rectangle()
                                    .fill(Color.brandBlue.opacity(0.2))
                                    .frame(height: 1)
                                TopGlowBar()
                            }

                            VStack(alignment: .leading, spacing: 13) {
                                Text(codeSent ? "Check Your Inbox" : "Forgot Password?")
                                    .font(.inter(23, weight: .heavy))
                                    .foregroundColor(.textPrimary)
                                    .padding(.top, 28)

                                Text(codeSent
                                    ? "Enter the verification code we sent to \(email)."
                                    : "Enter your email address and we'll send you a verification code.")
                                    .font(.inter(13))
                                    .foregroundColor(.textSecondary)
                                    .lineSpacing(3)
                                    .padding(.bottom, 4)

                                if codeSent {
                                    ScrivanoTextField(label: "Enter Code Here", text: $code, placeholder: "000000")
                                    if let err = auth.errorMessage {
                                        Text(err)
                                            .font(.inter(12))
                                            .foregroundColor(.danger)
                                            .padding(.top, -6)
                                    }
                                    ScrivanoTextField(label: "New Password", text: $newPassword, placeholder: "New password", isSecure: true)
                                } else {
                                    ScrivanoTextField(label: "Email", text: $email, placeholder: "you@example.com", keyboardType: .emailAddress)
                                    if let err = auth.errorMessage {
                                        Text(err)
                                            .font(.inter(12))
                                            .foregroundColor(.danger)
                                            .padding(.top, -6)
                                    }
                                }

                                Button {
                                    Task {
                                        loading = true
                                        auth.errorMessage = nil
                                        if !codeSent {
                                            codeSent = await auth.forgotPassword(email: email)
                                        } else {
                                            let ok = await auth.verifyResetCode(email: email, code: code, newPassword: newPassword)
                                            if ok { verified = true }
                                        }
                                        loading = false
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        if loading { ProgressView().tint(.white).scaleEffect(0.8) }
                                        Text(loading
                                            ? (codeSent ? "Verifying…" : "Sending…")
                                            : (codeSent ? "Reset Password" : "Send Code"))
                                    }
                                }
                                .primaryButtonStyle()
                                .disabled((codeSent ? (code.isEmpty || newPassword.isEmpty) : email.isEmpty) || loading)
                                .padding(.top, 4)

                                if codeSent {
                                    Button("Resend Code") {
                                        Task {
                                            loading = true
                                            _ = await auth.resendResetCode(email: email)
                                            loading = false
                                        }
                                    }
                                    .font(.inter(12, weight: .medium))
                                    .foregroundColor(.brandCyan)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 2)
                                }

                                Spacer().frame(height: 36)
                            }
                            .padding(.horizontal, 20)
                        }
                        .background(Color(hex: "#050c19").opacity(0.88))
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.brandBlue.opacity(0.45), Color.brandBlue.opacity(0.15), Color.brandBlue.opacity(0.08)],
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .offset(y: -10)
                    }
                }
            }

            // Success overlay
            if verified {
                ZStack {
                    Color.black.opacity(0.75).ignoresSafeArea()
                        .transition(.opacity)

                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.brandBlue.opacity(0.18))
                                .frame(width: 100, height: 100)
                                .blur(radius: 12)
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(hex: "#081526"), Color(hex: "#03080f")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 76, height: 76)
                                .overlay(Circle().stroke(Color.brandCyan.opacity(0.5), lineWidth: 1))
                                .shadow(color: Color.brandCyan.opacity(0.5), radius: 16, y: 0)
                            Image(systemName: "checkmark")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(colors: [Color.brandCyan, Color.brandBlue], startPoint: .top, endPoint: .bottom)
                                )
                        }

                        Text("Password Changed!")
                            .font(.inter(22, weight: .heavy))
                            .foregroundColor(.textPrimary)

                        Text("Your password has been updated.\nPlease sign in with your new password.")
                            .font(.inter(13))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)

                        Button {
                            dismiss()
                        } label: {
                            Text("Back to Sign In →")
                        }
                        .primaryButtonStyle()
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                    }
                    .padding(36)
                    .background(Color(hex: "#050c19").opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.brandBlue.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 28)
                    .shadow(color: Color.brandBlue.opacity(0.25), radius: 40, y: 0)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: verified)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: verified)
    }
}
