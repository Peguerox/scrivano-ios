import Foundation
import LocalAuthentication
import SwiftUI

final class SecurityLockManager: ObservableObject {

    @Published var isLocked = false

    private let passcodeKey = "security_lock_passcode"
    private let enabledKey  = "security_lock_enabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    var hasPasscode: Bool {
        UserDefaults.standard.string(forKey: passcodeKey) != nil
    }

    // MARK: - Setup / Disable

    func setupPasscode(_ code: String) {
        UserDefaults.standard.set(code, forKey: passcodeKey)
        isEnabled = true
        isLocked  = false
    }

    func disablePasscode() {
        UserDefaults.standard.removeObject(forKey: passcodeKey)
        isEnabled = false
        isLocked  = false
    }

    // MARK: - Lock / Unlock

    func lock() {
        guard isEnabled, hasPasscode else { return }
        isLocked = true
    }

    func unlock() {
        isLocked = false
    }

    func verify(_ code: String) -> Bool {
        UserDefaults.standard.string(forKey: passcodeKey) == code
    }

    // MARK: - Biometrics

    var biometricType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    var biometricIcon: String {
        biometricType == .faceID ? "faceid" : "touchid"
    }

    var biometricAvailable: Bool {
        let ctx = LAContext()
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    func authenticateBiometric(completion: @escaping (Bool) -> Void) {
        guard biometricAvailable else { completion(false); return }
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Unlock Scrivano") { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}
