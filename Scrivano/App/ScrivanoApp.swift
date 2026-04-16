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
            "recorderQuality":   1,    // Medium
            "recorderFormat":    1,    // WAV
            "recorderBitDepth":  0,    // 16 bit
            "splittingInterval": 1080, // 18:00 — under Vercel 4.5 MB upload limit
            "auto_transcription": true,
            "auto_conversion":    true
        ])
        // One-time migration: force correct defaults for devices that had old values stored
        if !UserDefaults.standard.bool(forKey: "recorderDefaultsV1Migrated") {
            UserDefaults.standard.set(1,    forKey: "recorderFormat")
            UserDefaults.standard.set(1080, forKey: "splittingInterval")
            UserDefaults.standard.set(true, forKey: "recorderDefaultsV1Migrated")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(lockMgr)
                .environmentObject(langMgr)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    if url.pathExtension == "scrivano" {
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
}
