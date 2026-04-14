import SwiftUI
import AVFoundation
import AVKit

// MARK: - AppStorage keys
private let kQuality      = "recorderQuality"   // 0=Low 1=Med 2=High 3=Max
private let kFormat       = "recorderFormat"    // 0=M4A 1=WAV
private let kGain         = "recorderGain"      // 0.0–1.0
let kBitDepth             = "recorderBitDepth"  // 0=16bit 1=24bit 2=32bit (WAV only)
let kSplitInterval        = "splittingInterval" // seconds, 0=none

struct RecordingView: View {
    let item: Item
    var onRename: ((String) -> Void)? = nil
    /// Called on the main thread after the file is safely saved to Documents.
    var onRecordingSaved: (() -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @ObservedObject private var recorder = AudioRecorderManager.shared
    @AppStorage("splittingInterval") private var splitInterval: Int = 1080
    @AppStorage("recorderFormat")    private var formatSetting: Int = 1
    @AppStorage("pocket_mode")       private var pocketMode: Bool = false

    @State private var displayName: String
    @State private var showRenameSheet  = false
    @State private var showDeleteCard   = false
    @State private var showRedoCard     = false

    // Pocket mode double-tap arm state
    @State private var pauseArmed = false
    @State private var stopArmed  = false
    @State private var pauseArmTask: Task<Void, Never>? = nil
    @State private var stopArmTask:  Task<Void, Never>? = nil

    init(item: Item,
         onRename: ((String) -> Void)? = nil,
         onRecordingSaved: (() -> Void)? = nil) {
        self.item = item
        self.onRename = onRename
        self.onRecordingSaved = onRecordingSaved
        self._displayName = State(initialValue: item.name)
    }

    private var isActivelyRecording: Bool { recorder.isRecording && !recorder.isPaused }

    private var kHzLabel: String {
        let quality = UserDefaults.standard.integer(forKey: kQuality)
        let rates = ["8 kHz", "22 kHz", "44 kHz", "96 kHz"]
        return rates[safe: quality] ?? "22 kHz"
    }

    private var splitIntervalLabel: String {
        switch splitInterval {
        case 300:  return "5 min"
        case 600:  return "10 min"
        case 900:  return "15 min"
        case 1080: return "18 min"
        case 1800: return "30 min"
        case 3600: return "1 hour"
        default:   return "\(splitInterval / 60) min"
        }
    }

    var body: some View {
        ZStack {
            if !pocketMode {
            // ── Background ────────────────────────────────────────
            Color.phoneBg.ignoresSafeArea()

            // Grid — more noticeable, full-screen
            Canvas { ctx, size in
                let spacing: CGFloat = 28
                let cols = Int(size.width / spacing) + 1
                let rows = Int(size.height / spacing) + 1
                var path = Path()
                for c in 0...cols {
                    let x = CGFloat(c) * spacing
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for r in 0...rows {
                    let y = CGFloat(r) * spacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                ctx.stroke(path, with: .color(Color.brandCyan.opacity(0.20)), lineWidth: 0.5)
            }
            .mask(
                RadialGradient(
                    colors: [.black.opacity(0.85), .black.opacity(0.25)],
                    center: .init(x: 0.5, y: 0.45),
                    startRadius: 0, endRadius: 500
                )
            )
            .ignoresSafeArea()

            // ── Main layout ───────────────────────────────────────
            VStack(spacing: 0) {

                // Top bar
                HStack {
                    Button {
                        if recorder.isRecording || recorder.isPaused {
                            recorder.isMinimized = true
                            dismiss()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.brandCyan)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.07))
                            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text("Recording")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    AirPlayButton()
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.07))
                        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        .clipShape(Circle())
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 2)

                // API key warning — shown for BYOK users who haven't set their key
                let auth = AuthManager.shared
                if auth.currentUser?.hasBYOK == true && !auth.hasOpenAIKey && !recorder.isRecording {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("No API key set — auto-transcription will not work")
                            .font(.inter(10, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#f59e0b"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#f59e0b").opacity(0.10))
                }

                // Split interval banner — shown only when a split is configured
                if splitInterval > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "scissors")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Split every \(splitIntervalLabel)")
                            .font(.inter(10, weight: .medium))
                    }
                    .foregroundColor(Color.white.opacity(0.38))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                // ── Content area ──────────────────────────────────
                VStack(spacing: 0) {
                    Spacer().frame(height: 10)

                    // Format badge — updates live when settings change
                    HStack {
                        Image(formatSetting == 1 ? "recorderWav" : "recorderM4a")
                            .resizable().scaledToFit()
                            .frame(width: 52, height: 32)
                        Spacer()
                    }
                    .padding(.horizontal, 22)

                    // Mic logo with neon glow
                    ZStack {
                        Circle()
                            .fill(Color.brandCyan.opacity(isActivelyRecording ? 0.20 : 0.05))
                            .frame(width: 220, height: 220)
                            .blur(radius: 22)
                            .animation(.easeInOut(duration: 0.5), value: isActivelyRecording)
                        Circle()
                            .fill(Color.brandBlue.opacity(isActivelyRecording ? 0.24 : 0.08))
                            .frame(width: 150, height: 150)
                            .blur(radius: 12)
                            .animation(.easeInOut(duration: 0.5), value: isActivelyRecording)

                        Image("recorderMic")
                            .resizable().scaledToFit()
                            .frame(maxWidth: 220)
                            .shadow(color: Color.brandCyan.opacity(isActivelyRecording ? 0.55 : 0.18), radius: 20)
                            .shadow(color: Color.brandBlue.opacity(isActivelyRecording ? 0.32 : 0.10), radius: 10)
                            .animation(.easeInOut(duration: 0.5), value: isActivelyRecording)
                    }
                    .frame(maxHeight: .infinity)

                    // Waveform — 2/3 width, centered
                    EQBandView(level: recorder.audioLevel, isActive: isActivelyRecording)
                        .frame(height: 72)
                        .padding(.horizontal, UIScreen.main.bounds.width / 6)

                    // Timer
                    Text(recorder.formattedTime)
                        .font(.system(size: 54, weight: .thin, design: .monospaced))
                        .foregroundColor(Color(hex: "#E6E6E6"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)

                    // Name (below timer)
                    Text(displayName)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(Color(hex: "#D3D3D3"))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)

                    // Recording · size · kHz — one line
                    HStack(spacing: 6) {
                        Text(recorder.isRecording
                             ? (recorder.isPaused ? "Paused" : "Recording")
                             : "Idle")
                            .foregroundColor(isActivelyRecording ? Color.danger : Color(hex: "#D3D3D3"))
                        Text("·")
                        HStack(spacing: 3) {
                            Image("recorderDisk")
                                .resizable().scaledToFit()
                                .frame(width: 14, height: 10)
                            Text(recorder.formattedSize)
                        }
                        Text("·")
                        Text(kHzLabel)
                    }
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(Color(hex: "#D3D3D3"))
                    .padding(.top, 6)

                    Spacer().frame(height: 12)
                }
                .frame(maxHeight: .infinity)

                // ── Bottom panel ──────────────────────────────────
                VStack(spacing: 0) {
                    // Buttons — equally spaced
                    HStack(alignment: .center) {
                        Spacer()
                        Button {
                            if recorder.isRecording || recorder.isPaused { showDeleteCard = true }
                        } label: {
                            circleBtn(image: "recorderDelete", size: 52,
                                      enabled: recorder.isRecording || recorder.isPaused)
                        }
                        Spacer()
                        Button {
                            if recorder.isRecording || recorder.isPaused { showRedoCard = true }
                        } label: {
                            circleBtn(image: "recorderRedo", size: 52,
                                      enabled: recorder.isRecording || recorder.isPaused)
                        }
                        Spacer()
                        Button {
                            if recorder.isRecording || recorder.isPaused {
                                recorder.togglePause()
                            } else {
                                recorder.requestPermissionAndStart(itemId: item.id)
                            }
                        } label: {
                            Image(isActivelyRecording ? "recorderPause" : "recorderPlay")
                                .resizable().scaledToFit()
                                .frame(width: 80, height: 80)
                        }
                        Spacer()
                        Button { stopAndTranscribe() } label: {
                            circleBtn(image: "recorderStop", size: 52,
                                      enabled: recorder.isRecording || recorder.isPaused)
                        }
                        Spacer()
                        Button { showRenameSheet = true } label: {
                            circleBtn(image: "recorderEdit", size: 52, enabled: true)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .padding(.bottom, 4)
                }
                .background(Color.clear)
            }

            // ── Delete confirmation card ───────────────────────────
            if showDeleteCard {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .onTapGesture { showDeleteCard = false }

                VStack(spacing: 20) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.danger)

                    Text("Discard Recording?")
                        .font(.inter(18, weight: .heavy))
                        .foregroundColor(.textPrimary)

                    Text("This recording will be permanently deleted and cannot be recovered.")
                        .font(.inter(13))
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button { showDeleteCard = false } label: {
                            Text("Keep")
                                .font(.inter(14, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            showDeleteCard = false
                            recorder.stopAndDiscard()
                            dismiss()
                        } label: {
                            Text("Discard")
                                .font(.inter(14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.danger)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(28)
                .background(Color.sheetBg)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.danger.opacity(0.3), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 32)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(10)
            }
            // ── Redo confirmation card ────────────────────────────
            if showRedoCard {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .onTapGesture { showRedoCard = false }

                VStack(spacing: 20) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.brandCyan)

                    Text("Restart Recording?")
                        .font(.inter(18, weight: .heavy))
                        .foregroundColor(.textPrimary)

                    Text("The current recording will be discarded and a new one will start.")
                        .font(.inter(13))
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button { showRedoCard = false } label: {
                            Text("Cancel")
                                .font(.inter(14, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            showRedoCard = false
                            recorder.restart()
                        } label: {
                            Text("Restart")
                                .font(.inter(14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.brandBlue)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(28)
                .background(Color.sheetBg)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.borderBlue, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 32)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(10)
            }
            } // end if !pocketMode
            // ── Pocket Mode overlay ───────────────────────────────
            if pocketMode {
                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack {
                        Spacer()
                        HStack {
                            // Pause / Resume — double-tap required
                            Button {
                                if pauseArmed {
                                    pauseArmTask?.cancel(); pauseArmed = false
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    recorder.togglePause()
                                } else {
                                    stopArmTask?.cancel(); stopArmed = false
                                    pauseArmed = true
                                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                    pauseArmTask = Task {
                                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                                        guard !Task.isCancelled else { return }
                                        await MainActor.run {
                                            pauseArmed = false
                                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: isActivelyRecording ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color.white.opacity(pauseArmed ? 0.55 : 0.22))
                                    .frame(width: 56, height: 56)
                                    .background(Color.white.opacity(pauseArmed ? 0.10 : 0.04))
                                    .clipShape(Circle())
                                    .animation(.easeInOut(duration: 0.15), value: pauseArmed)
                            }
                            Spacer()
                            // Stop — double-tap required
                            Button {
                                if stopArmed {
                                    stopArmTask?.cancel(); stopArmed = false
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    stopAndTranscribe()
                                } else {
                                    pauseArmTask?.cancel(); pauseArmed = false
                                    stopArmed = true
                                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                    stopArmTask = Task {
                                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                                        guard !Task.isCancelled else { return }
                                        await MainActor.run {
                                            stopArmed = false
                                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color.white.opacity(stopArmed ? 0.55 : 0.22))
                                    .frame(width: 56, height: 56)
                                    .background(Color.white.opacity(stopArmed ? 0.10 : 0.04))
                                    .clipShape(Circle())
                                    .animation(.easeInOut(duration: 0.15), value: stopArmed)
                            }
                        }
                        .padding(.horizontal, 36)
                        .padding(.bottom, 52)
                    }
                }
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: pocketMode)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showDeleteCard)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showRedoCard)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            recorder.currentItemName = item.name
            if !recorder.isRecording && !recorder.isPaused {
                recorder.requestPermissionAndStart(itemId: item.id)
            }
        }
        .onDisappear {
            // Only re-enable idle timer if recording has fully stopped and nothing is processing
            if !recorder.isRecording && !recorder.isPaused {
                UIApplication.shared.isIdleTimerDisabled = TaskQueueManager.shared.isProcessing
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameRecordingSheet(currentName: displayName) { newName in
                displayName = newName
                onRename?(newName)
            }
        }
    }

    @ViewBuilder
    private func circleBtn(image: String, size: CGFloat, enabled: Bool) -> some View {
        Image(image)
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .opacity(enabled ? 1 : 0.28)
    }

    private func stopAndTranscribe() {
        guard recorder.isRecording || recorder.isPaused else { return }
        let duration       = Double(recorder.elapsedSeconds)
        let url            = recorder.recordedFileURL
        recorder.stop()

        // ── Save to manifest immediately ─────────────────────────────
        // File is already in Documents (recorded there from byte 1).
        // We register it in the manifest right now so even if the next
        // steps fail the recording is never lost.
        if let url {
            let entry = LocalRecordingEntry(
                id: UUID().uuidString,
                itemId: item.id,
                relativePath: LocalRecordingStore.relativePath(of: url),
                createdAt: Date(),
                durationSeconds: duration
            )
            LocalRecordingStore.shared.add(entry)
            onRecordingSaved?()
            recorder.showSavedToast(itemName: item.name)
            TranscriptionManager.shared.autoTriggerIfEnabled(entry: entry, item: item)
        }

        dismiss()
    }
}

// MARK: - Recorder Settings Sheet

struct RecorderSettingsSheet: View {
    let recorder: AudioRecorderManager

    @AppStorage(kQuality) private var quality: Int = 1
    @AppStorage(kFormat)  private var format:  Int = 1
    @AppStorage(kGain)    private var gain: Double = 0.5

    @Environment(\.dismiss) var dismiss

    private let qualityLabels = ["Low", "Medium", "High", "Max"]
    private let formatLabels  = ["M4A", "WAV"]
    private let gainSettable  = AVAudioSession.sharedInstance().isInputGainSettable

    var body: some View {
        ZStack {
            Color.sheetBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Recorder Settings")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // Audio Quality
                        SectionLabel(text: "Audio Quality")
                        Picker("Quality", selection: $quality) {
                            ForEach(0..<qualityLabels.count, id: \.self) { i in
                                Text(qualityLabels[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .onChange(of: quality) { _ in }

                        Divider().background(Color.borderDefault).padding(.horizontal, 18)

                        // Audio Format
                        SectionLabel(text: "Audio Format")
                        Picker("Format", selection: $format) {
                            ForEach(0..<formatLabels.count, id: \.self) { i in
                                Text(formatLabels[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .onChange(of: format) { _ in }

                        Divider().background(Color.borderDefault).padding(.horizontal, 18)

                        // Input Gain
                        SectionLabel(text: "Input Gain")
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "mic")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textTertiary)
                                Slider(value: $gain, in: 0...1) { editing in
                                    if !editing { applyGain() }
                                }
                                .tint(.brandCyan)
                                .onChange(of: gain) { _ in applyGain() }
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.brandCyan)
                            }
                            .padding(.horizontal, 18)

                            if !gainSettable {
                                Text("Input gain is not adjustable on this device")
                                    .font(.inter(11))
                                    .foregroundColor(.textTertiary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 18)
                            } else {
                                Text(String(format: "Gain: %.0f%%", gain * 100))
                                    .font(.inter(11))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .padding(.vertical, 12)

                    }
                }
            }
        }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
    }

    private func applyGain() {
        guard gainSettable else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setInputGain(Float(gain))
    }
}

// MARK: - Rename card (centered overlay)
struct RenameRecordingSheet: View {
    let currentName: String
    var title: String = "Rename Item"
    var onRename: ((String) -> Void)?
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color(hex: "#030c1a").ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack {
                Spacer()
                VStack(spacing: 16) {
                    Text(title)
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)

                    TextField(currentName, text: $name)
                        .font(.inter(14))
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandCyan.opacity(0.35), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                        .focused($focused)
                        .onSubmit {
                            let trimmed = name.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            onRename?(trimmed)
                            dismiss()
                        }

                    HStack(spacing: 10) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .font(.inter(14, weight: .bold))
                                .foregroundColor(.textTertiary)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            let trimmed = name.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            onRename?(trimmed)
                            dismiss()
                        } label: {
                            Text("Rename")
                                .font(.inter(14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(LinearGradient(colors: [Color.brandBlue, Color.brandCyan],
                                                           startPoint: .leading, endPoint: .trailing))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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
        }
        .onAppear {
            name = currentName
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
    }
}

// MARK: - AirPlay button
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(Color.brandCyan)
        v.activeTintColor = UIColor.white
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Waveform
// Option B+A (inactive): log curve + peak-hold smoothing, scrolling 40-bar history
// To reactivate: uncomment this block, comment out EQBandView below,
// change audioLevel: Float back to audioLevels: [Float] in AudioRecorderManager,
// and swap the call site back to WaveformView(levels: recorder.audioLevels, ...)
/*
struct WaveformView: View {
    let levels: [Float]
    var isActive: Bool

    private let barCount = 40
    private let spacing: CGFloat = 3.0

    var body: some View {
        Canvas { ctx, size in
            let barWidth = (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            let midY = size.height / 2
            let baseline = Path(CGRect(x: 0, y: midY - 1, width: size.width, height: 2))
            ctx.fill(baseline, with: .color(.white.opacity(0.06)))
            for i in 0..<barCount {
                let level = CGFloat(sampleLevel(at: i))
                let h = max(4, level * size.height)
                let x = CGFloat(i) * (barWidth + spacing)
                let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                let color: Color = isActive
                    ? barColor(level: level)
                    : Color(hex: "#38d9f5").opacity(0.18 + level * 0.14)
                ctx.fill(path, with: .color(color))
            }
        }
    }

    private func sampleLevel(at i: Int) -> Float {
        guard !levels.isEmpty else { return 0.08 }
        let ratio = Float(i) / Float(barCount - 1)
        let exact = ratio * Float(levels.count - 1)
        let lo = Int(exact); let hi = min(lo + 1, levels.count - 1)
        let frac = exact - Float(lo)
        return levels[lo] * (1 - frac) + levels[hi] * frac
    }

    private func barColor(level: CGFloat) -> Color {
        let t = Double(min(max(level, 0), 1))
        return Color(red: 1.0, green: 0.85 * (1 - t), blue: 0).opacity(0.80 + t * 0.15)
    }
}
*/

// MARK: - Option C (active): EQ Band VU Meter
// 14 static bands with independent multipliers — pro VU meter look.
// Uses single audioLevel: Float published at 4 Hz.
struct EQBandView: View {
    let level: Float
    var isActive: Bool

    private let bandCount = 14
    private let spacing: CGFloat = 4.0
    private let bandMultipliers: [Float] = [0.55, 0.70, 0.85, 1.0, 0.95, 0.88, 0.80,
                                             0.75, 0.82, 0.90, 0.78, 0.65, 0.50, 0.40]

    var body: some View {
        Canvas { ctx, size in
            let barWidth = (size.width - spacing * CGFloat(bandCount - 1)) / CGFloat(bandCount)
            for i in 0..<bandCount {
                let bandLevel = CGFloat(min(level * bandMultipliers[i], 1.0))
                let h = max(4, bandLevel * size.height)
                let x = CGFloat(i) * (barWidth + spacing)
                let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                let color: Color = isActive
                    ? Color(red: 1.0, green: Double(0.85 * (1 - bandLevel)), blue: 0).opacity(0.75 + Double(bandLevel) * 0.25)
                    : Color(hex: "#38d9f5").opacity(0.15 + Double(bandLevel) * 0.20)
                ctx.fill(path, with: .color(color))
            }
        }
    }
}

// MARK: - AudioRecorderManager
@MainActor
final class AudioRecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = AudioRecorderManager()

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var isMinimized = false
    @Published var elapsedSeconds: Int = 0
    @Published var audioLevel: Float = 0.08
    private var fileSizeTick = 0
    private var smoothedLevel: Float = 0.08
    @Published var fileSize: Int64 = 0
    @Published var currentItemName: String = ""
    /// Set to the itemId each time stopAndSave() successfully saves — observed by DashboardView to refresh counts.
    @Published var lastSavedItemId: String? = nil
    /// Toast message shown while saving / after saved.
    @Published var saveMessage: String? = nil
    /// Set when a system interruption (phone call, Siri) was active — resumes on end.
    @Published var wasInterrupted = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var outputURL: URL?
    private var currentItemId: String = ""

    // MARK: - Session observers
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    private override init() {
        super.init()
        setupSessionObservers()
    }

    private func setupSessionObservers() {
        let nc = NotificationCenter.default

        // Phone calls, Siri, alarms — pause and auto-resume when they end
        interruptionObserver = nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let info = note.userInfo,
                  let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }

            if type == .began {
                // System took audio — pause our recorder to avoid silent corruption
                if self.isRecording && !self.isPaused {
                    self.recorder?.pause()
                    self.isPaused = true
                    self.wasInterrupted = true
                    self.timer?.invalidate()
                }
            } else if type == .ended {
                // System returned audio — resume if we were interrupted
                let optVal = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optVal).contains(.shouldResume)
                if self.wasInterrupted && shouldResume {
                    self.wasInterrupted = false
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self.recorder?.record()
                    self.isPaused = false
                    self.startTimer()
                }
            }
        }

        // Headphones unplugged / Bluetooth disconnect — keep recording on built-in mic
        routeChangeObserver = nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let info = note.userInfo,
                  let reasonVal = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonVal) else { return }

            // Old device removed (headphones unplugged) — reactivate session so recording continues
            if reason == .oldDeviceUnavailable && self.isRecording && !self.isPaused {
                try? AVAudioSession.sharedInstance().setActive(true)
                self.recorder?.record()
            }
        }
    }

    // MARK: - AVAudioRecorderDelegate
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Encoding error — stop cleanly so file is finalized, then restart on same item
            let itemId = self.currentItemId
            self.stop()
            if !itemId.isEmpty {
                // Brief delay then restart to recover seamlessly
                try? await Task.sleep(nanoseconds: 500_000_000)
                try? AVAudioSession.sharedInstance().setCategory(.record, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
                try? AVAudioSession.sharedInstance().setActive(true)
                self.currentItemId = itemId
                self.start()
            }
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // No action needed — finalization is handled by stop()/stopAndSave()
    }

    var formattedTime: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    var formattedSize: String {
        if fileSize < 1024 { return "\(fileSize) B" }
        if fileSize < 1_048_576 { return String(format: "%.1f KB", Double(fileSize) / 1024) }
        return String(format: "%.1f MB", Double(fileSize) / 1_048_576)
    }

    /// Returns free disk space in bytes.
    private func freeDiskSpace() -> Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs?[.systemFreeSize] as? Int64) ?? Int64.max
    }

    func requestPermissionAndStart(itemId: String) {
        // Require at least 50 MB free before starting
        guard freeDiskSpace() > 50 * 1024 * 1024 else {
            saveMessage = "Not enough disk space to record."
            return
        }
        currentItemId = itemId
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard granted, let self else { return }
            // Activate audio session off the main thread — setActive(true) can take 100-300ms
            // and would block the UI/animation if run on main.
            Task.detached(priority: .userInitiated) { [weak self] in
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.record, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
                try? session.setActive(true)
                // Keep screen on while recording
                await MainActor.run {
                    UIApplication.shared.isIdleTimerDisabled = true
                    self?.startRecorder()
                }
            }
        }
    }

    // Called after session is already active — only creates AVAudioRecorder and calls record().
    @MainActor
    private func startRecorder() {
        let quality    = UserDefaults.standard.integer(forKey: kQuality)
        let format     = UserDefaults.standard.integer(forKey: kFormat)
        let gain       = UserDefaults.standard.double(forKey: kGain)
        let sampleRate: Double = [8000.0, 22050.0, 44100.0, 96000.0][safe: quality] ?? 22050.0
        let ext        = format == 1 ? "wav" : "m4a"
        let formatID   = format == 1 ? kAudioFormatLinearPCM : kAudioFormatMPEG4AAC

        let url = LocalRecordingStore.newFileURL(itemId: currentItemId, ext: ext)
        outputURL = url

        var settings: [String: Any] = [
            AVFormatIDKey: Int(formatID),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        if format == 1 {
            let depth = [16, 24, 32][safe: UserDefaults.standard.integer(forKey: kBitDepth)] ?? 16
            settings[AVLinearPCMBitDepthKey] = depth
            settings[AVLinearPCMIsFloatKey] = depth == 32
        }

        let session = AVAudioSession.sharedInstance()
        if session.isInputGainSettable {
            try? session.setInputGain(Float(gain > 0 ? gain : 0.5))
        }
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else {
            isRecording = false
            return
        }
        rec.isMeteringEnabled = true
        rec.delegate = self
        rec.record()
        self.recorder = rec
        self.isRecording = true
        self.isPaused = false
        self.startTimer()
    }

    // Used by restart() and auto-split — session is already active, so setActive is a no-op.
    func start() {
        let quality    = UserDefaults.standard.integer(forKey: kQuality)
        let format     = UserDefaults.standard.integer(forKey: kFormat)
        let gain       = UserDefaults.standard.double(forKey: kGain)
        let sampleRate: Double = [8000.0, 22050.0, 44100.0, 96000.0][safe: quality] ?? 22050.0
        let ext        = format == 1 ? "wav" : "m4a"
        let formatID   = format == 1 ? kAudioFormatLinearPCM : kAudioFormatMPEG4AAC

        let url = LocalRecordingStore.newFileURL(itemId: currentItemId, ext: ext)
        outputURL = url

        var settings: [String: Any] = [
            AVFormatIDKey: Int(formatID),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        if format == 1 {
            let depth = [16, 24, 32][safe: UserDefaults.standard.integer(forKey: kBitDepth)] ?? 16
            settings[AVLinearPCMBitDepthKey] = depth
            settings[AVLinearPCMIsFloatKey] = depth == 32
        }

        // Session is already active from requestPermissionAndStart — setActive is a fast no-op
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .default)
        try? session.setActive(true)
        if session.isInputGainSettable {
            try? session.setInputGain(Float(gain > 0 ? gain : 0.5))
        }
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else {
            isRecording = false
            return
        }
        rec.isMeteringEnabled = true
        rec.delegate = self
        rec.record()
        self.recorder = rec
        self.isRecording = true
        self.isPaused = false
        self.startTimer()
    }

    /// Called by the timer when the split interval is reached — saves the current segment and starts a new one.
    private func performAutoSplit() {
        guard isRecording, let url = outputURL, !currentItemId.isEmpty else { return }
        let duration = Double(elapsedSeconds)
        let itemId   = currentItemId

        // Finalize current file
        let oldRec = recorder
        recorder = nil
        oldRec?.stop()   // synchronous — ensures file is fully flushed before auto-trigger reads it

        // Save manifest entry for the finished segment
        let entry = LocalRecordingEntry(
            id: UUID().uuidString,
            itemId: itemId,
            relativePath: LocalRecordingStore.relativePath(of: url),
            createdAt: Date(),
            durationSeconds: duration
        )
        LocalRecordingStore.shared.add(entry)
        lastSavedItemId = itemId

        // Auto-trigger pipeline for this segment if enabled
        if let stored = LocalItemStore.shared.items.first(where: { $0.id == itemId }) {
            let autoItem = Item(id: stored.id, name: stored.name, collection: stored.collection,
                                collectionId: stored.collectionId, createdAt: stored.createdAt,
                                transcripts: nil, notes: nil)
            TranscriptionManager.shared.autoTriggerIfEnabled(entry: entry, item: autoItem)
        }

        // Reset counters and start a fresh segment
        elapsedSeconds = 0
        fileSize = 0
        audioLevel = 0.08
        start()
    }

    func togglePause() {
        guard let rec = recorder else { return }
        if isPaused { rec.record(); isPaused = false; startTimer() }
        else { rec.pause(); isPaused = true; timer?.invalidate() }
    }

    /// Stops and saves the recording — used by the mini bar stop button.
    func stopAndSave() {
        guard isRecording || isPaused else { return }
        saveMessage = "Saving audio..."
        let duration = Double(elapsedSeconds)
        let url = outputURL
        let itemId = currentItemId
        let name = currentItemName
        stop()  // resets all state including isMinimized
        guard let url, !itemId.isEmpty else { saveMessage = nil; return }
        let entry = LocalRecordingEntry(
            id: UUID().uuidString,
            itemId: itemId,
            relativePath: LocalRecordingStore.relativePath(of: url),
            createdAt: Date(),
            durationSeconds: duration
        )
        LocalRecordingStore.shared.add(entry)
        lastSavedItemId = itemId
        // Auto-trigger pipeline if enabled — look up full Item from local store
        if let stored = LocalItemStore.shared.items.first(where: { $0.id == itemId }) {
            let autoItem = Item(id: stored.id, name: stored.name, collection: stored.collection,
                                collectionId: stored.collectionId, createdAt: stored.createdAt,
                                transcripts: nil, notes: nil)
            TranscriptionManager.shared.autoTriggerIfEnabled(entry: entry, item: autoItem)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.saveMessage = "Saved to \(name)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.saveMessage = nil
            }
        }
    }

    /// Shows the save toast — called by RecordingView after stopAndTranscribe saves.
    func showSavedToast(itemName: String) {
        saveMessage = "Saving audio..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.saveMessage = "Saved to \(itemName)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.saveMessage = nil
            }
        }
    }

    func stop() {
        timer?.invalidate()
        let rec = recorder
        recorder = nil
        isRecording = false
        isPaused = false
        isMinimized = false
        // Keep screen on if transcription is still running after recording stops
        UIApplication.shared.isIdleTimerDisabled = TaskQueueManager.shared.isProcessing
        // Finalize the file synchronously so any subsequent read (e.g. autoTrigger) gets a complete file.
        // Session deactivation can be async — it does not affect file integrity.
        rec?.stop()
        Task.detached {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    func restart() {
        timer?.invalidate()
        let rec = recorder
        let oldURL = outputURL
        recorder = nil
        isRecording = false
        isPaused = false
        // Stop synchronously so the session is cleanly released before the new recording starts.
        // File deletion can be async — the URL is already captured and no one else will read it.
        rec?.stop()
        Task.detached {
            if let url = oldURL { try? FileManager.default.removeItem(at: url) }
        }
        elapsedSeconds = 0
        fileSize = 0
        smoothedLevel = 0.08
        audioLevel = 0.08
        start()
    }

    /// Stops recording and deletes the file — used by the discard/delete action.
    func stopAndDiscard() {
        timer?.invalidate()
        let rec = recorder
        let url = outputURL
        recorder = nil
        isRecording = false
        isPaused = false
        isMinimized = false
        // Keep screen on if transcription is still running after discard
        UIApplication.shared.isIdleTimerDisabled = TaskQueueManager.shared.isProcessing
        Task.detached {
            rec?.stop()
            if let url { try? FileManager.default.removeItem(at: url) }
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    var recordedFileURL: URL? { outputURL }

    private func startTimer() {
        fileSizeTick = 0
        smoothedLevel = 0.08
        // 4 Hz — half the old rate, same visual quality, meaningfully less CPU/battery
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedSeconds = Int(self.recorder?.currentTime ?? 0)
                // Auto-split when interval is reached
                let splitInterval = UserDefaults.standard.integer(forKey: kSplitInterval)
                if splitInterval > 0 && self.elapsedSeconds > 0 && self.elapsedSeconds >= splitInterval {
                    self.performAutoSplit()
                    return
                }
                self.recorder?.updateMeters()
                let level = self.recorder?.averagePower(forChannel: 0) ?? -60
                // Log curve: compresses quiet noise, preserves loud peaks naturally
                let raw = Float(max(0, min(1, (level + 60) / 60)))
                let curved = pow(raw, 2.0)
                // Peak-hold smoothing: rises instantly, decays slowly → no jitter
                let smoothed = max(curved, self.smoothedLevel * 0.72)
                self.smoothedLevel = smoothed
                self.audioLevel = smoothed
                // File size — only every ~1s (every 4 ticks at 0.25s)
                self.fileSizeTick += 1
                if self.fileSizeTick >= 4 {
                    self.fileSizeTick = 0
                    let url = self.outputURL
                    Task.detached {
                        guard let url else { return }
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                           let size = attrs[.size] as? Int64 {
                            await MainActor.run { [weak self] in self?.fileSize = size }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
