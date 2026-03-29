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

    var canSubmit: Bool {
        !firstName.isEmpty && !email.isEmpty
        && password.count >= 6
        && password == confirmPassword
        && agreed
    }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            LinearGradient(colors: [Color.brandBlue.opacity(0.25), .clear], startPoint: .top, endPoint: .center).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Top bar
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
                        Text("Create Account")
                            .font(.inter(16, weight: .heavy))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Spacer().frame(width: 36)
                    }
                    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 24)

                    // Form
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Join Scrivano")
                            .font(.inter(23, weight: .heavy))
                            .foregroundColor(.textPrimary)
                        Text("Join thousands of professionals")
                            .font(.inter(13))
                            .foregroundColor(.textSecondary)
                            .padding(.bottom, 8)

                        // First / Last name row
                        HStack(spacing: 10) {
                            ScrivanoTextField(label: "First Name", text: $firstName, placeholder: "Juan")
                            ScrivanoTextField(label: "Last Name", text: $lastName, placeholder: "García")
                        }

                        ScrivanoTextField(label: "Email", text: $email, placeholder: "doctor@clinic.com", keyboardType: .emailAddress)

                        ScrivanoTextField(label: "Password", text: $password, placeholder: "Min 6 characters", isSecure: true)

                        ScrivanoTextField(label: "Retype Password", text: $confirmPassword, placeholder: "Confirm password", isSecure: true)

                        // Password mismatch hint
                        if !confirmPassword.isEmpty && password != confirmPassword {
                            Text("Passwords don't match")
                                .font(.inter(11))
                                .foregroundColor(.danger)
                        }

                        if let err = auth.errorMessage {
                            Text(err).font(.inter(12)).foregroundColor(.danger)
                        }

                        // Legal
                        HStack(alignment: .top, spacing: 10) {
                            Spacer()
                            Button { agreed.toggle() } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(agreed
                                            ? LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            : LinearGradient(colors: [Color.brandBlue.opacity(0.06), Color.brandBlue.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.brandBlue.opacity(0.55), lineWidth: 1.5))
                                        .frame(width: 18, height: 18)
                                    if agreed {
                                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundColor(.white)
                                    }
                                }
                            }
                            (Text("I agree to the ")
                                .font(.inter(12)).foregroundColor(.textQuaternary)
                            + Text("Terms of Service")
                                .font(.inter(12, weight: .semibold)).foregroundColor(.brandCyan))
                        }
                        .padding(.top, 2)

                        // Submit
                        Button {
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

                        HStack {
                            Spacer()
                            Text("Already have an account? ")
                                .font(.inter(12)).foregroundColor(.textQuaternary)
                            Button("Sign In") { dismiss() }
                                .font(.inter(12, weight: .semibold)).foregroundColor(.brandCyan)
                        }
                        .padding(.top, 2).padding(.bottom, 36)
                    }
                    .padding(.horizontal, 26)
                }
            }
        }
        .sheet(isPresented: $showVerify) {
            VerifyCodeView(email: email)
        }
    }
}
