import SwiftUI

struct ItemCardView: View {
    let item: Item
    var isSelected: Bool
    var onTap: () -> Void
    var onMenu: () -> Void
    var onStageTap: (DashboardViewModel.Stage) -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // Header row
                HStack(alignment: .center) {
                    Text(item.name)
                        .font(.inter(14, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text("·")
                        .foregroundColor(.textQuaternary)
                    Text(relativeTime(from: item.updatedAt))
                        .font(.inter(11))
                        .foregroundColor(.textQuaternary)
                    Spacer()
                    Button(action: onMenu) {
                        Text("···")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }

                // Pipeline
                HStack(spacing: 0) {
                    stageButton(.media, label: "Media", count: item.mediaCount)
                    connector(filled: item.mediaCount > 0 && item.textCount > 0)
                    stageButton(.text, label: "Text", count: item.textCount)
                    connector(filled: item.textCount > 0 && item.noteCount > 0)
                    stageButton(.notes, label: "Notes", count: item.noteCount)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? Color.brandBlue.opacity(0.08)
                    : Color.white.opacity(0.035)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.brandCyan.opacity(0.3) : Color.white.opacity(0.07),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
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
                    .font(.inter(10, weight: .bold))
                    .foregroundColor(isFilled ? color : Color.white.opacity(0.3))
                Text(isFilled ? "\(count)" : "—")
                    .font(.inter(13, weight: .heavy))
                    .foregroundColor(isFilled ? color : Color.white.opacity(0.2))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isFilled
                    ? color.opacity(0.12)
                    : Color.white.opacity(0.04)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isFilled ? color.opacity(0.35) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func connector(filled: Bool) -> some View {
        Rectangle()
            .fill(
                filled
                    ? LinearGradient(colors: [Color.brandBlue.opacity(0.6), Color.brandCyan.opacity(0.4)], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
            )
            .frame(width: 16, height: 2)
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

// MARK: - Collection Picker Sheet
struct CollectionPickerView: View {
    @ObservedObject var vm: DashboardViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selected = Set<String>()

    var body: some View {
        ZStack {
            Color.sheetBg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Collections")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    if !selected.isEmpty {
                        Button("🗑 Delete") {}
                            .font(.inter(12, weight: .semibold))
                            .foregroundColor(.danger)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.danger.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    Button("+ New") { vm.createCollection() }
                        .font(.inter(12, weight: .bold))
                        .foregroundColor(.brandCyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.brandBlue.opacity(0.15))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Divider().background(Color.white.opacity(0.07))

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // "All items" option
                        collRow(id: nil, name: "All Items", meta: "\(vm.items.count) items total", isActive: vm.activeCollection == nil)

                        ForEach(vm.collections) { c in
                            collRow(
                                id: c.id,
                                name: c.name,
                                meta: "\(c.itemCount) items · \(c.createdAt.prefix(10))",
                                isActive: vm.activeCollection?.id == c.id
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func collRow(id: String?, name: String, meta: String, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                selected.toggle(id ?? "__all")
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.brandBlue.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if selected.contains(id ?? "__all") {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(.brandBlue)
                    }
                }
            }

            Text("📁")
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.inter(14, weight: .semibold)).foregroundColor(.textPrimary)
                Text(meta + (isActive ? " · Active" : "")).font(.inter(11)).foregroundColor(.textTertiary)
            }
            Spacer()
            if isActive { Text("📌").font(.system(size: 14)) }
            Button {
                vm.selectCollection(vm.collections.first { $0.id == id })
                dismiss()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.brandCyan)
                    .frame(width: 28, height: 28)
                    .background(Color.brandBlue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(isActive ? Color.brandBlue.opacity(0.06) : .clear)
        .overlay(alignment: .bottom) { Divider().background(Color.white.opacity(0.05)) }
    }
}

extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) { remove(element) } else { insert(element) }
    }
}

// MARK: - New Item Sheet
struct NewItemView: View {
    @ObservedObject var vm: DashboardViewModel
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var loading = false

    var body: some View {
        ZStack {
            Color.sheetBg.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Text("New Item")
                        .font(.inter(16, weight: .heavy))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button(action: { dismiss() }) {
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

                ScrivanoTextField(label: "Name", text: $name, placeholder: "e.g. John Smith")
                    .padding(.horizontal, 24)

                Button {
                    Task {
                        loading = true
                        await vm.createItem(name: name)
                        loading = false
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if loading { ProgressView().tint(.white).scaleEffect(0.8) }
                        Text(loading ? "Creating…" : "Create Item")
                    }
                }
                .primaryButtonStyle()
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                .padding(.horizontal, 24)
                Spacer()
            }
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}

extension DashboardViewModel {
    func createItem(name: String) async {
        struct Body: Encodable {
            let name: String
            let collectionId: String?
            enum CodingKeys: String, CodingKey { case name; case collectionId = "collection_id" }
        }
        struct Res: Decodable { let success: Bool; let item: Item? }
        do {
            let res = try await api.request(
                path: "/api/items",
                method: "POST",
                body: Body(name: name, collectionId: activeCollection?.id),
                responseType: Res.self
            )
            if res.success, let item = res.item { items.insert(item, at: 0) }
        } catch { self.error = error.localizedDescription }
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
