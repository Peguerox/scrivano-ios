import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ItemCardView: View {
    let item: Item
    var isSelected: Bool
    var isCompact: Bool = false
    var localAudioCount: Int = 0
    var localTextCount: Int? = nil
    var localNoteCount: Int? = nil
    @ObservedObject var vm: DashboardViewModel
    var onTap: () -> Void
    var onStageTap: (DashboardViewModel.Stage) -> Void

    var onImportAudioTapped: () -> Void = {}
    var onImportImageTapped: () -> Void = {}
    var onImportDocTapped: () -> Void = {}
    var isInProcessMode: Bool = false
    var isProcessSelected: Bool = false
    var onRenameRequested: () -> Void = {}
    var onClearAllRequested: () -> Void = {}

    @ObservedObject private var transcriptionMgr: TranscriptionManager = TranscriptionManager.shared
    @ObservedObject private var notesMgr: NoteGenerationManager = NoteGenerationManager.shared
    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var showIntegrationMeta = false

    private var mediaCount: Int { localAudioCount }
    private var textCount: Int { localTextCount ?? item.textCount }
    private var noteCount: Int { localNoteCount ?? item.noteCount }

    private var isTranscribingThisItem: Bool {
        transcriptionMgr.transcribingItemName == item.name
    }

    private var isGeneratingNotesThisItem: Bool {
        notesMgr.processingItemId == item.id
    }

    var body: some View {
        Group {
            if isCompact { compactLayout } else { cardLayout }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .sheet(isPresented: $showIntegrationMeta) {
            if let meta = IntegrationStore.shared.integrationMetadata(for: item.id) {
                IntegrationMetaSheet(meta: meta)
            }
        }
    }

    // MARK: - Shared style helpers
    private var cardBg: LinearGradient {
        isSelected
            ? LinearGradient(colors: [Color.brandNavy.opacity(0.18), Color.black.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.035)], startPoint: .top, endPoint: .bottom)
    }
    private var strokeColor: Color { isSelected ? Color.brandCyan.opacity(0.35) : Color.white.opacity(0.09) }
    private var strokeWidth: CGFloat { isSelected ? 2 : 1 }

    private func stageBg(isFilled: Bool, color: Color) -> LinearGradient {
        isFilled
            ? LinearGradient(colors: [color.opacity(0.25), color.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color.white.opacity(0.03), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
    }
    private func stageStroke(isFilled: Bool, color: Color) -> some ShapeStyle {
        isFilled ? AnyShapeStyle(color.opacity(0.40)) : AnyShapeStyle(Color.white.opacity(0.1))
    }

    // MARK: - Card layout (default)
    private var cardLayout: some View {
        VStack(spacing: 10) {
            // Header row
            HStack(alignment: .center) {
                Text(item.name)
                    .font(.inter(15, weight: .bold))
                    .foregroundColor(isSelected ? .brandCyan : .textPrimary)
                    .lineLimit(1)
                Text("·")
                    .foregroundColor(.textQuaternary)
                Text(relativeTime(from: item.createdAt))
                    .font(.inter(10))
                    .foregroundColor(.textQuaternary)
                Spacer()
                if !isInProcessMode {
                    Menu {
                        Button { onImportAudioTapped() } label: {
                            Label(langMgr.t("dashboard.importAudio"), systemImage: "waveform")
                        }
                        Button { onImportImageTapped() } label: {
                            Label(langMgr.t("dashboard.importImage"), systemImage: "photo.badge.plus")
                        }
                        Button { onImportDocTapped() } label: {
                            Label(langMgr.t("dashboard.importDocument"), systemImage: "doc.badge.plus")
                        }
                        Button { onRenameRequested() } label: { Label(langMgr.t("dashboard.renameItem"), systemImage: "pencil") }
                        Divider()
                        Button(role: .destructive) { onClearAllRequested() } label: {
                            Label(langMgr.t("dashboard.clearContent"), systemImage: "trash.fill")
                        }
                        Button(role: .destructive) {
                            DeleteConfirmPresenter.show(itemName: item.name) { vm.deleteItem(item) }
                        } label: {
                            Label(langMgr.t("dashboard.deleteItemMenu"), systemImage: "trash")
                        }
                        if IntegrationStore.shared.integrationMetadata(for: item.id) != nil {
                            Divider()
                            Button { showIntegrationMeta = true } label: {
                                Label("Integration Source", systemImage: "link.badge.plus")
                            }
                        }
                    } label: {
                        Text("···")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 32)
                    }
                }
            }

            // Pipeline
            HStack(spacing: 5) {
                stageButton(.media, label: langMgr.t("automation.stage.media"), count: mediaCount)
                connector(filled: mediaCount > 0 && textCount > 0, isTranscribing: isTranscribingThisItem)
                stageButton(.text, label: langMgr.t("automation.stage.text"), count: textCount)
                connector(filled: textCount > 0 && noteCount > 0, isTranscribing: isGeneratingNotesThisItem)
                stageButton(.notes, label: langMgr.t("automation.stage.notes"), count: noteCount)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(cardBg)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(strokeColor, lineWidth: strokeWidth))
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(LinearGradient(colors: [.brandCyan, .brandBlue], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: isSelected ? Color.brandBlue.opacity(0.18) : .clear, radius: 8, y: 4)
        .overlay(alignment: .topTrailing) {
            if isInProcessMode {
                Image(systemName: isProcessSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isProcessSelected ? .brandCyan : Color.white.opacity(0.3))
                    .padding(10)
            }
        }
    }

    // MARK: - Compact list layout
    private var compactLayout: some View {
        HStack(spacing: 8) {
            Text(item.name)
                .font(.inter(15, weight: .bold))
                .foregroundColor(isSelected ? .brandCyan : .textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Mini pipeline
            HStack(spacing: 6) {
                miniStage(.media, count: mediaCount)
                miniConnector(filled: mediaCount > 0 && textCount > 0, isTranscribing: isTranscribingThisItem)
                miniStage(.text, count: textCount)
                miniConnector(filled: textCount > 0 && noteCount > 0, isTranscribing: isGeneratingNotesThisItem)
                miniStage(.notes, count: noteCount)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(cardBg)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(strokeColor, lineWidth: strokeWidth))
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(LinearGradient(colors: [.brandCyan, .brandBlue], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: isSelected ? Color.brandBlue.opacity(0.3) : .clear, radius: 8, y: 4)
    }

    private func miniStage(_ stage: DashboardViewModel.Stage, count: Int) -> some View {
        let isFilled = count > 0
        let color = stageColor(stage)
        return Button { onStageTap(stage) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(stageBg(isFilled: isFilled, color: color))
                    .frame(width: 34, height: 34)
                RoundedRectangle(cornerRadius: 7)
                    .stroke(stageStroke(isFilled: isFilled, color: color),
                            style: StrokeStyle(lineWidth: 1.5, dash: isFilled ? [] : [3, 3]))
                    .frame(width: 34, height: 34)
                Text(isFilled ? "\(count)" : "—")
                    .font(.inter(14, weight: .heavy))
                    .foregroundColor(isFilled ? color : Color.white.opacity(0.18))
                    .shadow(color: isFilled ? color.opacity(0.7) : .clear, radius: 5, x: 0, y: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func miniConnector(filled: Bool, isTranscribing: Bool = false) -> some View {
        ZStack {
            if !filled && !isTranscribing {
                Canvas { ctx, size in
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    ctx.stroke(path, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                }
            } else if filled && !isTranscribing {
                Capsule()
                    .fill(Color.brandCyan.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: 1.5)
                    .shadow(color: Color.brandCyan.opacity(0.7), radius: 3)
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(maxWidth: .infinity, maxHeight: 1.5)
            }
            if isTranscribing {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        let cycle = 1.4
                        let dotR: CGFloat = 1.0
                        for i in 0..<3 {
                            let p = (t + Double(i) * cycle / 3).truncatingRemainder(dividingBy: cycle) / cycle
                            let opacity = p < 0.2 ? p / 0.2 : (p > 0.8 ? (1 - p) / 0.2 : 1.0)
                            let cx = p * (size.width - dotR * 2) + dotR
                            let cy = size.height / 2
                            ctx.fill(Path(ellipseIn: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4)),
                                     with: .color(Color.brandCyan.opacity(opacity * 0.2)))
                            ctx.fill(Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)),
                                     with: .color(Color.brandCyan.opacity(opacity * 0.9)))
                        }
                    }
                }
            }
        }
        .frame(width: 14, height: 4)
        .clipped()
    }

    // MARK: - Stage button
    @ViewBuilder
    private func stageButton(_ stage: DashboardViewModel.Stage, label: String, count: Int) -> some View {
        let isFilled = count > 0
        let color = stageColor(stage)

        Button {
            onStageTap(stage)
        } label: {
            VStack(spacing: 3) {
                Text(label)
                    .font(.inter(9, weight: .heavy))
                    .tracking(0.3)
                    .foregroundColor(isFilled ? color : Color.white.opacity(0.22))
                    .shadow(color: isFilled ? color.opacity(0.6) : .clear, radius: 4, x: 0, y: 0)
                    .textCase(.uppercase)
                Text(isFilled ? "\(count)" : "—")
                    .font(.inter(17, weight: .heavy))
                    .foregroundColor(isFilled ? color : Color.white.opacity(0.18))
                    .shadow(color: isFilled ? color.opacity(0.7) : .clear, radius: 5, x: 0, y: 0)
            }
            .frame(width: 54, height: 54)
            .background(stageBg(isFilled: isFilled, color: color))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(stageStroke(isFilled: isFilled, color: color),
                            style: StrokeStyle(lineWidth: 1.5, dash: isFilled ? [] : [4, 3]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func connector(filled: Bool, isTranscribing: Bool = false) -> some View {
        ZStack {
            if !filled && !isTranscribing {
                Canvas { ctx, size in
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    ctx.stroke(path, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                }
            } else if filled && !isTranscribing {
                Capsule()
                    .fill(Color.brandCyan.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: 2)
                    .shadow(color: Color.brandCyan.opacity(0.65), radius: 5)
                    .shadow(color: Color.brandCyan.opacity(0.35), radius: 10)
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(maxWidth: .infinity, maxHeight: 2)
            }
            if isTranscribing {
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
        }
        .frame(minWidth: 8, maxWidth: .infinity)
        .frame(height: 6)
        .clipped()
    }

    private func stageColor(_ stage: DashboardViewModel.Stage) -> Color {
        switch stage {
        case .media:  return .stageMedia
        case .text:   return .stageText
        case .notes:  return .stageNotes
        }
    }

    private func relativeTime(from dateString: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString) else { return "" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff/60))m ago" }
        if diff < 86400 { return "\(Int(diff/3600))h ago" }
        let cal = Calendar.current
        let comps = cal.dateComponents([.day], from: date, to: Date())
        if let d = comps.day, d < 7 { return "\(d)d ago" }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }
}

// MARK: - Delete confirmation presenter
// Uses UIKit overFullScreen + crossDissolve so the backdrop fades in and the
// card scales up from center — consistent with every other popup in the app.
enum DeleteConfirmPresenter {
    static func show(itemName: String?, onCancel: (() -> Void)? = nil, onDelete: @escaping () -> Void) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }
        let host = UIHostingController(rootView: DeleteConfirmCover(itemName: itemName, onCancel: onCancel, onDelete: onDelete))
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.view.backgroundColor = .clear
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(host, animated: true)
    }
}

// MARK: - Swipe To Delete

struct SwipeToDelete<Content: View>: View {
    let onDelete: () -> Void
    var isCompact: Bool = false
    var itemName: String? = nil
    let content: () -> Content

    @State private var offset: CGFloat = 0

    private var revealWidth: CGFloat { isCompact ? 54 : 100 }
    private var cornerRadius: CGFloat { isCompact ? 10 : 18 }

    var body: some View {
        ZStack(alignment: .trailing) {
            content()
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onChanged { value in
                            let h = abs(value.translation.width)
                            let v = abs(value.translation.height)
                            guard h > v * 1.5, value.translation.width < 0 else { return }
                            offset = max(value.translation.width, -(revealWidth + 12))
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                offset = value.translation.width < -(revealWidth / 2) ? -revealWidth : 0
                            }
                        }
                )

            if offset < -12 {
                Button {
                    DeleteConfirmPresenter.show(
                        itemName: itemName,
                        onCancel: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { offset = 0 }
                        },
                        onDelete: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { offset = 0 }
                            onDelete()
                        }
                    )
                } label: {
                    if isCompact {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 5) {
                            Image(systemName: "trash")
                                .font(.system(size: 18, weight: .bold))
                            Text("Delete")
                                .font(.inter(11, weight: .heavy))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: revealWidth - 8)
                .background(Color(hex: "#ef4444"))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Reusable full-screen delete confirmation
struct DeleteConfirmCover: View {
    @Environment(\.dismiss) var dismiss
    var itemName: String? = nil
    var onCancel: (() -> Void)? = nil
    let onDelete: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
                .onTapGesture { cancel() }
            VStack(spacing: 16) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.danger)
                    .shadow(color: Color.danger.opacity(0.5), radius: 10)
                if let name = itemName {
                    Text("Delete \u{201C}\(name)\u{201D}?")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Delete this item?")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                }
                Text("This action cannot be undone.")
                    .font(.inter(13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button { cancel() } label: {
                        Text("Cancel")
                            .font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Color.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button {
                        dismiss()
                        onDelete()
                    } label: {
                        Text("Delete")
                            .font(.inter(14, weight: .heavy)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Color.danger.opacity(0.80))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(24)
            .background(Color(hex: "#081221"))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.danger.opacity(0.35), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: Color.danger.opacity(0.15), radius: 20)
            .padding(.horizontal, 24)
            .scaleEffect(appeared ? 1.0 : 0.88)
            .opacity(appeared ? 1.0 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appeared)
        }
        .onAppear { appeared = true }
    }

    private func cancel() {
        dismiss()
        onCancel?()
    }
}

// MARK: - Collection Top Panel (slides down from top)
struct CollectionTopPanel: View {
    @ObservedObject var vm: DashboardViewModel
    var onDismiss: () -> Void
    var onMinOneError: () -> Void
    var onActiveError: () -> Void
    var onDuplicateError: () -> Void
    var onRequestNewCollection: (String) -> Void
    @State private var selected = Set<String>()
    @State private var showDeleteConfirm = false
    @State private var scrollToId: String? = nil
    @AppStorage("showMyCollection") private var showMyCollection: Bool = true
    @AppStorage("collectionSortOrder") private var sortOrder: String = "date"

    // Stable key for the "My Collection" default row
    private let defaultKey = "__my_collection"

    // All rows: default first (always), then real collections sorted by preference
    private var allRows: [(id: String, name: String, isDefault: Bool)] {
        let defaults: [(id: String, name: String, isDefault: Bool)] = showMyCollection
            ? [(id: defaultKey, name: "My Collection", isDefault: true)]
            : []
        let sorted = sortOrder == "name"
            ? vm.collections.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            : vm.collections.sorted { $0.createdAt < $1.createdAt }
        let rest = sorted.map { (id: $0.id, name: $0.name, isDefault: false) }
        return defaults + rest
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Collections")
                    .font(.inter(17, weight: .heavy))
                    .foregroundColor(.textPrimary)
                Spacer()
                // Sort toggle
                Button {
                    sortOrder = sortOrder == "name" ? "date" : "name"
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sortOrder == "name" ? "textformat.abc" : "calendar")
                            .font(.system(size: 11, weight: .semibold))
                        Text(sortOrder == "name" ? "A–Z" : "Date")
                            .font(.inter(11, weight: .semibold))
                    }
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                if !selected.isEmpty {
                    Button {
                        let realSelected = selected.filter { $0 != defaultKey }
                        let deletingDefault = selected.contains(defaultKey)

                        // Block if trying to delete the currently active collection
                        let activeIsDefault = vm.activeCollection == nil
                        if deletingDefault && activeIsDefault { onActiveError(); return }
                        if let active = vm.activeCollection, realSelected.contains(active.id) { onActiveError(); return }

                        // Safeguard: at least 1 collection must remain
                        let myCollCount = (showMyCollection && !deletingDefault) ? 1 : 0
                        let remaining = myCollCount + (vm.collections.count - realSelected.count)
                        guard remaining >= 1 else { onMinOneError(); return }

                        // All checks passed — show confirmation
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteConfirm = true }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .font(.inter(12, weight: .bold))
                        .foregroundColor(.danger)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Color.danger.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.danger.opacity(0.2), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                Button {
                    let df = DateFormatter()
                    df.dateFormat = "MMMM d"
                    onRequestNewCollection(df.string(from: Date()))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New")
                    }
                    .font(.inter(12, weight: .bold))
                    .foregroundColor(.brandCyan)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(LinearGradient(colors: [Color.brandBlue.opacity(0.24), Color.brandNavy.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.brandBlue.opacity(0.42), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) { Divider().background(Color.white.opacity(0.07)) }

            // Collection rows
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(allRows, id: \.id) { row in
                            let isActive = row.isDefault
                                ? vm.activeCollection == nil
                                : vm.activeCollection?.id == row.id
                            let allStored = LocalItemStore.shared.all()
                            let meta = row.isDefault
                                ? "\(allStored.filter { $0.collectionId == nil || ($0.collectionId?.isEmpty ?? true) }.count) items"
                                : "\(allStored.filter { $0.collectionId == row.id }.count) items"
                            collRow(key: row.id, name: row.name, meta: meta, isActive: isActive, isDefault: row.isDefault)
                                .id(row.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 340)
                .onChange(of: vm.activeCollection?.id) { newId in
                    guard let newId else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color(hex: "#081221"))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.brandCyan.opacity(0.5), Color.brandBlue.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .clipShape(RoundedBottomShape(radius: 24))
        .overlay(RoundedBottomShape(radius: 24).stroke(Color.brandBlue.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .overlay {
            if showDeleteConfirm {
                ZStack {
                    Color.black.opacity(0.65).ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteConfirm = false }
                        }
                    VStack(spacing: 16) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.danger)
                            .shadow(color: Color.danger.opacity(0.5), radius: 10)
                        let count = selected.count
                        Text("Delete \(count) collection\(count == 1 ? "" : "s")?")
                            .font(.inter(16, weight: .heavy))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("Items inside will not be deleted.")
                            .font(.inter(13))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteConfirm = false }
                            } label: {
                                Text("Cancel")
                                    .font(.inter(14, weight: .bold)).foregroundColor(.textTertiary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(Color.white.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteConfirm = false }
                                performDelete()
                            } label: {
                                Text("Delete")
                                    .font(.inter(14, weight: .heavy)).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(Color.danger.opacity(0.80))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(24)
                    .background(Color(hex: "#081221"))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.danger.opacity(0.35), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.danger.opacity(0.15), radius: 20)
                    .padding(.horizontal, 24)
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDeleteConfirm)
    }

    private func performDelete() {
        let realSelected = selected.filter { $0 != defaultKey }
        let deletingDefault = selected.contains(defaultKey)
        vm.collections.removeAll { realSelected.contains($0.id) }
        for id in realSelected {
            if let col = LocalCollectionStore.shared.all().first(where: { $0.id == id }) {
                TrashStore.shared.trashCollection(col)
            }
            LocalItemStore.shared.clearCollection(id)
            LocalCollectionStore.shared.delete(id)
        }
        if deletingDefault { showMyCollection = false }
        selected.removeAll()
    }

    private func collRow(key: String, name: String, meta: String, isActive: Bool, isDefault: Bool) -> some View {
        HStack(spacing: 12) {
            // Checkbox — select for deletion only, menu stays open
            Button { selected.toggle(key) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selected.contains(key)
                              ? LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Color.clear, Color.clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: 22)
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(selected.contains(key) ? Color.brandBlue : Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected.contains(key) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            // Row body — tap to pin (set active) without closing the menu
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(isActive ? Color.brandBlue.opacity(0.2) : Color.white.opacity(0.07))
                        .frame(width: 40, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(isActive ? Color.brandCyan.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1))
                    Image(systemName: "tray.full")
                        .font(.system(size: 16))
                        .foregroundColor(isActive ? .brandCyan : .textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.inter(14, weight: .bold)).foregroundColor(.textPrimary)
                    Text(meta + (isActive ? " · Active" : "")).font(.inter(11)).foregroundColor(.textTertiary)
                }
                Spacer()
                if isActive {
                    Text("📌")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 32)
                }

                // Chevron — pin AND close the menu
                Button {
                    vm.selectCollection(isDefault ? nil : vm.collections.first { $0.id == key })
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.brandCyan)
                        .frame(width: 32, height: 32)
                        .background(Color.brandBlue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Pin only — menu stays open so user can keep browsing or delete
                vm.selectCollection(isDefault ? nil : vm.collections.first { $0.id == key })
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isActive ? Color.brandBlue.opacity(0.06) : .clear)
        .overlay(alignment: .bottom) { Divider().background(Color.white.opacity(0.05)) }
    }
}

// Rounded only on bottom corners
struct RoundedBottomShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) { remove(element) } else { insert(element) }
    }
}

extension DashboardViewModel {
    func deleteItem(_ item: Item) {
        // Soft-delete to trash before wiping
        if let stored = LocalItemStore.shared.all().first(where: { $0.id == item.id }) {
            TrashStore.shared.trashItem(stored)
        }
        for t in LocalTranscriptStore.shared.transcripts(for: item.id) where !t.isMerge {
            TrashStore.shared.trashTranscript(t, itemName: item.name)
        }
        for n in LocalNoteStore.shared.notes(for: item.id) {
            TrashStore.shared.trashNote(n, itemName: item.name)
        }
        for rec in LocalRecordingStore.shared.recordings(for: item.id) {
            TrashStore.shared.trashRecording(rec, itemName: item.name)
        }
        items.removeAll { $0.id == item.id }
        LocalItemStore.shared.delete(item.id)
        LocalTranscriptStore.shared.deleteAll(for: item.id)
        LocalNoteStore.shared.deleteAll(for: item.id)
        localAudioCounts.removeValue(forKey: item.id)
    }

    @discardableResult
    func createItem(name: String) -> Item {
        let stored = LocalStoredItem(
            id: UUID().uuidString,
            name: name,
            collection: activeCollection?.name,
            collectionId: activeCollection?.id,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        LocalItemStore.shared.save(stored)
        let item = buildLocalItem(stored)
        items.insert(item, at: 0)
        return item
    }
}

// MARK: - Item Context Menu
struct ItemMenuView: View {
    let item: Item
    @ObservedObject var vm: DashboardViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.sheetBg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Handle
                Capsule().fill(Color.white.opacity(0.15)).frame(width: 36, height: 4).padding(.top, 12).padding(.bottom, 8)

                Text(item.name)
                    .font(.inter(14, weight: .heavy))
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 4)

                Divider().background(Color.white.opacity(0.07)).padding(.bottom, 4)

                SectionLabel(text: "Files")

                menuRow(icon: "🎵", color: .stageMedia, title: "Import Audio File") {}
                menuRow(icon: "📄", color: .brandBlue, title: "Import Document File") {}

                Divider().background(Color.white.opacity(0.07)).padding(.vertical, 4)

                menuRow(icon: "🎙️", color: .brandCyan, title: "Record New Audio") {}
                menuRow(icon: "✦", color: Color(hex: "#a78bfa"), title: "Apply Prompt to All Text") {}

                Divider().background(Color.white.opacity(0.07)).padding(.vertical, 4)

                menuRow(icon: "✏️", color: .textSecondary, title: "Rename") {}
                menuRow(icon: "🗑", color: .danger, title: "Delete Item", isDanger: true) {}

                Spacer().frame(height: 24)
            }
        }
    }

    private func menuRow(icon: String, color: Color, title: String, isDanger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: { action(); dismiss() }) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 15))
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                Text(title)
                    .font(.inter(14, weight: .semibold))
                    .foregroundColor(isDanger ? .danger : .textPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Integration metadata sheet

struct IntegrationMetaSheet: View {
    let meta: IntegrationItemMetadata
    @Environment(\.dismiss) var dismiss

    private var dateFmt: DateFormatter {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Integration Source")
                            .font(.inter(16, weight: .heavy))
                            .foregroundColor(.textPrimary)
                        Text(meta.integrationName)
                            .font(.inter(12))
                            .foregroundColor(.textTertiary)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // Sync info card
                        infoCard(label: "Sync Info") {
                            infoRow(label: meta.identifierLabel, value: meta.sourceIdentifier, mono: true, isLast: false)
                            infoRow(label: "Last synced", value: dateFmt.string(from: meta.lastSynced), mono: false, isLast: true)
                        }

                        // Raw fields card — exclude keys already shown in Sync Info
                        let hiddenKeys: Set<String> = ["patient_name"]
                        let ehrKeys = meta.rawFields.keys.filter { !hiddenKeys.contains($0.lowercased()) }.sorted()
                        if !ehrKeys.isEmpty {
                            infoCard(label: "EHR Fields") {
                                ForEach(ehrKeys, id: \.self) { key in
                                    infoRow(label: key.replacingOccurrences(of: "_", with: " "),
                                            value: meta.rawFields[key] ?? "", mono: false,
                                            isLast: key == ehrKeys.last)
                                }
                            }
                        }

                        Spacer().frame(height: 32)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func infoCard(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.inter(10, weight: .heavy))
                .foregroundColor(.textTertiary)
                .tracking(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            content()
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func infoRow(label: String, value: String, mono: Bool, isLast: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label.capitalized)
                .font(.inter(11, weight: .bold))
                .foregroundColor(.textTertiary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 11, design: .monospaced) : .inter(12, weight: .semibold))
                .foregroundColor(mono ? Color.brandCyan.opacity(0.85) : .textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        if !isLast {
            Divider().background(Color.white.opacity(0.05)).padding(.leading, 16)
        }
    }
}
