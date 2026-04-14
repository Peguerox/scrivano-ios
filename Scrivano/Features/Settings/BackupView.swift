import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @ObservedObject private var manager = BackupManager.shared
    @Environment(\.dismiss) var dismiss

    // ── Create backup state ──────────────────────────────────────────────
    @State private var createPassword = ""
    @State private var createConfirm  = ""
    @State private var includeAudio   = true
    @State private var createError: String?
    @State private var backupURL: URL?
    @State private var showShareSheet = false
    @State private var isLoggingOut = false

    // ── Restore state ────────────────────────────────────────────────────
    @State private var showFilePicker = false
    @State private var pendingRestoreURL: URL?
    @State private var restorePassword = ""
    @State private var restoreError: String?
    @State private var restoreSuccess: String?
    @State private var showRestoreSheet = false
    @FocusState private var restorePwdFocused: Bool

    private var passwordsMatch: Bool {
        !createPassword.isEmpty && createPassword == createConfirm
    }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: "Backup & Restore", accentColor: .brandBlue, onBack: { dismiss() })
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.brandBlue.opacity(0.4)).frame(height: 1)
                    }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        infoCard
                        createCard
                        restoreCard
                        Spacer().frame(height: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
            }

            // Working overlay
            if manager.isWorking {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().progressViewStyle(.circular).tint(.brandCyan).scaleEffect(1.4)
                    Text(manager.progress)
                        .font(.inter(13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                .padding(28)
                .background(Color(hex: "#0d1a2a"))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }

            // Restore password overlay
            if showRestoreSheet {
                Color.black.opacity(0.65).ignoresSafeArea()
                    .onTapGesture { showRestoreSheet = false; restorePassword = ""; restoreError = nil }
                    .zIndex(10)
                VStack {
                    Spacer()
                    VStack(spacing: 18) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.brandCyan)

                        VStack(spacing: 5) {
                            Text("Enter Backup Password")
                                .font(.inter(17, weight: .bold))
                                .foregroundColor(.textPrimary)
                            if let url = pendingRestoreURL {
                                Text(url.lastPathComponent)
                                    .font(.inter(11))
                                    .foregroundColor(.textQuaternary)
                                    .lineLimit(1)
                            }
                        }

                        SecureField("Password", text: $restorePassword)
                            .font(Font.custom("Inter", size: 14))
                            .foregroundColor(Color(hex: "#e2e8f0"))
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .focused($restorePwdFocused)

                        if let err = restoreError {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.inter(12))
                                .foregroundColor(.danger)
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: 12) {
                            Button {
                                showRestoreSheet = false
                                restorePassword = ""
                                restoreError = nil
                            } label: {
                                Text("Cancel")
                                    .font(.inter(14, weight: .semibold))
                                    .foregroundColor(.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.white.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                            }
                            Button { Task { await doRestore() } } label: {
                                Text("Restore")
                                    .font(.inter(14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(
                                        restorePassword.isEmpty
                                            ? LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)], startPoint: .leading, endPoint: .trailing)
                                            : LinearGradient(colors: [.brandBlue, .brandNavy], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                            }
                            .disabled(restorePassword.isEmpty || manager.isWorking)
                        }
                    }
                    .padding(24)
                    .background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.brandCyan.opacity(0.25), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.brandCyan.opacity(0.15), radius: 20)
                    .padding(.horizontal, 24)
                    Spacer()
                }
                .zIndex(11)
            }

            // Logout overlay — shown after export when coming from logout flow
            if isLoggingOut {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().progressViewStyle(.circular).tint(.brandCyan).scaleEffect(1.4)
                    Text("Saving file and logging out…")
                        .font(.inter(13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                .padding(28)
                .background(Color(hex: "#0d1a2a"))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.brandBlue.opacity(0.35), lineWidth: 1))
            }
        }
        .navigationBarHidden(true)
        // Share sheet — shown after backup file is created
        .sheet(isPresented: $showShareSheet, onDismiss: {
            guard AuthManager.shared.pendingLogoutAfterBackup else { return }
            AuthManager.shared.pendingLogoutAfterBackup = false
            isLoggingOut = true
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                AuthManager.shared.forceLogout()
            }
        }) {
            if let url = backupURL { ShareSheetView(url: url) }
        }
        // File picker — user selects a .scrivano file
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            // Copy to temp so we keep access after the picker closes
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: tmp)
            pendingRestoreURL = FileManager.default.fileExists(atPath: tmp.path) ? tmp : url
            restoreError = nil
            restorePassword = ""
            showRestoreSheet = true
        }
        .onChange(of: showRestoreSheet) { showing in
            if showing { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { restorePwdFocused = true } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrivanoOpenBackupFile)) { note in
            guard let url = note.object as? URL else { return }
            pendingRestoreURL = url
            restoreError = nil
            restorePassword = ""
            showRestoreSheet = true
        }
    }

    // MARK: - Info card

    private var infoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.brandCyan)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your data stays on-device")
                    .font(.inter(13, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("The backup includes all collections, items, transcripts, and notes. Audio recordings are optional — including them increases file size. Everything is encrypted with your password — only you can open it.")
                    .font(.inter(11))
                    .foregroundColor(.textQuaternary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.brandBlue.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandBlue.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Create card

    private var createCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(icon: "lock.doc.fill", title: "Create Backup",
                       subtitle: "Exports all data as an encrypted .scrivano file")

            VStack(spacing: 10) {
                SecureField("Password", text: $createPassword)
                    .styledField()

                SecureField("Confirm Password", text: $createConfirm)
                    .styledField(
                        borderColor: createConfirm.isEmpty ? Color.white.opacity(0.1)
                            : passwordsMatch ? Color.green.opacity(0.4)
                            : Color.danger.opacity(0.5)
                    )
            }

            // ── Audio toggle ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $includeAudio) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Audio Files")
                            .font(.inter(13, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(includeAudio
                             ? "Backup will include all recordings — larger file size"
                             : "Text only — transcripts, notes & collections")
                            .font(.inter(11))
                            .foregroundColor(.textQuaternary)
                    }
                }
                .tint(.brandCyan)

                if !includeAudio {
                    let untranscribed = untranscribedRecordingCount
                    if untranscribed > 0 {
                        Label("\(untranscribed) recording\(untranscribed == 1 ? "" : "s") not yet transcribed — audio will be lost if excluded",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.inter(11, weight: .semibold))
                            .foregroundColor(Color(hex: "#f59e0b"))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "#f59e0b").opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "#f59e0b").opacity(0.25), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let err = createError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.inter(12))
                    .foregroundColor(.danger)
            }

            Button { Task { await doCreate() } } label: {
                Label("Create & Export Backup", systemImage: "square.and.arrow.up")
                    .font(.inter(14, weight: .bold))
                    .foregroundColor(passwordsMatch ? .white : .textQuaternary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        passwordsMatch
                            ? LinearGradient(colors: [.brandBlue, .brandNavy],
                                             startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)],
                                             startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!passwordsMatch || manager.isWorking)
            .contentShape(Rectangle())
        }
        .padding(18)
        .cardStyle(borderColor: .brandBlue.opacity(0.2))
    }

    // MARK: - Restore card

    private var restoreCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(icon: "arrow.down.doc.fill", title: "Restore Backup",
                       subtitle: "Import a .scrivano file to your device")

            if let success = restoreSuccess {
                Label(success, systemImage: "checkmark.circle.fill")
                    .font(.inter(13, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text("Existing data is kept. Duplicate collection names will be renamed automatically (e.g. \"My Collection 1\").")
                .font(.inter(11))
                .foregroundColor(.textQuaternary)
                .fixedSize(horizontal: false, vertical: true)

            Button { showFilePicker = true } label: {
                Label("Choose .scrivano File", systemImage: "doc.badge.plus")
                    .font(.inter(14, weight: .bold))
                    .foregroundColor(.brandCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.brandBlue.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandCyan.opacity(0.3), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .contentShape(Rectangle())
        }
        .padding(18)
        .cardStyle(borderColor: .brandBlue.opacity(0.2))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func cardHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.brandBlue.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(.brandCyan)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.inter(15, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.inter(11))
                    .foregroundColor(.textQuaternary)
            }
        }
    }

    // MARK: - Actions

    private var untranscribedRecordingCount: Int {
        let allRecs = LocalRecordingStore.shared.entries
        let transcribed = Set(UserDefaults.standard.stringArray(forKey: "transcribedRecordingIds") ?? [])
        return allRecs.filter { !transcribed.contains($0.id) }.count
    }

    private func doCreate() async {
        createError = nil
        do {
            let url = try await BackupManager.shared.createBackup(password: createPassword, includeAudio: includeAudio)
            backupURL = url
            showShareSheet = true
            createPassword = ""
            createConfirm  = ""
        } catch {
            createError = error.localizedDescription
        }
    }

    private func doRestore() async {
        guard let url = pendingRestoreURL else { return }
        restoreError = nil
        do {
            let count = try await BackupManager.shared.restoreBackup(from: url, password: restorePassword)
            showRestoreSheet = false
            restorePassword = ""
            pendingRestoreURL = nil
            restoreSuccess = "\(count) collection\(count == 1 ? "" : "s") restored successfully."
        } catch {
            restoreError = error.localizedDescription
        }
    }
}

// MARK: - Share Sheet

struct ShareSheetView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - View helpers

private extension View {
    func styledField(borderColor: Color = Color.white.opacity(0.1)) -> some View {
        self
            .font(Font.custom("Inter", size: 14))
            .foregroundColor(Color(hex: "#e2e8f0"))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(borderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    func cardStyle(borderColor: Color = Color.white.opacity(0.1)) -> some View {
        self
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(borderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
