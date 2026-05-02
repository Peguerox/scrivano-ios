import SwiftUI

// MARK: - App Group
private let kGroupID = "group.com.scrivano.ScrivanoRecorder"

// MARK: - Shared models (must match main app's Codable structs)
private struct SCollection: Codable, Identifiable { let id: String; let name: String }
private struct SItem: Codable, Identifiable {
    let id: String; var name: String
    var collection: String?; var collectionId: String?; var createdAt: String?
}
private struct PendingEntry: Codable {
    let id, fileRelativePath, fileExtension: String
    let isAudio: Bool
    let collectionId, collectionName, itemId, itemName: String
    let importedAt: Date
}

// MARK: - State
private enum ImportState { case idle, loading, success, error(String) }

// MARK: - Colors
private struct SC {
    static let appBg  = Color(r: 3,   g: 8,   b: 15)
    static let card   = Color(r: 8,   g: 18,  b: 33)
    static let cyan   = Color(r: 56,  g: 217, b: 245)
    static let yellow = Color(r: 234, g: 179, b: 8)
    static let pink   = Color(r: 236, g: 72,  b: 153)
    static let green  = Color(r: 34,  g: 197, b: 94)
    static let red    = Color(r: 239, g: 68,  b: 68)
}
private extension Color {
    init(r: Double, g: Double, b: Double) { self.init(red: r/255, green: g/255, blue: b/255) }
}

// MARK: - ShareView
struct ShareView: View {
    let fileURL: URL
    let isAudio: Bool
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var collections: [SCollection] = []
    @State private var allItems: [SItem] = []
    @State private var selectedCollection: SCollection?
    @State private var selectedItem: SItem?
    @State private var state: ImportState = .idle

    private var isLoggedIn: Bool {
        UserDefaults(suiteName: kGroupID)?.bool(forKey: "scrivano.isLoggedIn") ?? false
    }
    private var filteredItems: [SItem] {
        guard let col = selectedCollection else { return [] }
        return allItems.filter { $0.collectionId == col.id }
    }

    var body: some View {
        ZStack {
            SC.appBg.ignoresSafeArea()
            if !isLoggedIn {
                notLoggedIn
            } else {
                switch state {
                case .loading: loadingView
                case .success: successView
                default:       mainContent
                }
            }
        }
        .onAppear(perform: loadData)
    }

