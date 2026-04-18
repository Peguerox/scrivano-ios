import SwiftUI
import UIKit

enum PromptsContext {
    /// Generate a note from selected transcript texts
    case applyToText(transcriptTexts: [String], itemId: String, transcriptIds: [String])
    /// Generate a note (same as applyToText, kept for semantic clarity)
    case generateNote(transcriptTexts: [String], itemId: String, transcriptIds: [String])
    /// Generate notes for multiple items — one note per item, processed sequentially
    case applyToItems(items: [(texts: [String], itemId: String, transcriptIds: [String])])
    /// Process an image with the selected prompt
    case imageProcess(imageId: String, imageURL: URL, itemId: String, itemName: String)
    /// Pick prompts to save for Automatic Note automation (no immediate generation)
    case selectForAutomation
    case browse
}

// MARK: - Filter category definition

private enum FilterCategory: String, Identifiable, CaseIterable {
    case profession = "Professions"
    case author     = "Authors"
    case language   = "Languages"
    case noteType   = "Note Types"

    var id: String { rawValue }

    var translationKey: String {
        switch self {
        case .profession: return "prompts.cat.professions"
        case .author:     return "prompts.cat.authors"
        case .language:   return "prompts.cat.languages"
        case .noteType:   return "prompts.cat.noteTypes"
        }
    }

    var key: String {
        switch self {
        case .profession: return "profession"
        case .author:     return "author"
        case .language:   return "language"
        case .noteType:   return "note_type"
        }
    }

    var icon: String {
        switch self {
        case .profession: return "briefcase.fill"
        case .author:     return "person.fill"
        case .language:   return "globe"
        case .noteType:   return "doc.text.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .profession: return Color(hex: "#818cf8")   // indigo
        case .author:     return Color(hex: "#fb923c")   // orange
        case .language:   return Color(hex: "#38d9f5")   // cyan
        case .noteType:   return Color(hex: "#fbbf24")   // amber
        }
    }
}

// MARK: - PromptsView

struct PromptsView: View {
    let context: PromptsContext
    @EnvironmentObject var langMgr: LanguageManager
    @Environment(\.dismiss) var dismiss
    @State private var prompts: [Prompt] = []
    @State private var search = ""
    @State private var isLoading = false
    @State private var isApplying = false
    @State private var selectedTab: PromptTab
    @State private var error: String? = nil
    @State private var appliedIds = Set<String>()

    // Prompt selection (for apply flow)
    @State private var selectedPromptIds = Set<String>()

    // Filters
    @State private var showFilters = false
    @State private var selectedProfessions: Set<String> = []
    @State private var selectedAuthors:     Set<String> = []
    @State private var selectedLanguages:   Set<String> = []
    @State private var selectedNoteTypes:   Set<String> = []
    @State private var activeFilterCat: FilterCategory? = nil

    // MARK: - Favorites
    @AppStorage("favoritePromptIds") private var favoriteIdsRaw: String = ""

    @AppStorage("auto_note_prompts_encoded") private var autoNotePromptsEncoded: String = ""

    private var isSelectMode: Bool {
        if case .browse = context { return false }
        return true
    }

    private var isAutomationMode: Bool {
        if case .selectForAutomation = context { return true }
        return false
    }

    init(context: PromptsContext) {
        self.context = context
        // Open on Favorites when in selection mode, All when browsing
        if case .browse = context {
            self._selectedTab = State(initialValue: .all)
        } else {
            self._selectedTab = State(initialValue: .favorites)
        }
    }

    private var favoriteIds: Set<String> {
        Set(favoriteIdsRaw.split(separator: ",").map(String.init))
    }

    private func toggleFavorite(_ id: String) {
        var ids = favoriteIds
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        favoriteIdsRaw = ids.joined(separator: ",")
    }

    enum PromptTab: String, CaseIterable {
        case all = "All"
        case favorites = "Favorites"
        case custom = "Custom"

