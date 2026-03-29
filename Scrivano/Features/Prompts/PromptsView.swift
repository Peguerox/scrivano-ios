import SwiftUI

enum PromptsContext {
    case applyToText(selectedIds: [String], itemId: String)
    case generateNote(selectedTextIds: [String], itemId: String)
    case browse
}

struct PromptsView: View {
    let context: PromptsContext
    @Environment(\.dismiss) var dismiss
    @State private var prompts: [Prompt] = []
    @State private var search = ""
    @State private var isLoading = false
    @State private var isApplying = false
    @State private var selectedTab: PromptTab = .all
    @State private var showFilters = false
    @State private var error: String? = nil
    @State private var appliedIds = Set<String>()

    enum PromptTab: String, CaseIterable { case all = "All"; case favorites = "Favorites"; case custom = "Custom" }

    var filtered: [Prompt] {
        var list = prompts
        if !search.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) } }
        switch selectedTab {
        case .favorites: list = list.filter { $0.tags.contains("favorite") }
        case .custom: list = list.filter { $0.isCustom }
        default: break
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
                    Text("Prompts")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button("✕") { dismiss() }
                        .font(.inter(14, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 36, height: 36)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }

                // Info
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.textQuaternary)
                    Text("Tap a prompt to add to the pipeline")
                        .font(.inter(11))
                        .foregroundColor(.textQuaternary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)

                // Search
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(.textTertiary)
                        TextField("Search prompts…", text: $search)
                            .font(.inter(13))
                            .foregroundColor(.textPrimary)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        withAnimation { showFilters.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Filters")
                        }
                        .font(.inter(11, weight: .bold))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.white.opacity(0.07))
                        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

                // Results count
                HStack {
                    Text("Results · \(filtered.count)")
                        .font(.inter(11, weight: .bold))
                        .foregroundColor(.textQuaternary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 4)

                if let err = error {
                    Text(err).font(.inter(11)).foregroundColor(.danger).padding(.horizontal, 18)
                }

                // Prompt list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { prompt in
                            PromptCard(
                                prompt: prompt,
                                isApplied: appliedIds.contains(prompt.id),
                                isApplying: isApplying,
                                onUse: { Task { await apply(prompt: prompt) } }
                            )
                        }
                        if filtered.isEmpty && !isLoading {
                            Text("No prompts found").font(.inter(13)).foregroundColor(.textQuaternary).padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 80)
                }

                // Tab bar
                HStack(spacing: 0) {
                    ForEach(PromptTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                        } label: {
                            Text(tab.rawValue)
                                .font(.inter(12, weight: .bold))
                                .foregroundColor(selectedTab == tab ? .brandCyan : .textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(selectedTab == tab ? Color.brandBlue.opacity(0.15) : .clear)
                                .overlay(alignment: .top) {
                                    if selectedTab == tab {
                                        Rectangle().fill(Color.brandCyan).frame(height: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.phoneBg)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }

            if isLoading { LoadingOverlay() }
        }
        .task { await loadPrompts() }
    }

    private func loadPrompts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await APIClient.shared.request(path: "/api/prompts", responseType: PromptsResponse.self)
            if res.success { prompts = res.prompts }
        } catch { self.error = error.localizedDescription }
    }

    private func apply(prompt: Prompt) async {
        isApplying = true
        defer { isApplying = false }

        switch context {
        case .applyToText(let ids, let itemId):
            struct Body: Encodable {
                let promptId: String; let textFileIds: [String]; let itemId: String
                enum CodingKeys: String, CodingKey { case promptId = "prompt_id"; case textFileIds = "text_file_ids"; case itemId = "item_id" }
            }
            struct Res: Decodable { let success: Bool; let taskId: String?; enum CodingKeys: String, CodingKey { case success; case taskId = "task_id" } }
            do {
                let _ = try await APIClient.shared.request(
                    path: "/api/notes/generate",
                    method: "POST",
                    body: Body(promptId: prompt.id, textFileIds: ids, itemId: itemId),
                    responseType: Res.self
                )
                appliedIds.insert(prompt.id)
            } catch { self.error = error.localizedDescription }

        case .generateNote(let ids, let itemId):
            struct Body: Encodable {
                let promptId: String; let textFileIds: [String]; let itemId: String
                enum CodingKeys: String, CodingKey { case promptId = "prompt_id"; case textFileIds = "text_file_ids"; case itemId = "item_id" }
            }
            struct Res: Decodable { let success: Bool; let taskId: String?; enum CodingKeys: String, CodingKey { case success; case taskId = "task_id" } }
            do {
                let _ = try await APIClient.shared.request(
                    path: "/api/notes/generate",
                    method: "POST",
                    body: Body(promptId: prompt.id, textFileIds: ids, itemId: itemId),
                    responseType: Res.self
                )
                appliedIds.insert(prompt.id)
            } catch { self.error = error.localizedDescription }

        case .browse:
            appliedIds.insert(prompt.id)
        }
    }
}

struct PromptCard: View {
    let prompt: Prompt
    var isApplied: Bool
    var isApplying: Bool
    var onUse: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(prompt.name)
                        .font(.inter(14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textQuaternary)
                }

                Text(prompt.description)
                    .font(.inter(12))
                    .foregroundColor(.textTertiary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    ForEach(prompt.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.inter(10, weight: .bold))
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Button(action: onUse) {
                        HStack(spacing: 4) {
                            if isApplied {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                            }
                            Text(isApplied ? "Applied" : "Use →")
                        }
                        .font(.inter(11, weight: .bold))
                        .foregroundColor(isApplied ? .stageNotes : .brandCyan)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background((isApplied ? Color.stageNotes : Color.brandBlue).opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .disabled(isApplying)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
