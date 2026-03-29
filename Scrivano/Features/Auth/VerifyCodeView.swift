import SwiftUI
import Combine

struct VerifyCodeView: View {
    let email: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var auth: AuthManager

    @State private var digits: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedIndex: Int?
    @State private var secondsLeft = 299
    @State private var timer: Timer? = nil
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var error: String? = nil

    var code: String { digits.joined() }
    var isComplete: Bool { code.count == 6 }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            LinearGradient(colors: [Color(hex: "#a78bfa").opacity(0.12), .clear], startPoint: .top, endPoint: .center).ignoresSafeArea()

            VStack(spacing: 0) {
                // Bar
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
                    Text("Verify Code")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Spacer().frame(width: 36)
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 8)

                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: "#081526"), Color.appBg], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 100, height: 100)
                        .overlay(Circle().stroke(Color(hex: "#a78bfa").opacity(0.4), lineWidth: 1))
                        .shadow(color: Color(hex: "#a78bfa").opacity(0.25), radius: 25, y: 10)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(hex: "#a78bfa"), Color(hex: "#7c3aed")], startPoint: .top, endPoint: .bottom)
                        )
                }
                .padding(.bottom, 28)

                Text("Enter the code")
                    .font(.inter(18, weight: .heavy))
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 8)

                VStack(spacing: 4) {
                    Text("We sent a 6-digit code to")
                        .font(.inter(13))
                        .foregroundColor(.textTertiary)
                    Text(email)
                        .font(.inter(13, weight: .bold))
                        .foregroundColor(.brandCyan)
                }
                .multilineTextAlignment(.center)

                Spacer()

                // Card
                VStack(spacing: 20) {
                    TopGlowBar()

                    VStack(spacing: 20) {
                        // Countdown
                        HStack(spacing: 4) {
                            Text("The code expires in")
                                .font(.inter(12))
                                .foregroundColor(.textQuaternary)
                            Text(formattedTime)
                                .font(.inter(12, weight: .bold))
                                .foregroundColor(.brandCyan)
                        }

                        // OTP boxes
                        HStack(spacing: 10) {
                            ForEach(0..<6, id: \.self) { i in
                                OTPBox(
                                    digit: digits[i],
                                    state: otpState(for: i)
                                )
                                .onTapGesture { focusedIndex = i }
                            }
                        }

                        // Hidden text field to capture input
                        TextField("", text: Binding(
                            get: { code },
                            set: { newVal in
                                let filtered = newVal.filter(\.isNumber)
                                for i in 0..<6 {
                                    digits[i] = i < filtered.count ? String(filtered[filtered.index(filtered.startIndex, offsetBy: i)]) : ""
                                }
                                let next = min(filtered.count, 5)
                                focusedIndex = next
                            }
                        ))
                        .keyboardType(.numberPad)
                        .focused($focusedIndex, equals: 0)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)

                        if let err = error {
                            Text(err).font(.inter(12)).foregroundColor(.danger)
                        }

                        // Verify button
                        Button {
                            Task { await verify() }
                        } label: {
                            HStack(spacing: 8) {
                                if isVerifying { ProgressView().tint(.white).scaleEffect(0.8) }
                                Text(isVerifying ? "Verifying…" : "Verify →")
                            }
                            .font(.inter(15, weight: .heavy))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#7c3aed"), Color(hex: "#a78bfa"), Color(hex: "#6d28d9")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .shadow(color: Color(hex: "#a78bfa").opacity(0.4), radius: 12, y: 6)
                        }
                        .disabled(!isComplete || isVerifying)

                        // Resend
                        HStack(spacing: 4) {
                            Text("Didn't receive the code?")
                                .font(.inter(12)).foregroundColor(.textQuaternary)
                            Button {
                                Task { await resend() }
                            } label: {
                                Text(isResending ? "Sending…" : "Resend")
                                    .font(.inter(12, weight: .semibold))
                                    .foregroundColor(.brandCyan)
                            }
                            .disabled(isResending || secondsLeft > 240)
                        }
                        .padding(.bottom, 36)
                    }
                    .padding(.horizontal, 26)
                }
                .background(Color.phoneBg.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
        }
        .onAppear {
            startTimer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focusedIndex = 0 }
        }
        .onDisappear { timer?.invalidate() }
    }

    // MARK: -
    private var formattedTime: String {
        let m = secondsLeft / 60
        let s = secondsLeft % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func otpState(for index: Int) -> OTPBoxState {
        if digits[index].isEmpty {
            return focusedIndex == index ? .active : .empty
        }
        return .filled
    }

    private func startTimer() {
        timer?.invalidate()
        secondsLeft = 299
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if secondsLeft > 0 { secondsLeft -= 1 }
                else { timer?.invalidate() }
            }
        }
    }

    private func verify() async {
        isVerifying = true
        error = nil
        defer { isVerifying = false }

        struct Body: Encodable { let email: String; let code: String }
        struct Res: Decodable { let success: Bool; let message: String? }

        do {
            let res = try await APIClient.shared.request(
                path: "/api/auth/confirm-code",
                method: "POST",
                body: Body(email: email, code: code),
                responseType: Res.self
            )
            if res.success {
                dismiss()
            } else {
                error = res.message ?? "Invalid code."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resend() async {
        isResending = true
        defer { isResending = false }

        struct Body: Encodable { let email: String }
        struct Res: Decodable { let success: Bool }

        do {
            let _ = try await APIClient.shared.request(
                path: "/api/auth/resend-code",
                method: "POST",
                body: Body(email: email),
                responseType: Res.self
            )
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
                .shadow(color: shadowColor, radius: 6)
                .frame(width: 44, height: 54)

            if state == .active && digit.isEmpty {
                Rectangle()
                    .fill(Color.brandCyan)
                    .frame(width: 2, height: 22)
                    .opacity(0.8)
                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: state == .active)
            } else {
                Text(digit.isEmpty ? "" : digit)
                    .font(.inter(22, weight: .heavy))
                    .foregroundColor(.textPrimary)
            }
        }
    }

    private var background: Color {
        switch state {
        case .empty:  return Color.white.opacity(0.07)
        case .active: return Color.brandBlue.opacity(0.12)
        case .filled: return Color.brandBlue.opacity(0.1)
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
        case .active: return Color.brandBlue.opacity(0.15)
        case .filled: return Color.brandBlue.opacity(0.1)
        default:      return .clear
        }
    }
}
