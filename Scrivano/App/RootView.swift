import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var lockMgr: SecurityLockManager
    @ObservedObject private var recorder = AudioRecorderManager.shared

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            if auth.isLoggedIn || recorder.isRecording {
                DashboardView()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }

            if lockMgr.isLocked {
                LockScreenView()
                    .environmentObject(lockMgr)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.isLoggedIn)
        .animation(.easeInOut(duration: 0.25), value: lockMgr.isLocked)
    }
}
