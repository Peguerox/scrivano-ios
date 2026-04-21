import SwiftUI

struct AutomationView: View {
    @EnvironmentObject var langMgr: LanguageManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("auto_transcription")   private var autoTranscription = true
    @AppStorage("auto_conversion")      private var autoConversion = true
    @AppStorage("splittingInterval")    private var splittingInterval: Int = 1080

    @ObservedObject private var transcriptionMgr = TranscriptionManager.shared
    @ObservedObject private var notesMgr         = NoteGenerationManager.shared
    @ObservedObject private var taskQueue        = TaskQueueManager.shared

    private var splittingEnabled: Bool { splittingInterval > 0 }

    // Returns live processing/queued state for each pipeline stage node
    private func stageStatus(for stage: String) -> (isProcessing: Bool, isQueued: Bool) {
        switch stage {
        case "Text":
            let processing = transcriptionMgr.transcribingRecordingId != nil
            let queued     = !transcriptionMgr.queuedRecordingIds.isEmpty
            return (processing, queued && !processing)
        case "Notes":
            let processing = notesMgr.processingItemId != nil
            let queued     = !notesMgr.queuedItemIds.isEmpty
            return (processing, queued && !processing)
        default:
            return (false, false)
        }
    }

    @ViewBuilder
    private func pipelineStageNode(stage: String, color: Color, displayLabel: String? = nil) -> some View {
        let status = stageStatus(for: stage)
        VStack(spacing: 3) {
            Text(displayLabel ?? stage)
                .font(.inter(9, weight: .heavy))
                .tracking(0.3)
                .foregroundColor(color.opacity(0.85))
                .textCase(.uppercase)
            ZStack(alignment: .topTrailing) {
                if status.isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(color)
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 14, height: 14)
                        .shadow(color: color.opacity(status.isQueued ? 0.3 : 0.7), radius: 4)
                        .opacity(status.isQueued ? 0.45 : 1.0)
                }
                if status.isQueued {
                    Image(systemName: "hourglass")
                        .font(.system(size: 7, weight: .black))
                        .foregroundColor(.white)
                        .padding(2)
                        .background(color)
                        .clipShape(Circle())
                        .offset(x: 6, y: -6)
                }
            }
            .frame(width: 20, height: 20)
        }
        .frame(width: 50, height: 50)
        .background(LinearGradient(
            colors: [color.opacity(status.isProcessing ? 0.35 : 0.2), color.opacity(0.08)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
            color.opacity(status.isProcessing ? 0.6 : 0.3), lineWidth: status.isProcessing ? 1.5 : 1
        ))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var pipelineActiveConnector: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(maxWidth: .infinity, maxHeight: 2)
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    let cycle = 1.4
                    let dotR: CGFloat = 2.5
                    for i in 0..<3 {
                        let p = (t + Double(i) * cycle / 3).truncatingRemainder(dividingBy: cycle) / cycle
                        let opacity = p < 0.15 ? p / 0.15 : (p > 0.85 ? (1 - p) / 0.15 : 1.0)
                        let cx = p * (size.width - dotR * 2) + dotR
                        let cy = size.height / 2
                        ctx.fill(Path(ellipseIn: CGRect(x: cx - 7, y: cy - 7, width: 14, height: 14)),
                                 with: .color(Color.brandCyan.opacity(opacity * 0.12)))
                        ctx.fill(Path(ellipseIn: CGRect(x: cx - 4, y: cy - 4, width: 8, height: 8)),
                                 with: .color(Color.brandCyan.opacity(opacity * 0.28)))
                        ctx.fill(Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)),
                                 with: .color(Color.brandCyan.opacity(opacity * 0.95)))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 6)
        .clipped()
    }

    private var splitLabel: String {
        switch splittingInterval {
        case 300:  return "5 min"
        case 600:  return "10 min"
        case 900:  return "15 min"
        case 1070: return "18 min"
        case 1080: return "18 min"
        case 1800: return "30 min"
        case 3600: return "1 hour"
        default:   return "\(splittingInterval / 60) min"
        }
    }
    @AppStorage("auto_note")                    private var autoNote = false
    @AppStorage("auto_merge")                   private var autoMerge = true
    @AppStorage("auto_upload")                  private var autoUpload = false
    @AppStorage("auto_note_prompts_encoded")    private var autoNotePromptsEncoded: String = ""

    @State private var expandedStage: Int? = nil
    @State private var showPromptPicker = false

    private var savedPromptCount: Int {
        autoNotePromptsEncoded.isEmpty ? 0 : autoNotePromptsEncoded.split(separator: ",").count
    }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(title: langMgr.t("settings.automation.title"), accentColor: .brandCyan, onBack: { dismiss() })

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {

                        // Pipeline preview
                        VStack(spacing: 12) {
                            Text(langMgr.t("automation.diagramLabel"))
                                .font(.inter(10, weight: .heavy))
                                .tracking(0.7)
                                .foregroundColor(.textTertiary)
                                .textCase(.uppercase)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 0) {
                                ForEach([
                                    ("Media", Color.stageMedia, 0, langMgr.t("automation.stage.media")),
                                    ("Text", Color.stageText, 1, langMgr.t("automation.stage.text")),
                                    ("Notes", Color.stageNotes, 2, langMgr.t("automation.stage.notes")),
                                    ("Web", Color.stageWeb, -1, langMgr.t("automation.stage.web"))
                                ], id: \.0) { stage, color, cardIndex, stageLabel in
                                    HStack(spacing: 0) {
                                        if cardIndex >= 0 {
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedStage = expandedStage == cardIndex ? nil : cardIndex
                                                }
                                            } label: {
                                                pipelineStageNode(stage: stage, color: color, displayLabel: stageLabel)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 10)
                                                            .stroke(expandedStage == cardIndex ? color.opacity(0.7) : Color.clear, lineWidth: 1.5)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            pipelineStageNode(stage: stage, color: color, displayLabel: stageLabel)
                                        }

                                        if stage != "Web" {
                                            let isActive = (stage == "Media" && autoTranscription)
                                                        || (stage == "Text" && autoNote)
                                                        || (stage == "Notes" && autoUpload)
                                            if isActive {
                                                pipelineActiveConnector
                                            } else {
                                                Canvas { ctx, size in
                                                    var path = Path()
                                                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                                                    path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                                                    ctx.stroke(path, with: .color(.white.opacity(0.18)),
                                                               style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                                                }
                                                .frame(maxWidth: .infinity, maxHeight: 6)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(LinearGradient(colors: [Color.brandBlue.opacity(0.08), Color.brandNavy.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.brandBlue.opacity(0.18), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                        // Stage 1: Media → Text
                        automationCard(
                            index: 0,
                            dotColor: .stageMedia,
                            title: langMgr.t("automation.mediaToText.title"),
                            subtitle: langMgr.t("automation.mediaToText.subtitle")
                        ) {
                            miniToggle(langMgr.t("automation.autoTranscription"),
                                       desc: langMgr.t("automation.autoTranscription.desc"),
                                       isOn: $autoTranscription,
                                       enabled: autoConversion && splittingEnabled)
                            miniToggle(langMgr.t("automation.autoConversion"),
                                       desc: langMgr.t("automation.autoConversion.desc"),
                                       isOn: $autoConversion)
                            miniToggle(langMgr.t("automation.autoSplitting"),
                                       desc: splittingEnabled
                                            ? langMgr.t("automation.autoSplitting.active.desc").replacingOccurrences(of: "%@", with: splitLabel)
                                            : langMgr.t("automation.autoSplitting.inactive.desc"),
                                       isOn: Binding(
                                            get: { splittingEnabled },
                                            set: { _ in }
                                       ),
                                       enabled: false)
                            defaultButton {
                                autoTranscription = true
                                autoConversion = true
                            }
                        }
                        .onChange(of: autoConversion)     { newVal in if !newVal { autoTranscription = false } }
                        .onChange(of: splittingInterval)  { newVal in if newVal == 0 { autoTranscription = false } }

                        // Stage 2: Text → Notes
                        automationCard(
                            index: 1,
                            dotColor: .stageText,
                            title: langMgr.t("automation.textToNotes.title"),
                            subtitle: langMgr.t("automation.textToNotes.subtitle")
                        ) {
                            addPromptsButton()
                            miniToggle(langMgr.t("automation.autoNote"),
                                       desc: savedPromptCount == 0
                                           ? langMgr.t("automation.autoNote.noPrompt.desc")
                                           : langMgr.t("automation.autoNote.desc"),
                                       isOn: $autoNote,
                                       enabled: savedPromptCount > 0)
                            miniToggle(langMgr.t("automation.autoMerge"),
                                       desc: langMgr.t("automation.autoMerge.desc"),
                                       isOn: .constant(true),
                                       enabled: false)
                            defaultButton {
                                autoNote = false
                                autoMerge = true
                                autoNotePromptsEncoded = ""
                            }
                        }
                        .onChange(of: autoNotePromptsEncoded) { newVal in
                            if newVal.isEmpty { autoNote = false }
                            else { autoNote = true }
                        }

                        // Stage 3: Notes → Web
                        automationCard(
                            index: 2,
                            dotColor: .stageNotes,
                            title: langMgr.t("automation.notesToWeb.title"),
                            subtitle: langMgr.t("automation.notesToWeb.subtitle")
                        ) {
                            miniToggle(langMgr.t("automation.autoUpload"),
                                       desc: langMgr.t("automation.autoUpload.desc"),
                                       isOn: $autoUpload)
                            defaultButton {
                                autoUpload = false
                            }
                        }

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showPromptPicker) {
            PromptsView(context: .selectForAutomation)
        }
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
                .contentShape(Rectangle())
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

    private func miniToggle(_ title: String, desc: String, isOn: Binding<Bool>, enabled: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.inter(13, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(desc)
                    .font(.inter(11))
                    .foregroundColor(.textQuaternary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.brandBlue)
                .scaleEffect(0.85)
                .padding(.top, 2)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.35)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().background(Color.white.opacity(0.05)) }
    }

    @ViewBuilder
    private func addPromptsButton() -> some View {
        Button { showPromptPicker = true } label: {
            HStack(spacing: 8) {
                Image(systemName: savedPromptCount > 0 ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                if savedPromptCount > 0 {
                    Text("\(savedPromptCount) \(langMgr.t("prompts.title"))")
                        .font(.inter(13, weight: .bold))
                    Spacer()
                    Text(langMgr.t("common.change"))
                        .font(.inter(12, weight: .semibold))
                        .foregroundColor(.brandCyan.opacity(0.7))
                } else {
                    Text(langMgr.t("common.add_prompts"))
                        .font(.inter(13, weight: .bold))
                }
            }
            .foregroundColor(.brandCyan)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(LinearGradient(colors: [Color.brandBlue.opacity(0.35), Color.brandCyan.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandCyan.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func defaultButton(action: @escaping () -> Void) -> some View {
        Button("Default", action: action)
            .font(.inter(13, weight: .bold))
            .foregroundColor(.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
