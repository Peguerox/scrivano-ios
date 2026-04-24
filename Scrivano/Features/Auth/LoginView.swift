import SwiftUI
import GoogleSignInSwift
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var showSignup = false
    @State private var showForgot = false
    @State private var showVerify = false
    @State private var socialError: String?
    @State private var socialErrorIsInfo: Bool = false
    @State private var agreedToTerms = true

    private let socialAuth = SocialAuthManager.shared

    var body: some View {
        ZStack {
            // Background — darker gradient matching HTML
            LinearGradient(
                colors: [Color(hex: "#060e1e"), Color(hex: "#040a16")],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero
                    ZStack {
                        // Radial glow blobs — subtle, matching HTML
                        RadialGradient(colors: [Color.brandBlue.opacity(0.22), .clear], center: .init(x: 0.5, y: 0.8), startRadius: 0, endRadius: 200).ignoresSafeArea()
                        RadialGradient(colors: [Color.brandCyan.opacity(0.05), .clear], center: .init(x: 0.85, y: 0.2), startRadius: 0, endRadius: 90).ignoresSafeArea()

                        // Grid overlay
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
                                RadialGradient(
                                    colors: [.black, .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 220
                                )
                            )
                        }
                        .frame(height: 268)

                        // Fade bottom
                        VStack {
                            Spacer()
                            LinearGradient(colors: [.clear, Color(hex: "#040a16")], startPoint: .top, endPoint: .bottom)
                                .frame(height: 120)
                        }

                        // Logo
                        VStack(spacing: 0) {
                            // Neon logo image with outer glow
                            ZStack {
                                Circle()
                                    .fill(Color.brandBlue.opacity(0.18))
                                    .frame(width: 112, height: 112)
                                    .blur(radius: 14)
                                Circle()
                                    .fill(Color.brandCyan.opacity(0.08))
                                    .frame(width: 90, height: 90)
                                    .blur(radius: 8)
                                Image("ScrivanoLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 84, height: 84)
                                    .shadow(color: Color.brandBlue.opacity(0.6), radius: 16, y: 0)
                                    .shadow(color: Color.brandCyan.opacity(0.25), radius: 32, y: 0)
                            }

                            Text("SCRIVANO")
                                .font(.system(size: 24, weight: .heavy))
                                .tracking(6)
                                .foregroundStyle(
                                    LinearGradient(colors: [.white, Color(hex: "#7dd3fc"), Color.brandCyan], startPoint: .leading, endPoint: .trailing)
                                )
                                .padding(.top, 8)

                            Text("RECORD · TRANSCRIBE · GENERATE")
                                .font(.inter(10, weight: .bold))
                                .tracking(2.5)
                                .foregroundColor(Color.brandCyan.opacity(0.45))
                                .padding(.top, 5)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 28)
                    }
                    .frame(height: 268)

                    // Card
                    VStack(alignment: .leading, spacing: 0) {
                        // Full-width top border + gradient glow line
                        ZStack(alignment: .top) {
                            Rectangle()
                                .fill(Color.brandBlue.opacity(0.2))
                                .frame(height: 1)
                            TopGlowBar()
                        }

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
                                    Text(auth.isLoading ? "Signing in…" : "Sign In →")
                                }
                            }
                            .primaryButtonStyle()
                            .disabled(auth.isLoading || email.isEmpty || password.isEmpty || !agreedToTerms)
                            .padding(.top, 4)

                            // Unverified email banner
                            if auth.unverifiedEmail != nil {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "envelope.badge.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.brandCyan)
                                        Text("Email not verified yet")
                                            .font(.inter(13, weight: .bold))
                                            .foregroundColor(.textPrimary)
                                    }
                                    Text("Your account exists but the email hasn't been confirmed. Check your inbox for the verification code.")
                                        .font(.inter(12))
                                        .foregroundColor(.textSecondary)
                                        .lineSpacing(3)
                                    Button {
                                        showVerify = true
                                    } label: {
                                        Text("Verify Email →")
                                            .font(.inter(13, weight: .bold))
                                            .foregroundColor(.brandCyan)
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.brandBlue.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandCyan.opacity(0.35), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .padding(.top, 4)
                            }

                            // Terms of service
                            HStack(alignment: .top, spacing: 10) {
                                Button { agreedToTerms.toggle() } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(agreedToTerms
                                                ? LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                : LinearGradient(colors: [Color.brandBlue.opacity(0.06), Color.brandBlue.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                                            .frame(width: 18, height: 18)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.brandBlue.opacity(0.55), lineWidth: 1.5))
                                        if agreedToTerms {
                                            Text("✓").font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 1)

                                HStack(spacing: 0) {
                                    Text("I agree to the ")
                                        .font(.inter(12))
                                        .foregroundColor(Color.white.opacity(0.38))
                                    Button("Legal Agreements") {
                                        if let url = URL(string: "https://app.scrivano.net/#legal") {
                                            UIApplication.shared.open(url)
                                        }
                                    }
                                    .font(.inter(12, weight: .semibold))
                                    .foregroundColor(.brandCyan)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 2)

                            // Divider
                            HStack(spacing: 10) {
                                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                Text("or continue with").font(.inter(10, weight: .bold)).foregroundColor(Color.white.opacity(0.25)).tracking(0.5).fixedSize()
                                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                            }
                            .padding(.vertical, 4)

                            // Social errors / info
                            if let err = socialError {
                                Text(err).font(.inter(12)).foregroundColor(socialErrorIsInfo ? .brandCyan : .danger)
                            }

                            // Google + Apple side by side
                            HStack(spacing: 8) {
                                // Google
                                Button {
                                    guard let vc = UIApplication.shared.connectedScenes
                                        .compactMap({ $0 as? UIWindowScene })
                                        .flatMap({ $0.windows })
                                        .first(where: { $0.isKeyWindow })?.rootViewController else { return }
                                    Task {
                                        do {
                                            let user = try await socialAuth.signInWithGoogle(presenting: vc)
                                            auth.completeLogin(user: user)
                                        } catch {
                                            let code = (error as NSError).code
                                            if code != 1001 && code != -5 { socialError = error.localizedDescription }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 7) {
                                        GoogleGIcon(size: 17)
                                        Text("Google").font(.inter(13, weight: .semibold))
                                    }
                                    .foregroundColor(Color.white.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.06))
                                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.1), lineWidth: 1.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                                }

                                // Apple
                                Button {
                                    Task {
                                        do {
                                            let user = try await socialAuth.signInWithApple()
                                            auth.completeLogin(user: user)
                                        } catch {
                                            let code = (error as NSError).code
                                            if code == 1001 || code == -5 {
                                                // User cancelled — no message needed
                                            } else if code == 1000 {
                                                socialErrorIsInfo = true
                                                socialError = "Apple ID verified! Tap Sign in with Apple once more to continue."
                                            } else {
                                                socialErrorIsInfo = false
                                                socialError = error.localizedDescription
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "apple.logo").font(.system(size: 15))
                                        Text("Apple").font(.inter(13, weight: .semibold))
                                    }
                                    .foregroundColor(Color.white.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.06))
                                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.1), lineWidth: 1.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                                }
                            }

                            HStack {
                                Spacer()
                                Text("Don't have an account? ")
                                    .font(.inter(12))
                                    .foregroundColor(.textQuaternary)
                                Button("Sign up free") { showSignup = true }
                                    .font(.inter(12, weight: .semibold))
                                    .foregroundColor(.brandCyan)
                            }
                            .padding(.top, 2)
                            .padding(.bottom, 36)
                        }
                        .padding(.horizontal, 26)
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
                    .offset(y: -28)
                }
            }
        }
        .onAppear {
            auth.errorMessage = nil
            auth.unverifiedEmail = nil
        }
        .fullScreenCover(isPresented: $showSignup) { SignupView() }
        .fullScreenCover(isPresented: $showForgot) { ForgotPasswordView() }
        .fullScreenCover(isPresented: $showVerify) {
            VerifyCodeView(email: auth.unverifiedEmail ?? email) {
                auth.unverifiedEmail = nil
            }
        }
    }
}