        var translationKey: String {
            switch self {
            case .all:       return "prompts.tab.all"
            case .favorites: return "prompts.tab.favorites"
            case .custom:    return "prompts.tab.custom"
            }
        }

        var icon: String {
            switch self {
            case .all:       return "sparkles"
            case .favorites: return "star.fill"
            case .custom:    return "pencil"
            }
        }

        var activeColor: Color {
            switch self {
            case .all:       return Color(hex: "#38d9f5")
            case .favorites: return Color(hex: "#f59e0b")
            case .custom:    return Color(hex: "#a78bfa")
            }
        }
    }

    // MARK: - Filter helpers

    private var activeFilterCount: Int {
        selectedProfessions.count + selectedAuthors.count + selectedLanguages.count + selectedNoteTypes.count
    }

    private var userEmail: String { AuthManager.shared.currentUser?.email ?? "" }

    private func values(for cat: FilterCategory) -> [String] {
        if cat == .author {
            // Always show exactly two options regardless of raw author values
            return ["Scrivano", "My Prompts"]
        }
        return Array(Set(prompts.compactMap { $0.categories[cat.key] }.filter { !$0.isEmpty })).sorted()
    }

    private func selectedSet(for cat: FilterCategory) -> Binding<Set<String>> {
        switch cat {
        case .profession: return $selectedProfessions
        case .author:     return $selectedAuthors
        case .language:   return $selectedLanguages
        case .noteType:   return $selectedNoteTypes
        }
    }

    private func count(for cat: FilterCategory) -> Int {
        switch cat {
        case .profession: return selectedProfessions.count
        case .author:     return selectedAuthors.count
        case .language:   return selectedLanguages.count
        case .noteType:   return selectedNoteTypes.count
        }
    }

    private func clearCategory(_ cat: FilterCategory) {
        switch cat {
        case .profession: selectedProfessions = []
        case .author:     selectedAuthors = []
        case .language:   selectedLanguages = []
        case .noteType:   selectedNoteTypes = []
        }
    }

    private func clearAllFilters() {
        selectedProfessions = []; selectedAuthors = []; selectedLanguages = []; selectedNoteTypes = []
    }

    // MARK: - Filtered list

    private func isScrivano(_ author: String) -> Bool {
        author.isEmpty || author.lowercased() == "scrivano"
    }

    private func matchesSearch(_ p: Prompt) -> Bool {
        let q = search.lowercased()
        if p.name.lowercased().contains(q) { return true }
        if p.displayName.lowercased().contains(q) { return true }
        if p.overview.lowercased().contains(q) { return true }
        if p.description.lowercased().contains(q) { return true }
        return false
    }

