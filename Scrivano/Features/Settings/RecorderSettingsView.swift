import SwiftUI

struct RecorderSettingsView: View {
    @EnvironmentObject var langMgr: LanguageManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("pocket_mode") private var pocketMode = false
    @State private var showPocketExplanation = false
    @AppStorage("recorderQuality")  private var quality: Int = 1    // 0=Low 1=Med 2=High 3=Max
    @AppStorage("recorderFormat")   private var format: Int = 1     // 0=M4A 1=WAV
    @AppStorage("recorderBitDepth") private var bitDepth: Int = 0   // 0=16 1=24 2=32
    @AppStorage("splittingInterval")  private var splitInterval: Int = 300
    @AppStorage("auto_conversion")    private var autoConversion: Bool = true
    @AppStorage("compression_speed")  private var compressionSpeed: Int = 0   // 0=off 1=1.5x 2=2x
    @AppStorage("compression_mono")   private var compressionMono: Bool = false
    @AppStorage("compression_silence") private var compressionSilence: Bool = false

    private let qualityLabels = ["Low", "Medium", "High", "Max"]
    private var qualityDescriptions: [String] {[
        langMgr.t("recorder.quality.low"),
        langMgr.t("recorder.quality.medium"),
        langMgr.t("recorder.quality.high"),
        langMgr.t("recorder.quality.max")
    ]}

    private let formatLabels = ["M4A", "WAV"]
    private let depthLabels  = ["16 bit", "24 bit", "32 bit"]

    // Estimated file size based on format / quality / bit depth
    private var sizeHint: String {
        if format == 0 {
            return ["~8 MB/hr", "~16 MB/hr", "~22 MB/hr", "~30 MB/hr"][quality]
        }
        let sizes = [
            ["~55 MB/hr", "~83 MB/hr",  "~110 MB/hr"],
            ["~150 MB/hr","~230 MB/hr", "~305 MB/hr"],
            ["~305 MB/hr","~455 MB/hr", "~610 MB/hr"],
            ["~660 MB/hr","~990 MB/hr", "~1.3 GB/hr"]
        ]
        return sizes[quality][bitDepth]
    }

    private func formatLimit(mbPerHour: Double) -> String {
        let minutes = (4.5 / mbPerHour) * 60
        if minutes < 2 {
            let secs = max(5, Int((minutes * 60).rounded()))
            return "~\(secs) sec"
        }
        return "~\(Int(minutes.rounded())) min"
    }

    private var limitLabelM4A: String {
        formatLimit(mbPerHour: [8.0, 15.0, 22.0, 30.0][quality])
    }

    private var limitLabelWAV: String {
        let rates: [[Double]] = [
            [55,  83,  110],
            [150, 230, 305],
            [305, 455, 610],
            [660, 990, 1300]
        ]
        return formatLimit(mbPerHour: rates[quality][bitDepth])
    }

