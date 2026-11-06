import SwiftUI

struct SignupView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var langMgr: LanguageManager
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
                            RadialGradient(colors: [Color.brandCyan.opacity(0.05), .clear], center: .init(x: 0.15, y: 0.2), startRadius: 0, endRadius: 90).ignoresSafeArea()

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
                            .frame(height: 268)

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

                                Text(langMgr.t("dashboard.tagline"))
                                    .font(.inter(9, weight: .bold))
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
                            ZStack(alignment: .top) {
                                Rectangle()
                                    .fill(Color.brandBlue.opacity(0.2))
                                    .frame(height: 1)
                                TopGlowBar()
                            }

                            VStack(alignment: .leading, spacing: 13) {
                                Text(langMgr.t("auth.createAccount"))
                                    .font(.inter(23, weight: .heavy))
                                    .foregroundColor(.textPrimary)
                                    .padding(.top, 28)

                                Text(langMgr.t("auth.joinThousands"))
                                    .font(.inter(13))
                                    .foregroundColor(.textSecondary)
                                    .padding(.bottom, 4)

                                HStack(spacing: 10) {
                                    ScrivanoTextField(label: langMgr.t("auth.firstName"), text: $firstName, placeholder: "John")
                                    ScrivanoTextField(label: langMgr.t("auth.lastName"), text: $lastName, placeholder: "Cabrera")
                                }

                                ScrivanoTextField(label: langMgr.t("auth.email"), text: $email, placeholder: "you@example.com", keyboardType: .emailAddress)

                                ScrivanoTextField(label: langMgr.t("auth.password"), text: $password, placeholder: langMgr.t("auth.minChars"), isSecure: true)

                                ScrivanoTextField(label: langMgr.t("auth.confirmPassword"), text: $confirmPassword, placeholder: langMgr.t("auth.retypePassword"), isSecure: true)

                                if !confirmPassword.isEmpty && password != confirmPassword {
                                    Text(langMgr.t("auth.passwordsDontMatch"))
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
                                        Text(auth.isLoading ? langMgr.t("auth.creating") : langMgr.t("auth.createAccountBtn"))
                                    }
                                }
                                .primaryButtonStyle()
                                .disabled(!canSubmit || auth.isLoading)
                                .padding(.top, 4)

                                if showAgreementError {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.system(size: 13))
                                        Text(langMgr.t("auth.mustAgree"))
                                            .font(.inter(12))
                                    }
                                    .foregroundColor(.danger)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, -4)
                                }

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
                                        Text(langMgr.t("auth.agree"))
                                            .font(.inter(12))
                                            .foregroundColor(Color.white.opacity(0.38))
                                        Button(langMgr.t("auth.legalAgreements")) {
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
                                    Text(langMgr.t("auth.haveAccount"))
                                        .font(.inter(12))
                                        .foregroundColor(.textQuaternary)
                                    Button(langMgr.t("auth.signInShort")) { dismiss() }
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
        }
        .fullScreenCover(isPresented: $showVerify) {
            VerifyCodeView(email: email, onVerified: { dismiss() })
        }
    }
}