    var filtered: [Prompt] {
        // Image context: only show prompts with note_type == "Image"
        if case .imageProcess = context {
            return prompts.filter { ($0.categories["note_type"] ?? "") == "Image" }
        }

        // Only show prompts owned by the current user or official Scrivano prompts
        var list = prompts.filter { prompt in
            let author = prompt.categories["author"] ?? ""
            return author == userEmail || isScrivano(author)
        }
        if !search.isEmpty {
            list = list.filter { matchesSearch($0) }
        }
        switch selectedTab {
        case .favorites: list = list.filter { favoriteIds.contains($0.id) }
        case .custom:    list = list.filter { $0.promptType == "custom" }
        default: break
        }
        if !selectedProfessions.isEmpty {
            list = list.filter { selectedProfessions.contains($0.categories["profession"] ?? "") }
        }
        if !selectedAuthors.isEmpty {
            list = list.filter { prompt in
                let author = prompt.categories["author"] ?? ""
                return selectedAuthors.contains { selection in
                    if selection == "My Prompts" { return author == userEmail }
                    if selection == "Scrivano"   { return isScrivano(author) }
                    return false
                }
            }
        }
        if !selectedLanguages.isEmpty {
            list = list.filter { selectedLanguages.contains($0.categories["language"] ?? "") }
        }
        if !selectedNoteTypes.isEmpty {
            list = list.filter { selectedNoteTypes.contains($0.categories["note_type"] ?? "") }
        }
        return list
    }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.brandCyan)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text(langMgr.t("prompts.title"))
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button {
                        if activeFilterCount > 0 {
                            withAnimation(.easeInOut(duration: 0.2)) { clearAllFilters(); showFilters = false }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(activeFilterCount > 0 ? .brandCyan : .textTertiary)
                            .frame(width: 36, height: 36)
                            .background(activeFilterCount > 0 ? Color.brandBlue.opacity(0.2) : Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }

                // Info
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.textQuaternary)
                    Text(isAutomationMode
                         ? langMgr.t("prompts.hint.automation")
                         : isSelectMode
                             ? langMgr.t("prompts.hint.select")
                             : langMgr.t("prompts.hint.browse"))
                        .font(.inter(11))
                        .foregroundColor(.textQuaternary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)

                // Search + filter pill
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(.textTertiary)
                        TextField("Search prompts…", text: $search)
                            .font(.inter(14))
                            .foregroundColor(.textPrimary)
                            .autocorrectionDisabled()
                        if !search.isEmpty {
                            Button { search = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.textQuaternary)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color.white.opacity(0.065))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(search.isEmpty ? Color.white.opacity(0.12) : Color.brandCyan.opacity(0.4), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Filter pill — same height as search bar
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showFilters.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 13, weight: .semibold))
                            Text(langMgr.t("prompts.filter"))
                                .font(.inter(14, weight: .bold))
                            Image(systemName: showFilters ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.brandCyan)
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(Color.brandBlue.opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandCyan.opacity(0.5), lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

                // Filter dropdown — expands downward from search row
                if showFilters {
                    filterDropdown
                        .transition(.scale(scale: 0.01, anchor: .top).combined(with: .opacity))
                        .padding(.bottom, 6)
                }

                // Results count
                HStack {
                    Text("\(langMgr.t("prompts.results")) · \(filtered.count)")
                        .font(.inter(10, weight: .heavy))
                        .tracking(0.5)
                        .foregroundColor(.textQuaternary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

                if let err = error {
                    Text(err).font(.inter(11)).foregroundColor(.danger).padding(.horizontal, 18)
                }

                // Image-only banner
                if case .imageProcess = context {
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 11, weight: .medium))
                        Text("Only prompts available for image processing are shown")
                            .font(.inter(11))
                    }
                    .foregroundColor(Color(hex: "#34d399"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                }

                // Prompt list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { prompt in
                            PromptCard(
                                prompt: prompt,
                                isFavorite: favoriteIds.contains(prompt.id),
                                isSelected: selectedPromptIds.contains(prompt.id),
                                isSelectMode: isSelectMode,
                                onToggleFavorite: { toggleFavorite(prompt.id) },
                                onToggleSelect: {
                                    if selectedPromptIds.contains(prompt.id) {
                                        selectedPromptIds.remove(prompt.id)
                                    } else {
                                        selectedPromptIds.insert(prompt.id)
                                    }
                                }
                            )
                        }
                        if filtered.isEmpty && !isLoading {
                            Text(langMgr.t("prompts.noPrompts")).font(.inter(13)).foregroundColor(.textQuaternary).padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 80)
                }
                .refreshable { await loadPrompts() }

                // Apply button (selection mode only)
                if isSelectMode {
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                        Button {
                            applySelected()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill").font(.system(size: 14, weight: .bold))
                                Text(selectedPromptIds.isEmpty
                                     ? langMgr.t("prompts.selectPrompt")
                                     : isAutomationMode
                                         ? langMgr.t("prompts.activateForAutomation").replacingOccurrences(of: "%d", with: "\(selectedPromptIds.count)")
                                         : langMgr.t("prompts.applyPrompts").replacingOccurrences(of: "%d", with: "\(selectedPromptIds.count)"))
                                    .font(.inter(15, weight: .heavy))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(
                                colors: [Color.stageText.opacity(selectedPromptIds.isEmpty ? 0.15 : 0.8),
                                         Color.stageText.opacity(selectedPromptIds.isEmpty ? 0.08 : 0.6)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.stageText.opacity(selectedPromptIds.isEmpty ? 0.2 : 0.4), lineWidth: 1.5))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(selectedPromptIds.isEmpty)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                    }
                    .background(Color.phoneBg)
                }

                // Tab bar
                HStack(spacing: 0) {
                    ForEach(Array(PromptTab.allCases.enumerated()), id: \.offset) { idx, tab in
                        let isOn = tab == selectedTab
                        if idx > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 1, height: 36)
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 17, weight: .semibold))
                                Text(langMgr.t(tab.translationKey))
                                    .font(.inter(12, weight: .bold))
                            }
                            .foregroundColor(isOn ? tab.activeColor : Color.white.opacity(0.28))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(alignment: .top) {
                                if isOn {
                                    Rectangle().fill(tab.activeColor).frame(height: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background {
                    ZStack {
                        Color.phoneBg
                        HStack(spacing: 0) {
                            ForEach(PromptTab.allCases, id: \.self) { tab in
                                (tab == selectedTab ? tab.activeColor.opacity(0.07) : Color.clear)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            }

            if isLoading { LoadingOverlay() }
            if isApplying { LoadingOverlay(message: "Applying…") }
        }
        .task { await loadPrompts() }
        .onAppear {
            // Pre-populate selection from saved automation prompts
            if isAutomationMode, !autoNotePromptsEncoded.isEmpty {
                let ids = autoNotePromptsEncoded.split(separator: ",").compactMap { pair -> String? in
                    let parts = pair.split(separator: "|", maxSplits: 1)
                    return parts.count >= 1 ? String(parts[0]) : nil
                }
                selectedPromptIds = Set(ids)
            }
        }
        .sheet(item: $activeFilterCat) { cat in
            FilterPickerSheet(
                title: langMgr.t(cat.translationKey),
                values: values(for: cat),
                selected: selectedSet(for: cat)
            )
        }
    }

    // MARK: - Filter dropdown

    private var filterDropdown: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(FilterCategory.allCases) { cat in
                    let cnt = count(for: cat)
                    Button {
                        activeFilterCat = cat
                    } label: {
                        HStack(spacing: 14) {
                            // Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(cat.iconColor.opacity(0.15))
                                    .frame(width: 34, height: 34)
                                Image(systemName: cat.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(cat.iconColor)
                            }

                            Text(langMgr.t(cat.translationKey))
                                .font(.inter(14, weight: .semibold))
                                .foregroundColor(.textPrimary)

                            Spacer()

                            // Count badge
                            if cnt > 0 {
                                Text("\(cnt) selected")
                                    .font(.inter(11, weight: .heavy))
                                    .foregroundColor(.brandCyan)
                                    .padding(.horizontal, 9).padding(.vertical, 3)
                                    .background(Color.brandBlue.opacity(0.2))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.brandCyan.opacity(0.4), lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))

                                Button { clearCategory(cat) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color.white.opacity(0.5))
                                        .frame(width: 20, height: 20)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(langMgr.t("common.none"))
                                    .font(.inter(11, weight: .bold))
                                    .foregroundColor(Color.white.opacity(0.3))
                                    .padding(.horizontal, 9).padding(.vertical, 3)
                                    .background(Color.white.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.09), lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.3))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if cat != FilterCategory.allCases.last {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                            .padding(.leading, 64)
                    }
                }
            }
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.09), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 18)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFilters = false }
            } label: {
                Text(langMgr.t("misc.hideFilters"))
                    .font(.inter(11, weight: .bold))
                    .foregroundColor(Color.brandCyan.opacity(0.5))
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    private func loadPrompts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await APIClient.shared.request(path: "/api/prompts", responseType: PromptsResponse.self)
            if res.success { prompts = res.data }
        } catch { self.error = error.localizedDescription }
    }

    private func apply(prompt: Prompt) async {
        isApplying = true
        defer { isApplying = false }

        switch context {
        case .applyToText(let texts, let itemId, _), .generateNote(let texts, let itemId, _):
            let combinedText = texts.joined(separator: "\n\n")
            struct Body: Encodable {
                let transcript: String
                let promptId: String
                enum CodingKeys: String, CodingKey {
                    case transcript
                    case promptId = "prompt_id"
                }
            }
            struct Res: Decodable {
                let success: Bool
                let taskId: String?
                enum CodingKeys: String, CodingKey { case success; case taskId = "task_id" }
            }
            do {
                let res = try await APIClient.shared.request(
                    path: "/api/notes/generate",
                    method: "POST",
                    body: Body(transcript: combinedText, promptId: prompt.id),
                    responseType: Res.self
                )
                guard let taskId = res.taskId else {
                    self.error = "Failed to start note generation."
                    return
                }
                // Poll and save
                let api = APIClient.shared
                var attempt = 0
                while attempt < 60 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    let result = try await api.pollNoteResult(taskId: taskId)
                    switch result.status {
                    case "completed":
                        if let paid = result.credit, let free = result.freeCredit {
                            await AuthManager.shared.updateCredits(paid: paid, free: free)
                        }
                        if let text = result.note {
                            LocalNoteStore.shared.add(LocalNoteEntry(
                                id: UUID().uuidString,
                                itemId: itemId,
                                label: prompt.name,
                                text: text,
                                promptType: prompt.promptType ?? "general",
                                createdAt: Date()
                            ))
                            appliedIds.insert(prompt.id)
                            sendCompletionNotification(title: "Note Ready", body: "Your note has been generated.")
                        } else {
                            self.error = "No note text returned."
                        }
                        return
                    case "failed":
                        self.error = result.error ?? "Generation failed."
                        return
                    default: break
                    }
                    attempt += 1
                }
                self.error = "Generation timed out."
            } catch { self.error = error.localizedDescription }

        case .imageProcess(let imageId, let imageURL, let itemId, let itemName):
            ImageProcessingManager.shared.start(
                imageId: imageId,
                imageURL: imageURL,
                promptId: prompt.id,
                itemId: itemId,
                itemName: itemName
            )
            dismiss()

        case .browse, .selectForAutomation, .applyToItems:
            appliedIds.insert(prompt.id)
        }
    }

    private func applySelected() {
        let toApply = prompts.filter { selectedPromptIds.contains($0.id) }
        guard !toApply.isEmpty else { return }

        switch context {
        case .selectForAutomation:
            // Save id|name pairs to AppStorage, then dismiss
            let encoded = toApply.map { "\($0.id)|\($0.name)" }.joined(separator: ",")
            autoNotePromptsEncoded = encoded
            dismiss()

        case .applyToText(let texts, let itemId, let tIds),
             .generateNote(let texts, let itemId, let tIds):
            // Dismiss immediately — user sees progress in TextListView / Dashboard
            dismiss()
            let combined = texts.joined(separator: "\n\n")
            let promptsSnapshot = toApply
            NoteGenerationManager.shared.markQueued(itemId: itemId, transcriptIds: tIds)
            TaskQueueManager.shared.enqueue {
                guard !Task.isCancelled else { return }
                NoteGenerationManager.shared.begin(itemId: itemId, transcriptIds: tIds)
                var success = true
                for prompt in promptsSnapshot {
                    guard !Task.isCancelled else { success = false; break }
                    let ok = await runNoteGeneration(
                        text: combined, promptId: prompt.id,
                        itemId: itemId, promptName: prompt.name
                    )
                    if !ok { success = false; break }
                }
                NoteGenerationManager.shared.finish(itemId: itemId, success: success)
            }

        case .applyToItems(let itemGroups):
            dismiss()
            let promptsSnapshot = toApply
            // Mark every item as queued upfront so TextListView shows hourglass immediately
            for group in itemGroups {
                NoteGenerationManager.shared.markQueued(itemId: group.itemId, transcriptIds: group.transcriptIds)
            }
            for group in itemGroups {
                let combined = group.texts.joined(separator: "\n\n")
                let groupRef = group
                TaskQueueManager.shared.enqueue {
                    guard !Task.isCancelled else { return }
                    NoteGenerationManager.shared.begin(itemId: groupRef.itemId, transcriptIds: groupRef.transcriptIds)
                    var success = true
                    for prompt in promptsSnapshot {
                        guard !Task.isCancelled else { success = false; break }
                        let ok = await runNoteGeneration(
                            text: combined, promptId: prompt.id,
                            itemId: groupRef.itemId, promptName: prompt.name
                        )
                        if !ok { success = false; break }
                    }
                    NoteGenerationManager.shared.finish(itemId: groupRef.itemId, success: success)
                }
            }

        default:
            // imageProcess / browse — fall through to existing per-prompt apply
            Task { await apply(prompt: toApply[0]) }
        }
    }

    /// Standalone note generation — does not touch any view @State, safe to run after dismiss.
    private func runNoteGeneration(text: String, promptId: String, itemId: String, promptName: String) async -> Bool {
        struct Body: Encodable {
            let transcript: String
            let promptId: String
            enum CodingKeys: String, CodingKey { case transcript; case promptId = "prompt_id" }
        }
        struct Res: Decodable {
            let success: Bool
            let taskId: String?
            enum CodingKeys: String, CodingKey { case success; case taskId = "task_id" }
        }
        appLog("POST [notes endpoint] — prompt: \(promptName), item: \(itemId)", level: .info)
        do {
            let res = try await APIClient.shared.request(
                path: "/api/notes/generate", method: "POST",
                body: Body(transcript: text, promptId: promptId),
                timeout: 120,
                responseType: Res.self
            )
            guard let taskId = res.taskId else {
                appLog("  [notes endpoint] — no task_id returned (success=\(res.success))", level: .error)
                return false
            }
            appLog("  task_id: \(taskId) — polling...", level: .info)
            var attempt = 0
            while attempt < 60 {
                guard !Task.isCancelled else { return false }
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return false }
                guard !Task.isCancelled else { return false }
                do {
                    let result = try await APIClient.shared.pollNoteResult(taskId: taskId)
                    switch result.status {
                    case "completed":
                        appLog("[CREDITS] Charged: \(String(format: "%.4f", result.creditCharge ?? 0)) | Balance: paid=\(String(format: "%.4f", result.credit ?? 0))  free=\(String(format: "%.0f", result.freeCredit ?? 0))", level: .info)
                        if let paid = result.credit, let free = result.freeCredit {
                            await AuthManager.shared.updateCredits(paid: paid, free: free)
                        }
                        if let noteText = result.note {
                            let itemName = LocalItemStore.shared.all().first(where: { $0.id == itemId })?.name ?? itemId
                            let label = "Note-\(itemName)-\(promptName)"
                            LocalNoteStore.shared.addOrReplace(LocalNoteEntry(
                                id: UUID().uuidString, itemId: itemId,
                                label: label, text: noteText,
                                promptType: promptName, createdAt: Date()
                            ))
                            appLog("  Note generated OK — \(label)", level: .success)
                            sendCompletionNotification(title: "Note Ready", body: "Your note has been generated.")
                            return true
                        }
                        appLog("  [notes endpoint] — status completed but note text is nil", level: .error)
                        sendCompletionNotification(title: "Note Failed", body: "Note generation completed but returned no text.")
                        return false
                    case "failed":
                        let serverErr = result.error ?? "no error message"
                        appLog("  [notes endpoint] — status: failed — \(serverErr) (task: \(taskId))", level: .error)
                        sendCompletionNotification(title: "Note Failed", body: serverErr)
                        return false
                    default:
                        break
                    }
                } catch {
                    guard !Task.isCancelled else { return false }
                    appLog("  Poll attempt \(attempt + 1) error: \(error.localizedDescription)", level: .warning)
                }
                attempt += 1
            }
                        appLog("  [notes endpoint] — timed out after \(attempt) attempts (task: \(taskId))", level: .error)
            sendCompletionNotification(title: "Note Failed", body: "Note generation timed out for prompt: \(promptName).")
        } catch {
            appLog("  [notes endpoint] — request failed: \(error.localizedDescription)", level: .error)
            sendCompletionNotification(title: "Note Failed", body: "Could not start note generation: \(error.localizedDescription)")
        }
        return false
    }
}

