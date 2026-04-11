import SwiftUI

struct VerifyCodeView: View {
    let email: String
    var onVerified: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var auth: AuthManager

    @State private var digits: [String] = Array(repeating: "", count: 6)
    @FocusState private var inputFocused: Bool   // single focus state for the hidden field
    @State private var secondsLeft = 599
    @State private var timer: Timer? = nil
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var error: String? = nil
    @State private var verified = false

    var code: String { digits.joined() }
    var isComplete: Bool { code.count == 6 }
    var activeIndex: Int { min(code.count, 5) }

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

                        // Neon logo
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

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Verify Your Email")
                                .font(.inter(23, weight: .heavy))
                                .foregroundColor(.textPrimary)
                                .padding(.top, 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("We sent a 6-digit code to")
                                    .font(.inter(13))
                                    .foregroundColor(.textSecondary)
                                Text(email)
                                    .font(.inter(13, weight: .bold))
                                    .foregroundColor(.brandCyan)
                            }

                            // Countdown
                            HStack(spacing: 4) {
                                Text("Expires in")
                                    .font(.inter(12))
                                    .foregroundColor(.textQuaternary)
                                Text(formattedTime)
                                    .font(.inter(12, weight: .bold))
                                    .foregroundColor(.brandCyan)
                            }

                            // OTP boxes — tap anywhere to focus the hidden field
                            HStack(spacing: 10) {
                                ForEach(0..<6, id: \.self) { i in
                                    OTPBox(digit: digits[i], state: otpState(for: i))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .contentShape(Rectangle())
                            .onTapGesture { inputFocused = true }

                            // Hidden text field — always focused, captures all input
                            TextField("", text: Binding(
                                get: { code },
                                set: { newVal in
                                    let filtered = String(newVal.filter { $0.isLetter || $0.isNumber }.prefix(6))
                                    for i in 0..<6 {
                                        digits[i] = i < filtered.count
                                            ? String(filtered[filtered.index(filtered.startIndex, offsetBy: i)])
                                            : ""
                                    }
                                }
                            ))
                            .keyboardType(.default)
                            .autocapitalization(.allCharacters)
                            .autocorrectionDisabled()
                            .focused($inputFocused)
                            .frame(width: 1, height: 1)
                            .opacity(0.01)

                            if let err = error {
                                Text(err)
                                    .font(.inter(12))
                                    .foregroundColor(.danger)
                            }

                            Button {
                                Task { await verify() }
                            } label: {
                                HStack(spacing: 8) {
                                    if isVerifying { ProgressView().tint(.white).scaleEffect(0.8) }
                                    Text(isVerifying ? "Verifying…" : "Verify →")
                                }
                            }
                            .primaryButtonStyle()
                            .disabled(!isComplete || isVerifying)

                            HStack(spacing: 4) {
                                Text("Didn't receive it?")
                                    .font(.inter(12))
                                    .foregroundColor(.textQuaternary)
                                Button {
                                    Task { await resend() }
                                } label: {
                                    Text(isResending ? "Sending…" : "Resend Code")
                                        .font(.inter(12, weight: .semibold))
                                        .foregroundColor(.brandCyan)
                                }
                                .disabled(isResending || secondsLeft > 240)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
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
                    .offset(y: -8)
                }
            }

            // Success overlay
            if verified {
                ZStack {
                    Color.black.opacity(0.75).ignoresSafeArea()

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

                        Text("Account Created!")
                            .font(.inter(22, weight: .heavy))
                            .foregroundColor(.textPrimary)

                        Text("Your account has been verified.\nPlease sign in to get started.")
                            .font(.inter(13))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)

                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onVerified?()
                            }
                        } label: {
                            Text("Sign In →")
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
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: verified)
        .onAppear {
            startTimer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { inputFocused = true }
        }
        .onDisappear { timer?.invalidate() }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let m = secondsLeft / 60; let s = secondsLeft % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func otpState(for index: Int) -> OTPBoxState {
        if !digits[index].isEmpty { return .filled }
        return index == activeIndex && inputFocused ? .active : .empty
    }

    private func startTimer() {
        timer?.invalidate()
        secondsLeft = 599
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if secondsLeft > 0 { secondsLeft -= 1 } else { timer?.invalidate() }
            }
        }
    }

    private func verify() async {
        isVerifying = true; error = nil
        defer { isVerifying = false }
        guard let url = URL(string: APIClient.shared.baseURL + "/api/auth/confirm-code") else { return }
        do {
            struct Body: Encodable { let email: String; let confirmation_code: String }
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(Body(email: email, confirmation_code: code))
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if json["success"] as? Bool == true { verified = true }
                else { error = json["message"] as? String ?? "Invalid or expired code." }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func resend() async {
        isResending = true
        defer { isResending = false }
        guard let url = URL(string: APIClient.shared.baseURL + "/api/auth/resend-code") else { return }
        do {
            struct Body: Encodable { let email: String; let type: String }
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(Body(email: email, type: "registration"))
            let _ = try await URLSession.shared.data(for: req)
            startTimer()
        } catch {}
    }
}

// MARK: - OTP Box
enum OTPBoxState { case empty, active, filled }

struct OTPBox: View {
    let digit: String
    let state: OTPBoxState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(background)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1.5))
                .shadow(color: shadowColor, radius: 8)
                .frame(width: 44, height: 54)

            if state == .active && digit.isEmpty {
                Rectangle()
                    .fill(Color.brandCyan)
                    .frame(width: 2, height: 22)
                    .opacity(0.8)
            } else {
                Text(digit)
                    .font(.inter(22, weight: .heavy))
                    .foregroundColor(.textPrimary)
            }
        }
    }

    private var background: Color {
        switch state {
        case .empty:  return Color.white.opacity(0.07)
        case .active: return Color.brandBlue.opacity(0.12)
        case .filled: return Color.brandBlue.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch state {
        case .empty:  return Color.white.opacity(0.14)
        case .active: return Color.brandCyan
        case .filled: return Color.brandCyan.opacity(0.55)
        }
    }

    private var shadowColor: Color {
        switch state {
        case .active: return Color.brandBlue.opacity(0.35)
        case .filled: return Color.brandBlue.opacity(0.15)
        default:      return .clear
        }
    }
}
