import SwiftUI
import LocalAuthentication

// MARK: - Lock Screen

struct LockScreenView: View {
    @EnvironmentObject var lockMgr: SecurityLockManager
    @State private var entered  = ""
    @State private var shake    = false
    @State private var showError = false

    var body: some View {
        ZStack {
            Color(hex: "#030a14").ignoresSafeArea()

            VStack(spacing: 0) {

                Spacer()

                // Icon + title
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.brandCyan.opacity(0.1))
                            .frame(width: 72, height: 72)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundColor(.brandCyan)
                            .shadow(color: .brandCyan.opacity(0.6), radius: 10)
                    }
                    Text("Scrivano")
                        .font(.inter(22, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Text("Enter your PIN to continue")
                        .font(.inter(13))
                        .foregroundColor(.textTertiary)
                }

                // PIN dots
                HStack(spacing: 22) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i < entered.count ? Color.brandCyan : Color.white.opacity(0.18))
                            .frame(width: 16, height: 16)
                            .shadow(color: i < entered.count ? Color.brandCyan.opacity(0.8) : .clear, radius: 6)
                            .animation(.spring(response: 0.2), value: entered.count)
                    }
                }
                .modifier(ShakeEffect(trigger: shake))
                .padding(.top, 36)
                .frame(height: 44)

                // Error label
                Text(showError ? "Incorrect PIN" : " ")
                    .font(.inter(12, weight: .semibold))
                    .foregroundColor(.danger)
                    .padding(.top, 6)
                    .animation(.easeInOut(duration: 0.2), value: showError)

                Spacer()

                // Number pad
                numberPad
                    .padding(.bottom, 52)
            }
        }
        .onAppear { tryBiometric() }
    }

    // MARK: - Number pad

    private var numberPad: some View {
        VStack(spacing: 16) {
            ForEach([["1","2","3"], ["4","5","6"], ["7","8","9"]], id: \.self) { row in
                HStack(spacing: 20) {
                    ForEach(row, id: \.self) { numButton($0) }
                }
            }
            HStack(spacing: 20) {
                // Biometric
                Button { tryBiometric() } label: {
                    Image(systemName: lockMgr.biometricIcon)
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(lockMgr.biometricAvailable ? .textSecondary : .clear)
                        .frame(width: 76, height: 76)
                }
                .disabled(!lockMgr.biometricAvailable)

                numButton("0")

                // Delete
                Button {
                    guard !entered.isEmpty else { return }
                    entered.removeLast()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(.textSecondary)
                        .frame(width: 76, height: 76)
                }
            }
        }
    }

    private func numButton(_ digit: String) -> some View {
        Button {
            guard entered.count < 4 else { return }
            entered.append(digit)
            if entered.count == 4 { verifyPin() }
        } label: {
            Text(digit)
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.textPrimary)
                .frame(width: 76, height: 76)
                .background(Color.white.opacity(0.07))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    // MARK: - Logic

    private func tryBiometric() {
        lockMgr.authenticateBiometric { success in
            if success { lockMgr.unlock() }
        }
    }

    private func verifyPin() {
        if lockMgr.verify(entered) {
            lockMgr.unlock()
        } else {
            withAnimation(.default) { shake = true }
            showError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                shake = false
                entered = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showError = false
            }
        }
    }
}

// MARK: - Shake effect

struct ShakeEffect: ViewModifier {
    var trigger: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: trigger ? -10 : 0)
            .animation(
                trigger
                    ? .interpolatingSpring(stiffness: 600, damping: 10)
                    : .default,
                value: trigger
            )
    }
}

// MARK: - PIN Setup Sheet

struct PinSetupView: View {
    @EnvironmentObject var lockMgr: SecurityLockManager
    @Environment(\.dismiss) var dismiss

    @State private var step: Step = .enter
    @State private var first  = ""
    @State private var second = ""
    @State private var shake  = false
    @State private var mismatch = false

    enum Step { case enter, confirm }

    private var current: Binding<String> {
        step == .enter ? $first : $second
    }

    private var prompt: String {
        step == .enter ? "Enter a 4-digit PIN" : "Confirm your PIN"
    }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text("Security Lock")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Spacer().frame(width: 36)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                Spacer()

                // Step indicator
                HStack(spacing: 8) {
                    stepDot(filled: true)
                    stepDot(filled: step == .confirm)
                }
                .padding(.bottom, 24)

