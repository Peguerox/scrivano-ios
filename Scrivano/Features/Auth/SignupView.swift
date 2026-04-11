import SwiftUI

struct SignupView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var agreed = false
    @State private var showVerify = false
    @State private var showAgreementError = false

    var canSubmit: Bool {
        !firstName.isEmpty && !email.isEmpty
        && password.count >= 6
        && password == confirmPassword
    }

    var body: some View {
        ZStack {
            // Same background as LoginView
            LinearGradient(
                colors: [Color(hex: "#060e1e"), Color(hex: "#040a16")],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero
                    ZStack {
                        RadialGradient(colors: [Color.brandBlue.opacity(0.22), .clear], center: .init(x: 0.5, y: 0.8), startRadius: 0, endRadius: 200).ignoresSafeArea()
                        RadialGradient(colors: [Color.brandCyan.opacity(0.05), .clear], center: .init(x: 0.15, y: 0.2), startRadius: 0, endRadius: 90).ignoresSafeArea()

                        // Grid
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
                            .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 0, endRadius: 220))
                        }
                        .frame(height: 228)

                        // Bottom fade
                        VStack {
                            Spacer()
                            LinearGradient(colors: [.clear, Color(hex: "#040a16")], startPoint: .top, endPoint: .bottom)
                                .frame(height: 100)
                        }

                        // Back button
                        VStack {
                            HStack {
                                Button(action: { dismiss() }) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.brandCyan)
                                        .frame(width: 36, height: 36)
                                        .background(Color.white.opacity(0.07))
                                        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                                        .clipShape(Circle())
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 58)
                            Spacer()
                        }

                        // Logo
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
                                .font(.inter(9, weight: .bold))
                                .tracking(2.5)
                                .foregroundColor(Color.brandCyan.opacity(0.45))
                                .padding(.top, 5)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 28)
                    }
                    .frame(height: 228)

                    // Card
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack(alignment: .top) {
                            Rectangle()
                                .fill(Color.brandBlue.opacity(0.2))
                                .frame(height: 1)
                            TopGlowBar()
                        }

                        VStack(alignment: .leading, spacing: 13) {
                            Text("Create Account")
                                .font(.inter(23, weight: .heavy))
                                .foregroundColor(.textPrimary)
                                .padding(.top, 28)

                            Text("Join thousands of professionals")
                                .font(.inter(13))
                                .foregroundColor(.textSecondary)
                                .padding(.bottom, 4)

                            // First / Last name side by side
                            HStack(spacing: 10) {
                                ScrivanoTextField(label: "First Name", text: $firstName, placeholder: "Juan")
                                ScrivanoTextField(label: "Last Name", text: $lastName, placeholder: "García")
                            }

                            ScrivanoTextField(label: "Email", text: $email, placeholder: "you@example.com", keyboardType: .emailAddress)

                            ScrivanoTextField(label: "Password", text: $password, placeholder: "Min 6 characters", isSecure: true)

                            ScrivanoTextField(label: "Confirm Password", text: $confirmPassword, placeholder: "Retype password", isSecure: true)

                            if !confirmPassword.isEmpty && password != confirmPassword {
                                Text("Passwords don't match")
                                    .font(.inter(11))
                                    .foregroundColor(.danger)
                                    .padding(.top, -6)
                            }

                            if let err = auth.errorMessage {
                                Text(err)
                                    .font(.inter(12))
                                    .foregroundColor(.danger)
                                    .padding(.vertical, 2)
                            }

                            Button {
                                guard agreed else {
                                    showAgreementError = true
                                    return
                                }
                                showAgreementError = false
                                Task {
                                    await auth.register(email: email, password: password, firstName: firstName, lastName: lastName)
                                    if auth.errorMessage == nil { showVerify = true }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if auth.isLoading { ProgressView().tint(.white).scaleEffect(0.8) }
                                    Text(auth.isLoading ? "Creating…" : "Create Account →")
                                }
                            }
                            .primaryButtonStyle()
                            .disabled(!canSubmit || auth.isLoading)
                            .padding(.top, 4)

                            if showAgreementError {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 13))
                                    Text("You must agree to our Legal Agreements to continue.")
                                        .font(.inter(12))
                                }
                                .foregroundColor(.danger)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, -4)
                            }

                            // Terms
                            HStack(alignment: .top, spacing: 10) {
                                Button { agreed.toggle() } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(agreed
                                                ? LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                : LinearGradient(colors: [Color.brandBlue.opacity(0.06), Color.brandBlue.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                                            .frame(width: 18, height: 18)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.brandBlue.opacity(0.55), lineWidth: 1.5))
                                        if agreed {
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

                            HStack {
                                Spacer()
                                Text("Already have an account? ")
                                    .font(.inter(12))
                                    .foregroundColor(.textQuaternary)
                                Button("Sign In") { dismiss() }
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
        .fullScreenCover(isPresented: $showVerify) {
            VerifyCodeView(email: email, onVerified: { dismiss() })
        }
    }
}