    // MARK: Not logged in
    private var notLoggedIn: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.circle").font(.system(size: 48)).foregroundColor(SC.cyan)
            Text("Please open Scrivano and sign in, then try again.")
                .foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button("Cancel", action: onCancel).foregroundColor(SC.cyan)
        }
    }

    // MARK: Main content
    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShareHeader(onCancel: onCancel)
                FileInfoCard(fileURL: fileURL, isAudio: isAudio)
                Spacer().frame(height: 10)

                SectionLabel("Collection")
                CollectionPicker(
                    collections: collections,
                    selected: selectedCollection,
                    onSelect: { col in selectedCollection = col; selectedItem = nil },
                    onCreate: { name in
                        let col = SCollection(id: UUID().uuidString, name: name)
                        collections.append(col); selectedCollection = col; selectedItem = nil
                    }
                )

                if selectedCollection != nil {
                    Spacer().frame(height: 10)
                    SectionLabel("Item")
                    ItemPicker(
                        items: filteredItems,
                        selected: selectedItem,
                        onSelect: { selectedItem = $0 },
                        onCreate: { name in
                            guard let col = selectedCollection else { return }
                            let item = SItem(id: UUID().uuidString, name: name,
                                            collection: col.name, collectionId: col.id, createdAt: nil)
                            allItems.append(item); selectedItem = item
                        }
                    )
                }

                if case .error(let msg) = state {
                    Text(msg).foregroundColor(SC.red).font(.system(size: 12))
                        .padding(.horizontal, 18).padding(.top, 12)
                }

                Spacer().frame(height: 24)

                let canImport = selectedCollection != nil && selectedItem != nil
                Button { if canImport { doImport() } } label: {
                    Text("Import").font(.system(size: 15, weight: .bold))
                        .foregroundColor(canImport ? .white : .white.opacity(0.4))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(SC.yellow.opacity(canImport ? 1 : 0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canImport).padding(.horizontal, 18)

                Spacer().frame(height: 32)
            }
        }
    }

    // MARK: Loading / Success
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().progressViewStyle(.circular).tint(SC.yellow).scaleEffect(1.2)
            Text("Importing…").foregroundColor(.white).font(.system(size: 14, weight: .semibold))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var successView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(SC.green.opacity(0.2)).frame(width: 56, height: 56)
                    .overlay(Circle().stroke(SC.green.opacity(0.4), lineWidth: 1))
                Image(systemName: "checkmark").foregroundColor(SC.green).font(.system(size: 20, weight: .bold))
            }
            Text("Imported!").foregroundColor(.white).font(.system(size: 16, weight: .bold))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Data
    private func loadData() {
        let ud = UserDefaults(suiteName: kGroupID)
        if let d = ud?.data(forKey: "scrivano.collections"),
           let c = try? JSONDecoder().decode([SCollection].self, from: d) { collections = c }
        if let d = ud?.data(forKey: "scrivano.items"),
           let i = try? JSONDecoder().decode([SItem].self, from: d) { allItems = i }
    }

    // MARK: Import
    private func doImport() {
        guard let col = selectedCollection, let item = selectedItem else { return }
        state = .loading
        Task {
            let ok = save(fileURL: fileURL, isAudio: isAudio, col: col, item: item)
            await MainActor.run {
                if ok {
                    state = .success
                    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); onDone() }
                } else {
                    state = .error("Failed to save file. Please try again.")
                }
            }
        }
    }

    private func save(fileURL: URL, isAudio: Bool, col: SCollection, item: SItem) -> Bool {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: kGroupID) else { return false }
        let dir = container.appendingPathComponent("pending_imports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let importId = UUID().uuidString
        let ext = fileURL.pathExtension.isEmpty ? (isAudio ? "m4a" : "pdf") : fileURL.pathExtension
        let filename = "\(importId).\(ext)"
        let dest = dir.appendingPathComponent(filename)
        guard (try? FileManager.default.copyItem(at: fileURL, to: dest)) != nil else { return false }

        let entry = PendingEntry(id: importId, fileRelativePath: "pending_imports/\(filename)",
                                 fileExtension: ext, isAudio: isAudio,
                                 collectionId: col.id, collectionName: col.name,
                                 itemId: item.id, itemName: item.name, importedAt: Date())

        let manifestURL = dir.appendingPathComponent("manifest.json")
        var entries: [PendingEntry] = []
        if let d = try? Data(contentsOf: manifestURL),
           let ex = try? JSONDecoder().decode([PendingEntry].self, from: d) { entries = ex }
        entries.append(entry)
        guard let data = try? JSONEncoder().encode(entries) else { return false }
        try? data.write(to: manifestURL, options: .atomic)
        return true
    }
}

// MARK: - Header
private struct ShareHeader: View {
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.07)).frame(width: 36, height: 36)
                        Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.55))
                    }
                }
                Text("Import File").font(.system(size: 16, weight: .heavy)).foregroundColor(.white).padding(.leading, 12)
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }
}

// MARK: - FileInfoCard
private struct FileInfoCard: View {
    let fileURL: URL; let isAudio: Bool
    private var ext: String { fileURL.pathExtension.lowercased() }
    private var icon: String { isAudio ? "mic.fill" : (ext == "pdf" ? "doc.fill" : "doc.text.fill") }
    private var color: Color { isAudio ? SC.pink : (ext == "pdf" ? SC.red : SC.cyan) }
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25), lineWidth: 1))
                    .frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
            }
            Text(fileURL.lastPathComponent)
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14).background(SC.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.20), lineWidth: 1))
        .padding(.horizontal, 18).padding(.vertical, 14)
    }
}

