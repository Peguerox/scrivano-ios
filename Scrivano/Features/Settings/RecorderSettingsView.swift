import SwiftUI

struct RecorderSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("pocket_mode")       private var pocketMode = false
    @AppStorage("audio_quality")     private var quality = 1
    @AppStorage("audio_format")      private var format = 1
    @AppStorage("bit_depth")         private var bitDepth = 0
    @AppStorage("auto_start")        private var autoStart = true
    @AppStorage("auto_gain")         private var autoGain = false

    let qualities = ["Low", "Medium", "High", "Max"]
    let qualityHints = ["Smallest Size", "Best for voice", "CD Quality", "High Definition"]
    let formats = ["aiff", "wav", "caf", "m4a"]
    let formatHints = ["150 MB/hr", "150 MB/hr", "94 MB/hr", "16 MB/hr"]
    let depths = ["16 bit", "24 bit", "32 bit"]

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: "Recorder Settings", accentColor: .stageMedia, onBack: { dismiss() })

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        settingsGroup {
                            ToggleRow(icon: "🎙️", iconColor: .stageMedia, title: "Pocket Mode", isOn: $pocketMode)
                        }
                        .padding(.top, 14)

                        SectionLabel(text: "Audio Quality")
                        settingsGroup {
                            VStack(spacing: 10) {
                                segmentedControl(options: qualities, selected: $quality)
                                Text(qualityHints[quality] + " · " + qualities[quality])
                                    .font(.inter(11))
                                    .foregroundColor(.textQuaternary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }

                        SectionLabel(text: "Audio Format")
                        settingsGroup {
                            VStack(spacing: 10) {
                                segmentedControl(options: formats, selected: $format)
                                Text(formatHints[format])
                                    .font(.inter(11))
                                    .foregroundColor(.textQuaternary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }

                        SectionLabel(text: "Bit Depth")
                        settingsGroup {
                            segmentedControl(options: depths, selected: $bitDepth)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                        }

                        settingsGroup {
                            ToggleRow(icon: "▶️", iconColor: .brandBlue, title: "Auto Start Recording", isOn: $autoStart)
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 68)
                            ToggleRow(icon: "🎚️", iconColor: .brandCyan, title: "Auto Input Gain", subtitle: "Input gain set automatically", isOn: $autoGain)
                        }
                        .padding(.top, 8)

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
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
    @Environment(\.dismiss) var dismiss
    @AppStorage("forward_seconds")  private var forwardSec = 30.0
    @AppStorage("rewind_seconds")   private var rewindSec = 10.0
    @AppStorage("repeat_audio")     private var repeatAudio = false

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: "Player Settings", accentColor: .stageText, onBack: { dismiss() })

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        SectionLabel(text: "Rewind / Forward Time")

                        VStack(spacing: 0) {
                            sliderRow(title: "Forward", value: $forwardSec, range: 5...60, unit: "sec")
                            Divider().background(Color.white.opacity(0.05)).padding(.leading, 16)
                            sliderRow(title: "Rewind", value: $rewindSec, range: 5...60, unit: "sec")
                        }
                        .background(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 14)

                        SectionLabel(text: "Repeat Audio")
                        VStack(spacing: 0) {
                            ToggleRow(icon: "repeat", iconColor: .brandBlue, title: "Repeat", isOn: $repeatAudio)
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
