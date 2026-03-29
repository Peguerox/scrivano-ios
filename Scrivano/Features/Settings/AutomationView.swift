import SwiftUI

struct AutomationView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("auto_transcription")   private var autoTranscription = true
    @AppStorage("auto_conversion")      private var autoConversion = true
    @AppStorage("auto_splitting")       private var autoSplitting = false
    @AppStorage("auto_note")            private var autoNote = false
    @AppStorage("auto_merge")           private var autoMerge = true
    @AppStorage("auto_upload")          private var autoUpload = false

    @State private var expandedStage: Int? = 0

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: "Automation", accentColor: .brandCyan, onBack: { dismiss() })

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {

                        // Pipeline preview
                        VStack(spacing: 10) {
                            Text("PIPELINE PREVIEW")
                                .font(.inter(9, weight: .heavy))
                                .tracking(1.5)
                                .foregroundColor(.textQuaternary)
                                .textCase(.uppercase)

                            HStack(spacing: 0) {
                                ForEach([
                                    ("Media", Color.stageMedia),
                                    ("Text", Color.stageText),
                                    ("Notes", Color.stageNotes),
                                    ("Web", Color.stageWeb)
                                ], id: \.0) { stage, color in
                                    HStack(spacing: 0) {
                                        VStack(spacing: 4) {
                                            Circle().fill(color).frame(width: 10, height: 10)
                                                .shadow(color: color.opacity(0.5), radius: 6)
                                            Text(stage).font(.inter(10, weight: .bold)).foregroundColor(color)
                                        }
                                        if stage != "Web" {
                                            Rectangle()
                                                .fill(Color.white.opacity(0.1))
                                                .frame(height: 1)
                                                .frame(maxWidth: .infinity)
                                                .padding(.horizontal, 4)
                                                .padding(.bottom, 16)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                        // Stage 1: Media → Text
                        automationCard(
                            index: 0,
                            dotColor: .stageMedia,
                            title: "Media → Text",
                            subtitle: "Auto-transcribe new recordings"
                        ) {
                            miniToggle("Automatic Transcription", isOn: $autoTranscription)
                            miniToggle("Automatic Conversion", isOn: $autoConversion)
                            miniToggle("Automatic Splitting", isOn: $autoSplitting)
                            defaultButton()
                        }

                        // Stage 2: Text → Notes
                        automationCard(
                            index: 1,
                            dotColor: .stageText,
                            title: "Text → Notes",
                            subtitle: "Auto-generate notes from transcripts"
                        ) {
                            miniToggle("Automatic Note", isOn: $autoNote)
                            Button {
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Prompts")
                                }
                                .font(.inter(12, weight: .bold))
                                .foregroundColor(.brandCyan)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.brandBlue.opacity(0.15))
                                .clipShape(Capsule())
                            }
                            .padding(.horizontal, 14).padding(.vertical, 4)
                            miniToggle("Automatic Merge", isOn: $autoMerge)
                            defaultButton()
                        }

                        // Stage 3: Notes → Web
                        automationCard(
                            index: 2,
                            dotColor: .stageNotes,
                            title: "Notes → Web",
                            subtitle: "Auto-publish notes to web"
                        ) {
                            miniToggle("Automatic Upload", isOn: $autoUpload)
                            defaultButton()
                        }

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func automationCard<Content: View>(
        index: Int,
        dotColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder expanded: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedStage = expandedStage == index ? nil : index
                }
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(dotColor).frame(width: 10, height: 10)
                        .shadow(color: dotColor.opacity(0.5), radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.inter(14, weight: .bold)).foregroundColor(.textPrimary)
                        Text(subtitle).font(.inter(11)).foregroundColor(.textTertiary)
                    }
                    Spacer()
                    Image(systemName: expandedStage == index ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textQuaternary)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if expandedStage == index {
                Divider().background(Color.white.opacity(0.07))
                VStack(spacing: 0) {
                    expanded()
                }
            }
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 14)
    }

    private func miniToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.inter(13, weight: .medium)).foregroundColor(.textSecondary)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(.brandBlue).scaleEffect(0.85)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func defaultButton() -> some View {
        HStack {
            Spacer()
            Button("Default") {}
                .font(.inter(11, weight: .bold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14).padding(.bottom, 10)
    }
}