// MARK: - SectionLabel
private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .heavy))
            .foregroundColor(.white.opacity(0.35)).kerning(1)
            .padding(.horizontal, 18).padding(.vertical, 6)
    }
}

// MARK: - CollectionPicker
private struct CollectionPicker: View {
    let collections: [SCollection]; let selected: SCollection?
    let onSelect: (SCollection) -> Void; let onCreate: (String) -> Void
    @State private var showNew = false; @State private var newName = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(collections.enumerated()), id: \.element.id) { idx, col in
                PickerRow(label: col.name, isSelected: col.id == selected?.id) { onSelect(col); showNew = false }
                if idx < collections.count - 1 || showNew { Divider().background(Color.white.opacity(0.05)) }
            }
            if showNew {
                NewNameRow(value: $newName, placeholder: "Collection name…", isFocused: $focused,
                           onConfirm: {
                    let t = newName.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { onCreate(t); newName = ""; showNew = false }
                }, onCancel: { showNew = false; newName = "" })
                .onAppear { focused = true }
            } else {
                if !collections.isEmpty { Divider().background(Color.white.opacity(0.05)) }
                NewRow(label: "New Collection…") { showNew = true }
            }
        }
        .background(SC.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .padding(.horizontal, 18)
    }
}

// MARK: - ItemPicker
private struct ItemPicker: View {
    let items: [SItem]; let selected: SItem?
    let onSelect: (SItem) -> Void; let onCreate: (String) -> Void
    @State private var showNew = false; @State private var newName = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty && !showNew {
                Text("No items yet — create one below")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 16).padding(.vertical, 14)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                PickerRow(label: item.name, isSelected: item.id == selected?.id) { onSelect(item); showNew = false }
                if idx < items.count - 1 || showNew { Divider().background(Color.white.opacity(0.05)) }
            }
            if showNew {
                NewNameRow(value: $newName, placeholder: "Item name…", isFocused: $focused,
                           onConfirm: {
                    let t = newName.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { onCreate(t); newName = ""; showNew = false }
                }, onCancel: { showNew = false; newName = "" })
                .onAppear { focused = true }
            } else {
                if !items.isEmpty { Divider().background(Color.white.opacity(0.05)) }
                NewRow(label: "New Item…") { showNew = true }
            }
        }
        .background(SC.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .padding(.horizontal, 18)
    }
}

// MARK: - PickerRow
private struct PickerRow: View {
    let label: String; let isSelected: Bool; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? SC.yellow : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundColor(SC.yellow) }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }
}

// MARK: - NewRow
private struct NewRow: View {
    let label: String; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 13)).foregroundColor(SC.cyan)
                Text(label).font(.system(size: 14)).foregroundColor(SC.cyan)
                Spacer()
            }.padding(.horizontal, 16).padding(.vertical, 14)
        }
    }
}

// MARK: - NewNameRow
private struct NewNameRow: View {
    @Binding var value: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    let onConfirm: () -> Void; let onCancel: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
                if value.isEmpty { Text(placeholder).foregroundColor(.white.opacity(0.30)).font(.system(size: 14)).padding(.horizontal, 10) }
                TextField("", text: $value).foregroundColor(.white).font(.system(size: 14))
                    .tint(SC.cyan).focused(isFocused).padding(.horizontal, 10).onSubmit { onConfirm() }
            }.frame(height: 36)
            Button { onConfirm() } label: {
                ZStack {
                    Circle().fill(value.isEmpty ? Color.white.opacity(0.05) : SC.cyan.opacity(0.2)).frame(width: 32, height: 32)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                        .foregroundColor(value.isEmpty ? .white.opacity(0.25) : SC.cyan)
                }
            }.disabled(value.isEmpty)
            Button { onCancel() } label: {
                ZStack {
                    Circle().fill(Color.white.opacity(0.05)).frame(width: 32, height: 32)
                    Image(systemName: "xmark").font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                }
            }
        }.padding(.horizontal, 12).padding(.vertical, 8)
    }
}