// MARK: - Filter picker sheet

private struct FilterPickerSheet: View {
    let title: String
    let values: [String]
    @Binding var selected: Set<String>
    @Environment(\.dismiss) var dismiss
    @State private var localSelected: Set<String> = []
    @State private var search = ""

    private var filtered: [String] {
        search.isEmpty ? values : values.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack {
            Color(hex: "#081221").ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    // X — cancel, revert to original selection
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text(title)
                        .font(.inter(17, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    // Checkmark — accept and apply
                    Button {
                        selected = localSelected
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.brandCyan)
                            .frame(width: 30, height: 30)
                            .background(Color.brandBlue.opacity(0.25))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)
                .onAppear { localSelected = selected }

                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.textQuaternary)
                    TextField("Search...", text: $search)
                        .font(.inter(14))
                        .foregroundColor(.textPrimary)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.white.opacity(0.065))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20).padding(.bottom, 16)

                // Grid
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(filtered, id: \.self) { value in
                            let isOn = localSelected.contains(value)
                            Button {
                                if isOn { localSelected.remove(value) } else { localSelected.insert(value) }
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .stroke(isOn ? Color.brandCyan : Color.white.opacity(0.25), lineWidth: 1.5)
                                            .frame(width: 18, height: 18)
                                        if isOn {
                                            Circle().fill(Color.brandCyan).frame(width: 10, height: 10)
                                        }
                                    }
                                    Text(value)
                                        .font(.inter(13))
                                        .foregroundColor(.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 11)
                                .background(isOn ? Color.brandBlue.opacity(0.15) : Color.white.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                    isOn ? Color.brandCyan.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - PromptCard

struct PromptCard: View {
    let prompt: Prompt
    var isFavorite: Bool
    var isSelected: Bool = false
    var isSelectMode: Bool = false
    var onToggleFavorite: () -> Void
    var onToggleSelect: () -> Void = {}

    @State private var showExample = false

    private var isHighlighted: Bool { isSelectMode ? isSelected : isFavorite }

    var body: some View {
        VStack(spacing: 0) {
            // ── Tappable body ──
            Button(action: isSelectMode ? onToggleSelect : onToggleFavorite) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(prompt.displayName)
                            .font(.inter(14, weight: .bold))
                            .foregroundColor(isHighlighted ? .brandCyan : .textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isSelectMode {
                            // Selection checkbox
                            ZStack {
                                Circle()
                                    .stroke(isSelected ? Color.brandCyan : Color.white.opacity(0.3), lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                                if isSelected {
                                    Circle().fill(Color.brandCyan).frame(width: 22, height: 22)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.leading, 6)
                        } else {
                            // Favorite star
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 14))
                                .foregroundColor(isFavorite ? Color(hex: "#facc15") : Color.white.opacity(0.25))
                                .padding(.leading, 6)
                        }
                    }

                    Text(prompt.overview)
                        .font(.inter(12))
                        .foregroundColor(.textTertiary)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── Footer ──
            HStack(spacing: 6) {
                if let profession = prompt.categories["profession"], !profession.isEmpty {
                    categoryTag(profession)
                }
                if let language = prompt.categories["language"], !language.isEmpty {
                    categoryTag(language)
                }
                if let cost = prompt.averageCreditCost, cost > 0 {
                    creditTag(cost)
                }

                Spacer()

                // Expand chevron (only if example exists)
                if prompt.example != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showExample.toggle() }
                    } label: {
                        Image(systemName: showExample ? "chevron.up" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.textQuaternary)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.black.opacity(0.12))
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }

            // ── Expanded example ──
            if showExample, let example = prompt.example {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Example")
                        .font(.inter(10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundColor(.textQuaternary)
                        .textCase(.uppercase)
                    Text(example)
                        .font(.inter(12))
                        .foregroundColor(.textTertiary)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.025))
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
            }
        }
        .background(isHighlighted ? Color.brandBlue.opacity(0.07) : Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isHighlighted ? Color.brandCyan.opacity(0.3) : Color.white.opacity(0.07),
                        lineWidth: isHighlighted ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func creditTag(_ cost: Double) -> some View {
        let label = cost.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "⚡ %.0f cr", cost)
            : String(format: "⚡ %.1f cr", cost)
        return Text(label)
            .font(.inter(9, weight: .heavy))
            .foregroundColor(Color(hex: "#facc15").opacity(0.85))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color(hex: "#facc15").opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: "#facc15").opacity(0.25), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func categoryTag(_ text: String) -> some View {
        let color = Self.tagColor(for: text)
        return Text(text.uppercased())
            .font(.inter(9, weight: .heavy))
            .tracking(0.4)
            .foregroundColor(color.opacity(0.9))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private static func tagColor(for text: String) -> Color {
        switch text.lowercased() {
        // Languages
        case "english":    return Color(hex: "#4ade80") // green
        case "spanish":    return Color(hex: "#f87171") // red
        case "portuguese": return Color(hex: "#34d399") // emerald
        case "french":     return Color(hex: "#a78bfa") // purple
        case "german":     return Color(hex: "#facc15") // yellow
        case "italian":    return Color(hex: "#fb7185") // rose
        case "chinese":    return Color(hex: "#f87171") // red
        case "japanese":   return Color(hex: "#e879f9") // fuchsia
        case "arabic":     return Color(hex: "#2dd4bf") // teal
        case "russian":    return Color(hex: "#c084fc") // violet
        case "korean":     return Color(hex: "#f472b6") // pink
        // Professions
        case "medicine", "medical":    return Color(hex: "#38bdf8") // blue
        case "general":                return Color(hex: "#a78bfa") // purple
        case "legal", "law":           return Color(hex: "#facc15") // amber
        case "education":              return Color(hex: "#4ade80") // green
        case "business":               return Color(hex: "#fb923c") // orange
        case "technology", "tech":     return Color(hex: "#a78bfa") // purple
        case "journalism", "media":    return Color(hex: "#fbbf24") // gold
        case "psychology":             return Color(hex: "#c084fc") // violet
        case "finance":                return Color(hex: "#f59e0b") // amber-gold
        case "science":                return Color(hex: "#2dd4bf") // teal
        case "creative", "writing":    return Color(hex: "#f472b6") // pink
        case "marketing":              return Color(hex: "#fb7185") // rose
        case "human resources", "hr":  return Color(hex: "#34d399") // emerald
        default:
            // Hash the string to pick a consistent non-blue/gray color
            let palette: [Color] = [
                Color(hex: "#f97316"), Color(hex: "#a78bfa"), Color(hex: "#4ade80"),
                Color(hex: "#f472b6"), Color(hex: "#facc15"), Color(hex: "#2dd4bf"),
                Color(hex: "#fb7185"), Color(hex: "#e879f9"), Color(hex: "#34d399"),
                Color(hex: "#fbbf24")
            ]
            let index = abs(text.hashValue) % palette.count
            return palette[index]
        }
    }
}