                // Prompt
                Text(prompt)
                    .font(.inter(16, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 28)

                // PIN dots
                HStack(spacing: 22) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i < current.wrappedValue.count ? Color.brandCyan : Color.white.opacity(0.18))
                            .frame(width: 16, height: 16)
                            .shadow(color: i < current.wrappedValue.count ? Color.brandCyan.opacity(0.8) : .clear, radius: 6)
                            .animation(.spring(response: 0.2), value: current.wrappedValue.count)
                    }
                }
                .modifier(ShakeEffect(trigger: shake))

                Text(mismatch ? "PINs don't match — try again" : " ")
                    .font(.inter(12, weight: .semibold))
                    .foregroundColor(.danger)
                    .padding(.top, 10)
                    .animation(.easeInOut(duration: 0.2), value: mismatch)

                Spacer()

                // Number pad
                VStack(spacing: 16) {
                    ForEach([["1","2","3"], ["4","5","6"], ["7","8","9"]], id: \.self) { row in
                        HStack(spacing: 20) {
                            ForEach(row, id: \.self) { setupNumButton($0) }
                        }
                    }
                    HStack(spacing: 20) {
                        Spacer().frame(width: 76)
                        setupNumButton("0")
                        Button {
                            guard !current.wrappedValue.isEmpty else { return }
                            current.wrappedValue.removeLast()
                        } label: {
                            Image(systemName: "delete.left")
                                .font(.system(size: 22, weight: .light))
                                .foregroundColor(.textSecondary)
                                .frame(width: 76, height: 76)
                        }
                    }
                }
                .padding(.bottom, 52)
            }
        }
    }

    private func setupNumButton(_ digit: String) -> some View {
        Button {
            guard current.wrappedValue.count < 4 else { return }
            current.wrappedValue.append(digit)
            if current.wrappedValue.count == 4 { advance() }
        } label: {
            Text(digit)
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.textPrimary)
                .frame(width: 76, height: 76)
                .background(Color.white.opacity(0.07))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func stepDot(filled: Bool) -> some View {
        Circle()
            .fill(filled ? Color.brandCyan : Color.white.opacity(0.2))
            .frame(width: 8, height: 8)
    }

    private func advance() {
        if step == .enter {
            step = .confirm
        } else {
            if first == second {
                lockMgr.setupPasscode(first)
                dismiss()
            } else {
                withAnimation { shake = true }
                mismatch = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    shake = false
                    second = ""
                    step = .enter
                    first = ""
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { mismatch = false }
            }
        }
    }
}

// MARK: - PIN Verify (used to confirm before disabling the lock)

struct PinVerifyView: View {
    @EnvironmentObject var lockMgr: SecurityLockManager
    @Environment(\.dismiss) var dismiss

    @State private var entered  = ""
    @State private var shake    = false
    @State private var showError = false

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text("Disable Security Lock")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Spacer().frame(width: 36)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.danger.opacity(0.1))
                        .frame(width: 64, height: 64)
                    Image(systemName: "lock.open")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.danger)
                        .shadow(color: Color.danger.opacity(0.5), radius: 8)
                }
                .padding(.bottom, 16)

                Text("Enter your PIN to disable")
                    .font(.inter(15, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 28)

                // PIN dots
                HStack(spacing: 22) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i < entered.count ? Color.danger : Color.white.opacity(0.18))
                            .frame(width: 16, height: 16)
                            .shadow(color: i < entered.count ? Color.danger.opacity(0.8) : .clear, radius: 6)
                            .animation(.spring(response: 0.2), value: entered.count)
                    }
                }
                .modifier(ShakeEffect(trigger: shake))

                Text(showError ? "Incorrect PIN" : " ")
                    .font(.inter(12, weight: .semibold))
                    .foregroundColor(.danger)
                    .padding(.top, 10)
                    .animation(.easeInOut(duration: 0.2), value: showError)

                Spacer()

                // Number pad
                VStack(spacing: 16) {
                    ForEach([["1","2","3"], ["4","5","6"], ["7","8","9"]], id: \.self) { row in
                        HStack(spacing: 20) {
                            ForEach(row, id: \.self) { verifyNumButton($0) }
                        }
                    }
                    HStack(spacing: 20) {
                        Spacer().frame(width: 76)
                        verifyNumButton("0")
                        Button {
                            guard !entered.isEmpty else { return }
                            entered.removeLast()
                        } label: {
                            Image(systemName: "delete.left")
                                .font(.system(size: 22, weight: .light))
                                .foregroundColor(.textSecondary)
                                .frame(width: 76, height: 76)
                        }
                    }
                }
                .padding(.bottom, 52)
            }
        }
    }

    private func verifyNumButton(_ digit: String) -> some View {
        Button {
            guard entered.count < 4 else { return }
            entered.append(digit)
            if entered.count == 4 { verify() }
        } label: {
            Text(digit)
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.textPrimary)
                .frame(width: 76, height: 76)
                .background(Color.white.opacity(0.07))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func verify() {
        if lockMgr.verify(entered) {
            lockMgr.disablePasscode()
            dismiss()
        } else {
            withAnimation(.default) { shake = true }
            showError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                shake = false
                entered = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showError = false }
        }
    }
}
