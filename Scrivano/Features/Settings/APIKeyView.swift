import SwiftUI

struct APIKeyView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    @State private var keyText: String = ""
    @State private var showKey = false
    @State private var isLoading = false
    @State private var saved = false
    @State private var errorMessage: String? = nil
    @State private var showRemoveConfirm = false

    private let api = APIClient.shared

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            VStack(spacing: 0) {
                SubScreenBar(title: "API Key", accentColor: Color(hex: "#22c55e"), onBack: { dismiss() })

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Icon + description
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "#22c55e").opacity(0.12))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "key.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(hex: "#22c55e"))
                            }
                            .padding(.top, 60)

                            VStack(spacing: 6) {
                                Text("Your OpenAI API Key")
                                    .font(.inter(18, weight: .heavy))
                                    .foregroundColor(.textPrimary)
                                Text("Your key is encrypted and stored securely on our servers. You can also set it from the web app.")
                                    .font(.inter(13))
                                    .foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .padding(.horizontal, 24)

                        // Current status
                        if auth.hasOpenAIKey {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(Color(hex: "#22c55e"))
                                Text("API key is saved")
                                    .font(.inter(13, weight: .semibold))
                                    .foregroundColor(Color(hex: "#22c55e"))
                                Spacer()
                            }
                            .padding(14)
                            .background(Color(hex: "#22c55e").opacity(0.07))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#22c55e").opacity(0.25), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 24)
                        }

                        // Error message
                        if let err = errorMessage {
                            Text(err)
                                .font(.inter(12))
                                .foregroundColor(.danger)
                                .padding(.horizontal, 24)
                        }

                        // Input field
                        VStack(alignment: .leading, spacing: 8) {
                            Text(auth.hasOpenAIKey ? "Replace Key" : "Enter Key")
                                .font(.inter(10, weight: .heavy))
                                .foregroundColor(.textQuaternary)
                                .tracking(1)
                                .textCase(.uppercase)
                                .padding(.horizontal, 4)

                            ZStack(alignment: .trailing) {
                                Group {
                                    if showKey {
                                        TextField("sk-...", text: $keyText)
                                    } else {
                                        SecureField("sk-...", text: $keyText)
                                    }
                                }
                                .font(.inter(14))
                                .foregroundColor(.textPrimary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .padding(.trailing, 40)
                                .background(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: 14))

                                Button { showKey.toggle() } label: {
                                    Image(systemName: showKey ? "eye.slash" : "eye")
                                        .font(.system(size: 15))
                                        .foregroundColor(.textQuaternary)
                                        .padding(.trailing, 14)
                                }
                            }
                        }
                        .padding(.horizontal, 24)

                        // Save button
                        VStack(spacing: 10) {
                            Button {
                                Task { await saveKey() }
                            } label: {
                                HStack(spacing: 8) {
                                    if isLoading {
                                        ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(0.8)
                                    } else if saved {
                                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                                    }
                                    Text(saved ? "Saved!" : (auth.hasOpenAIKey ? "Update Key" : "Save Key"))
                                        .font(.inter(15, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(colors: [Color(hex: "#16a34a"), Color(hex: "#22c55e")],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(color: Color(hex: "#22c55e").opacity(0.3), radius: 12, y: 4)
                            }
                            .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || saved)
                            .opacity(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

                            if auth.hasOpenAIKey {
                                Button { showRemoveConfirm = true } label: {
                                    Text("Remove Key")
                                        .font(.inter(14, weight: .semibold))
                                        .foregroundColor(.danger)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                }
                                .disabled(isLoading)
                            }
                        }
                        .padding(.horizontal, 24)

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            if let status = try? await api.getOpenAIKeyStatus() {
                auth.hasOpenAIKey = status.hasKey
            }
        }
        .confirmationDialog("Remove API Key?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task { await removeKey() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your OpenAI key will be deleted from the server.")
        }
    }

    private func saveKey() async {
        let trimmed = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await api.saveOpenAIKey(trimmed)
            auth.hasOpenAIKey = true
            withAnimation { saved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func removeKey() async {
        isLoading = true
        errorMessage = nil
        do {
            try await api.deleteOpenAIKey()
            auth.hasOpenAIKey = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
