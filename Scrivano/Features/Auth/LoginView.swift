import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var showSignup = false
    @State private var showForgot = false

    var body: some View {
        ZStack {
            // Background gradient
            Color.phoneBg.ignoresSafeArea()
            LinearGradient(
                colors: [Color.brandBlue.opacity(0.35), .clear, Color.brandNavy.opacity(0.25), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero
                    ZStack {
                        // Grid overlay
                        GeometryReader { geo in
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
                                ctx.stroke(path, with: .color(Color.brandBlue.opacity(0.1)), lineWidth: 1)
                            }
                            .mask(
                                RadialGradient(
                                    colors: [.black, .clear],
                                    center: .center,
                                    startRadius: 40,
                                    endRadius: 160
                                )
                            )
                        }
                        .frame(height: 268)

                        // Fade bottom
                        VStack {
                            Spacer()
                            LinearGradient(colors: [.clear, Color.phoneBg], startPoint: .top, endPoint: .bottom)
                                .frame(height: 100)
                        }

                        // Logo
                        VStack(spacing: 0) {
                            // App icon ring
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color(hex: "#081526"), Color.appBg], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 84, height: 84)
                                    .shadow(color: Color.brandBlue.opacity(0.3), radius: 30, y: 10)
                                    .overlay(Circle().stroke(Color.brandBlue.opacity(0.5), lineWidth: 1))

                                Image(systemName: "mic.fill")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(colors: [Color.brandCyan, Color.brandBlue], startPoint: .top, endPoint: .bottom)
                                    )
                            }

                            Text("SCRIVANO")
                                .font(.system(size: 24, weight: .heavy, design: .default))
                                .tracking(6)
                                .foregroundStyle(
                                    LinearGradient(colors: [.white, Color(hex: "#7dd3fc"), Color.brandCyan], startPoint: .leading, endPoint: .trailing)
                                )
                                .padding(.top, 16)

                            Text("AI TRANSCRIPTION")
                                .font(.inter(10, weight: .bold))
                                .tracking(2.5)
                                .foregroundColor(Color.brandCyan.opacity(0.45))
                                .padding(.top, 5)
                        }
                        .padding(.top, 40)
                    }
                    .frame(height: 268)

                    // Card
                    VStack(alignment: .leading, spacing: 0) {
                        TopGlowBar()

                        VStack(alignment: .leading, spacing: 13) {
                            Text("Welcome back")
                                .font(.inter(23, weight: .heavy))
                                .foregroundColor(.textPrimary)
                                .padding(.top, 28)

                            Text("Sign in to your account")
                                .font(.inter(13))
                                .foregroundColor(.textSecondary)
                                .padding(.bottom, 11)

                            ScrivanoTextField(label: "Email", text: $email, placeholder: "you@example.com", keyboardType: .emailAddress)

                            VStack(alignment: .trailing, spacing: 0) {
                                ScrivanoTextField(label: "Password", text: $password, placeholder: "••••••••", isSecure: true)
                                Button("Forgot password?") { showForgot = true }
                                    .font(.inter(12, weight: .medium))
                                    .foregroundColor(.brandCyan)
                                    .padding(.top, 8)
                            }

                            if let err = auth.errorMessage {
                                Text(err)
                                    .font(.inter(12))
                                    .foregroundColor(.danger)
                                    .padding(.vertical, 4)
                            }

                            Button {
                                Task { await auth.login(email: email, password: password) }
                            } label: {
                                HStack(spacing: 8) {
                                    if auth.isLoading {
                                        ProgressView().tint(.white).scaleEffect(0.8)
                                    }
                                    Text(auth.isLoading ? "Signing in…" : "Sign In")
                                }
                            }
                            .primaryButtonStyle()
                            .disabled(auth.isLoading || email.isEmpty || password.isEmpty)
                            .padding(.top, 4)

                            // Divider
                            HStack(spacing: 10) {
                                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                Text("or").font(.inter(10, weight: .bold)).foregroundColor(Color.white.opacity(0.25)).tracking(0.5)
                                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                            }
                            .padding(.vertical, 4)

                            // Google sign in
                            Button(action: {}) {
                                HStack(spacing: 7) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 16))
                                    Text("Continue with Google")
                                        .font(.inter(13, weight: .semibold))
                                }
                                .foregroundColor(Color.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.06))
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.1), lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                            }

                            HStack {
                                Spacer()
                                Text("Don't have an account? ")
                                    .font(.inter(12))
                                    .foregroundColor(.textQuaternary)
                                Button("Sign up") { showSignup = true }
                                    .font(.inter(12, weight: .semibold))
                                    .foregroundColor(.brandCyan)
                            }
                            .padding(.top, 2)
                            .padding(.bottom, 36)
                        }
                        .padding(.horizontal, 26)
                        .background(Color.phoneBg.opacity(0.85))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .offset(y: -28)
                }
            }
        }
        .sheet(isPresented: $showSignup) { SignupView() }
        .sheet(isPresented: $showForgot) { ForgotPasswordView() }
    }
}