    private var splitOptions: [(label: String, sublabel: String, seconds: Int)] {[
        (langMgr.t("recorder.split.none"), "off",    0),
        ("5 min",                          "300s",   300),
        ("10 min",                         "600s",   600),
        ("15 min",                         "900s",   900),
        ("18 min",                         "1070s",  1070),
        ("30 min",                         "1800s",  1800),
        (langMgr.t("recorder.split.hour"), "3600s",  3600)
    ]}

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            VStack(spacing: 0) {

                SubScreenBar(title: langMgr.t("settings.recorderSettings.title"), onBack: { dismiss() })
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        settingsGroup {
                            ToggleRow(icon: "🎙️", iconColor: .stageMedia, title: langMgr.t("recorder.pocketMode"), isOn: $pocketMode)
                        }
                        .padding(.top, 14)

                        // ── Audio Quality ──────────────────────────────────
                        SectionLabel(text: langMgr.t("recorder.section.quality"))
                        settingsGroup {
                            VStack(spacing: 10) {
                                segmentedControl(options: qualityLabels, selected: $quality)
                                HStack {
                                    Text(qualityDescriptions[quality])
                                    Spacer()
                                    Text(sizeHint)
                                }
                                .font(.inter(11))
                                .foregroundColor(.textQuaternary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }

                        // ── Audio Format ───────────────────────────────────
                        SectionLabel(text: langMgr.t("recorder.section.format"))
                        settingsGroup {
                            VStack(spacing: 10) {
                                segmentedControl(options: formatLabels, selected: $format)
                                Text(format == 0
                                     ? langMgr.t("recorder.format.m4a")
                                     : langMgr.t("recorder.format.wav"))
                                    .font(.inter(11))
                                    .foregroundColor(.textQuaternary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }

                        // ── Bit Depth (WAV only) ───────────────────────────
                        SectionLabel(text: langMgr.t("recorder.section.bitDepth"))
                        settingsGroup {
                            VStack(spacing: 10) {
                                segmentedControl(options: depthLabels, selected: $bitDepth)
                                    .opacity(format == 0 ? 0.3 : 1)
                                    .allowsHitTesting(format != 0)
                                Text(format == 0
                                     ? langMgr.t("recorder.bitDepth.wavOnly")
                                     : "\(depthLabels[bitDepth]) · \(sizeHint)")
                                    .font(.inter(11))
                                    .foregroundColor(.textQuaternary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }

                        // ── Splitting Interval ─────────────────────────────
                        SectionLabel(text: langMgr.t("recorder.section.splitting"))
                        settingsGroup {
                            VStack(spacing: 12) {
                                // Top row: None + first 3 time options
                                HStack(spacing: 6) {
                                    ForEach(splitOptions.prefix(4), id: \.seconds) { opt in
                                        splitPill(opt)
                                    }
                                }
                                // Bottom row: remaining 3 options
                                HStack(spacing: 6) {
                                    ForEach(splitOptions.suffix(3), id: \.seconds) { opt in
                                        splitPill(opt)
                                    }
                                    // invisible spacer pill to keep alignment
                                    Color.clear.frame(maxWidth: .infinity).frame(height: 52)
                                }
                                HStack(spacing: 6) {
                                    Image(systemName: splitInterval > 0 ? "scissors" : "infinity")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(splitInterval > 0
                                         ? langMgr.t("recorder.split.autoSaves")
                                         : langMgr.t("recorder.split.noSplit"))
                                        .font(.inter(11))
                                }
                                .foregroundColor(.textQuaternary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                // Warning: always show the size-based split info
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(Color(hex: "#f59e0b"))
                                    Text(langMgr.t("recorder.split.sizeWarning").replacingOccurrences(of: "%@", with: format == 0 || autoConversion ? limitLabelM4A : limitLabelWAV))
                                        .font(.inter(11, weight: .medium))
                                        .foregroundColor(Color(hex: "#fbbf24"))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(12)
                                .background(Color(hex: "#f59e0b").opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#f59e0b").opacity(0.25), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                                // Lock notice
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.white.opacity(0.3))
                                    Text("Other intervals are locked. 5 min is required to avoid transcription truncation with the current AI provider.")
                                        .font(.inter(11))
                                        .foregroundColor(Color.white.opacity(0.3))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.03))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 14)
                        }

                        // ── Compression Options ────────────────────────────
                        SectionLabel(text: "Compression Options")
                        settingsGroup {
                            VStack(spacing: 0) {
                                // Speed
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("UPLOAD SPEED")
                                        .font(.inter(10, weight: .heavy))
                                        .foregroundColor(.textTertiary)
                                        .tracking(0.6)
                                    HStack(spacing: 6) {
                                        ForEach([(0, "Normal"), (1, "1.5×"), (2, "2×")], id: \.0) { val, label in
                                            let isOn = compressionSpeed == val
                                            Button { withAnimation(.easeInOut(duration: 0.15)) { compressionSpeed = val } } label: {
                                                Text(label)
                                                    .font(.inter(13, weight: .bold))
                                                    .foregroundColor(isOn ? .white : .textTertiary)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 9)
                                                    .background(isOn
                                                        ? LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .leading, endPoint: .trailing)
                                                        : LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
                                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(isOn ? Color.brandCyan.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    Text(compressionSpeed == 0
                                        ? "Audio sent at original speed."
                                        : compressionSpeed == 1
                                            ? "Audio sped up 1.5× before upload. Reduces cost ~33%. Test on your audio first."
                                            : "Audio sped up 2× before upload. Halves cost. Use with caution on accented or medical speech.")
                                        .font(.inter(11))
                                        .foregroundColor(.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 14)

                                Divider().background(Color.white.opacity(0.05))

                                // Mono
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Convert to Mono")
                                                .font(.inter(13, weight: .semibold)).foregroundColor(.textPrimary)
                                            Text("Reduces file size ~50%. No accuracy loss for speech.")
                                                .font(.inter(11)).foregroundColor(.textTertiary)
                                        }
                                        Spacer()
                                        Toggle("", isOn: $compressionMono).labelsHidden().tint(.brandBlue).scaleEffect(0.85)
                                    }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 13)

                                Divider().background(Color.white.opacity(0.05))

                                // Silence removal
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Strip Silence")
                                                .font(.inter(13, weight: .semibold)).foregroundColor(.textPrimary)
                                            Text("Removes silent gaps before upload. Reduces cost and eliminates hallucinations on silence.")
                                                .font(.inter(11)).foregroundColor(.textTertiary)
                                        }
                                        Spacer()
                                        Toggle("", isOn: $compressionSilence).labelsHidden().tint(.brandBlue).scaleEffect(0.85)
                                    }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 13)
                            }
                        }

                        Spacer().frame(height: 40)
                    }
                }
            }

