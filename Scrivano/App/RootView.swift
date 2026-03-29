import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            if auth.isLoggedIn {
                DashboardView()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.isLoggedIn)
    }
}
