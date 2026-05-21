import SwiftUI
import GoogleSignIn
import UserNotifications
import UIKit
import RevenueCat

/// Holds mutable state that needs to survive SwiftUI struct re-renders.
private final class AppLifecycle: ObservableObject {
    var bgTaskID: UIBackgroundTaskIdentifier = .invalid

    func beginBackgroundTask() {
        guard bgTaskID == .invalid else { return }
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "ScrivanoActiveWork") { [weak self] in
            guard let self else { return }
            UIApplication.shared.endBackgroundTask(self.bgTaskID)
            self.bgTaskID = .invalid
        }
    }

    func endBackgroundTask() {
        guard bgTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTaskID)
        bgTaskID = .invalid
    }
}

@main
struct ScrivanoApp: App {
    @StateObject private var auth      = AuthManager.shared
    @StateObject private var lockMgr   = SecurityLockManager()
    @StateObject private var taskQueue = TaskQueueManager.shared
    @StateObject private var lifecycle = AppLifecycle()
    @StateObject private var langMgr   = LanguageManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Configure RevenueCat before anything else
        RevenueCatManager.configure()
        // BGTaskScheduler handlers MUST be registered before the app finishes launching
        BackgroundTaskManager.registerHandler()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        UserDefaults.standard.register(defaults: [
            "recorderQuality":     1,     // Medium
            "recorderFormat":      1,     // WAV
            "recorderBitDepth":    0,     // 16 bit
            "splittingInterval":   300,   // 5 min
            "auto_transcription":  true,
            "auto_conversion":     true,
            "compression_speed":   0,     // Normal
            "compression_mono":    false,
            "compression_silence": false
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(lockMgr)
                .environmentObject(langMgr)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    if url.scheme == "scrivano", url.host == "oauth-callback" {
                        handleOAuthCallback(url)
                    } else if url.pathExtension == "scrivano" {
                        NotificationCenter.default.post(name: .scrivanoOpenBackupFile, object: url)
                    } else {
                        GIDSignIn.sharedInstance.handle(url)
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                // Never lock while a recording is active — would hide the recording UI
                if !AudioRecorderManager.shared.isRecording {
                    lockMgr.lock()
                }
                // If we have active work (transcription queue or live recording),
                // request extra background time so iOS doesn't kill the process.
                let hasActiveWork = taskQueue.isProcessing || AudioRecorderManager.shared.isRecording
                if hasActiveWork { lifecycle.beginBackgroundTask() }
                // Schedule BGProcessingTask for any transcriptions still pending —
                // iOS will run this at an opportune time if the app is killed before they finish.
                BackgroundTaskManager.shared.scheduleIfNeeded()
            } else if phase == .active {
                // Back in foreground — release the background task if we held one.
                lifecycle.endBackgroundTask()
                // Resume any note tasks that were in-flight when the app was killed.
                NoteGenerationManager.shared.resumePendingNotes()
                // Process any files imported via the Share Extension.
                PendingImportProcessor.shared.process()
            }
        }
        .onChange(of: taskQueue.isProcessing) { processing in
            // Keep screen on while batch processing or recording — check both so stopping
            // one doesn't re-enable the idle timer while the other is still active.
            let stillRecording = AudioRecorderManager.shared.isRecording || AudioRecorderManager.shared.isPaused
            UIApplication.shared.isIdleTimerDisabled = processing || stillRecording
            // When processing finishes while in background, release the task token.
            if !processing && !AudioRecorderManager.shared.isRecording {
                lifecycle.endBackgroundTask()
            }
        }
    }

    // MARK: - OAuth deep link handler

    @MainActor
    private func handleOAuthCallback(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return }

        let params = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        let success = params["success"] == "true"
        let integrationId = params["integration"] ?? ""

        NotificationCenter.default.post(
            name: .integrationOAuthCallback,
            object: nil,
            userInfo: ["success": success, "integrationId": integrationId, "error": params["error"] ?? ""]
        )

        if success, !integrationId.isEmpty {
            Task { await IntegrationStore.shared.markConnected(integrationId: integrationId) }
        }
    }
}