            // Pocket Mode warning overlay
            if showPocketExplanation {
                Color.black.opacity(0.65).ignoresSafeArea().zIndex(10)
                VStack {
                    Spacer()
                    pocketModeCard
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(11)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showPocketExplanation)
        .navigationBarHidden(true)
        .onChange(of: pocketMode) { newValue in
            if newValue { showPocketExplanation = true }
        }
    }

    private var pocketModeCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(Color.white.opacity(0.75))

            Text(langMgr.t("dashboard.pocketMode"))
                .font(.inter(16, weight: .heavy))
                .foregroundColor(Color.white)

            VStack(alignment: .leading, spacing: 14) {
                pocketRow(icon: "hand.tap",      title: langMgr.t("recorder.firstTap"),
                          detail: langMgr.t("recorder.pocket.firstDetail"))
                pocketRow(icon: "hand.tap.fill",  title: langMgr.t("recorder.secondTap"),
                          detail: langMgr.t("recorder.pocket.secondDetail"))
                pocketRow(icon: "timer",          title: langMgr.t("recorder.inaction"),
                          detail: langMgr.t("recorder.pocket.inactionDetail"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showPocketExplanation = false }
            } label: {
                Text(langMgr.t("recorder.gotIt"))
                    .font(.inter(14, weight: .heavy))
                    .foregroundColor(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.30), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 13))
            }
        }
        .padding(24)
        .background(Color.black)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.35), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.6), radius: 24)
    }

    private func pocketRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.70))
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.inter(13, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.90))
                Text(detail)
                    .font(.inter(12))
                    .foregroundColor(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func splitPill(_ opt: (label: String, sublabel: String, seconds: Int)) -> some View {
        let isSelected = splitInterval == opt.seconds
        let isLocked = opt.seconds != 300  // only 5 min allowed while OpenAI truncation is unresolved
        return Button {
            guard !isLocked else { return }
            withAnimation(.easeInOut(duration: 0.15)) { splitInterval = opt.seconds }
        } label: {
            VStack(spacing: 2) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.2))
                }
                Text(opt.label)
                    .font(.inter(13, weight: .bold))
                    .foregroundColor(isLocked ? Color.white.opacity(0.2) : (isSelected ? .white : .textTertiary))
                Text(opt.sublabel)
                    .font(.inter(9, weight: .medium))
                    .foregroundColor(Color.white.opacity(isLocked ? 0.1 : (isSelected ? 0.6 : 0.2)))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isLocked
                ? LinearGradient(colors: [Color.white.opacity(0.02), Color.white.opacity(0.02)], startPoint: .leading, endPoint: .trailing)
                : (isSelected
                    ? LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(isLocked ? Color.white.opacity(0.03) : (isSelected ? Color.brandCyan.opacity(0.5) : Color.white.opacity(0.06)), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .shadow(color: isSelected && !isLocked ? Color.brandBlue.opacity(0.4) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isLocked)
    }

    private func segmentedControl(options: [String], selected: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selected.wrappedValue = i }
                } label: {
                    Text(opt)
                        .font(.inter(12, weight: .bold))
                        .foregroundColor(selected.wrappedValue == i ? .white : .textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected.wrappedValue == i
                            ? LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.05)], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 14)
    }
}

struct PlayerSettingsView: View {
    @EnvironmentObject var langMgr: LanguageManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("forward_seconds")  private var forwardSec = 30.0
    @AppStorage("rewind_seconds")   private var rewindSec = 10.0
    @AppStorage("repeat_audio")     private var repeatAudio = false

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: langMgr.t("recorder.playerSettings"), accentColor: .stageText, onBack: { dismiss() })

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        SectionLabel(text: langMgr.t("recorder.section.rewindFwd"))

                        VStack(spacing: 0) {
                            sliderRow(title: langMgr.t("recorder.forward"), value: $forwardSec, range: 5...60, unit: langMgr.t("recorder.sec"))
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 16)
                            sliderRow(title: langMgr.t("recorder.rewind"), value: $rewindSec, range: 5...60, unit: langMgr.t("recorder.sec"))
                        }
                        .background(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 14)

                        SectionLabel(text: langMgr.t("recorder.section.repeatAudio"))
                        VStack(spacing: 0) {
                            ToggleRow(icon: "repeat", iconColor: .brandBlue, title: langMgr.t("recorder.repeat"), isOn: $repeatAudio)
                        }
                        .background(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 14)

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.inter(13, weight: .semibold)).foregroundColor(.textSecondary)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.inter(13, weight: .bold)).foregroundColor(.textPrimary)
            }
            Slider(value: value, in: range, step: 5).accentColor(.brandBlue)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}
