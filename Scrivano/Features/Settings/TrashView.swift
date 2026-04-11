import SwiftUI

struct TrashView: View {
    @Environment(\.dismiss) var dismiss
    @State private var entries: [TrashEntry] = []
    @State private var showEmptyConfirm = false
    @State private var restoredId: String? = nil

    // Resolution flow
    @State private var resolution: Resolution? = nil

    enum Resolution {
        /// Item whose collection is missing
        case collectionMissing(
            entry: TrashEntry,
            item: LocalStoredItem,
            collectionName: String,
            trashedCollection: TrashEntry?   // non-nil if collection is also in trash
        )
        /// Transcript or note whose parent item is missing
        case itemMissing(
            entry: TrashEntry,
            parentItemName: String,
            trashedItem: TrashEntry?          // non-nil if item is also in trash
        )
    }

    private var grouped: [(TrashKind, [TrashEntry])] {
        let order: [TrashKind] = [.collection, .item, .transcript, .note, .recording]
        return order.compactMap { kind in
            let group = entries.filter { $0.kind == kind }.sorted { $0.deletedAt > $1.deletedAt }
            return group.isEmpty ? nil : (kind, group)
        }
    }

    var body: some View {
        ZStack {
            Color.phoneBg.ignoresSafeArea()

            VStack(spacing: 0) {
                SubScreenBar(
                    title: "Recycle Bin",
                    accentColor: .danger,
                    onBack: { dismiss() },
                    trailingIcon: entries.isEmpty ? nil : "🗑",
                    onTrailing: entries.isEmpty ? nil : { showEmptyConfirm = true }
                )

                if entries.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(grouped, id: \.0) { kind, group in
                                sectionHeader(kind)
                                VStack(spacing: 0) {
                                    ForEach(group) { entry in
                                        trashRow(entry)
                                        if entry.id != group.last?.id {
                                            Divider()
                                                .background(Color.white.opacity(0.05))
                                                .padding(.leading, 64)
                                        }
                                    }
                                }
                                .background(Color.white.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 14)
                                .padding(.bottom, 4)
                            }
                            Spacer().frame(height: 40)
                        }
                    }
                }
            }

            // Resolution card — missing collection or item
            if let res = resolution {
                Color.black.opacity(0.65).ignoresSafeArea().zIndex(10)
                VStack {
                    Spacer()
                    resolutionCard(res)
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(11)
            }

            // Empty Trash confirm card
            if showEmptyConfirm {
                Color.black.opacity(0.65).ignoresSafeArea().zIndex(10)
                VStack {
                    Spacer()
                    emptyConfirmCard
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(11)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showEmptyConfirm)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: resolution == nil)
        .navigationBarHidden(true)
        .onAppear { reload() }
    }

    // MARK: - Resolution card

    @ViewBuilder
    private func resolutionCard(_ res: Resolution) -> some View {
        switch res {
        case .collectionMissing(let entry, let item, let collectionName, let trashedCollection):
            VStack(spacing: 16) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 30))
                    .foregroundColor(.brandCyan)
                    .shadow(color: Color.brandCyan.opacity(0.5), radius: 10)

                Text("Collection Missing")
                    .font(.inter(16, weight: .heavy))
                    .foregroundColor(.textPrimary)

                Text("\"\(item.name)\" belonged to the \"\(collectionName)\" collection, which no longer exists.")
                    .font(.inter(13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    // Option 1: restore collection too (if it's in trash)
                    if let trashedCol = trashedCollection {
                        Button {
                            TrashStore.shared.restore(trashedCol)   // restore collection first
                            let col = try? JSONDecoder().decode(ScrivanoCollection.self, from: trashedCol.payload)
                            TrashStore.shared.restoreItem(entry, toCollectionId: col?.id, collectionName: col?.name)
                            if let item = decode(LocalStoredItem.self, from: entry.payload) { restoreDependents(of: item) }
                            finishRestore(entry)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 13, weight: .semibold))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Restore Collection Too")
                                        .font(.inter(14, weight: .bold))
                                    Text("Brings back \"\(collectionName)\" and the item")
                                        .font(.inter(11))
                                        .opacity(0.7)
                                }
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color.brandBlue.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    // Option 2: move to My Collection
                    Button {
                        TrashStore.shared.restoreItem(entry, toCollectionId: nil, collectionName: nil)
                        if let item = decode(LocalStoredItem.self, from: entry.payload) { restoreDependents(of: item) }
                        finishRestore(entry)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 13, weight: .semibold))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Move to My Collection")
                                    .font(.inter(14, weight: .bold))
                                Text("Restore item without a collection")
                                    .font(.inter(11))
                                    .opacity(0.7)
                            }
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    // Cancel
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { resolution = nil }
                    } label: {
                        Text("Cancel")
                            .font(.inter(14, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color(hex: "#081221"))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.brandBlue.opacity(0.3), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.4), radius: 20)

        case .itemMissing(let entry, let parentItemName, let trashedItem):
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.questionmark")
                    .font(.system(size: 30))
                    .foregroundColor(kindColor(entry.kind))
                    .shadow(color: kindColor(entry.kind).opacity(0.5), radius: 10)

                Text("Item Missing")
                    .font(.inter(16, weight: .heavy))
                    .foregroundColor(.textPrimary)

                Text("This \(entry.kind == .transcript ? "text" : "note") belonged to \"\(parentItemName)\", which no longer exists.")
                    .font(.inter(13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    // Option 1: restore parent item too (if it's in trash)
                    if let trashedItem = trashedItem {
                        Button {
                            // Restore parent item — cascade automatically restores all its transcripts/notes
                            tryRestore(trashedItem)
                            finishRestore(entry)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 13, weight: .semibold))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Restore Item Too")
                                        .font(.inter(14, weight: .bold))
                                    Text("Brings back \"\(parentItemName)\" and this content")
                                        .font(.inter(11))
                                        .opacity(0.7)
                                }
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(kindColor(entry.kind).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    } else {
                        // No parent item in trash — can't restore usefully
                        Text("The item \"\(parentItemName)\" was permanently deleted and cannot be recovered. You need to restore or recreate the item first.")
                            .font(.inter(12))
                            .foregroundColor(.textQuaternary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }

                    // Cancel
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { resolution = nil }
                    } label: {
                        Text("Cancel")
                            .font(.inter(14, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color(hex: "#081221"))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(kindColor(entry.kind).opacity(0.3), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.4), radius: 20)
        }
    }

    // MARK: - Empty confirm card

    private var emptyConfirmCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash.slash.fill")
                .font(.system(size: 30))
                .foregroundColor(.danger)
                .shadow(color: Color.danger.opacity(0.7), radius: 10)

            Text("Empty Recycle Bin")
                .font(.inter(16, weight: .heavy))
                .foregroundColor(.textPrimary)

            Text("This will permanently delete all \(entries.count) item\(entries.count == 1 ? "" : "s"). This cannot be undone.")
                .font(.inter(13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showEmptyConfirm = false }
                } label: {
                    Text("Cancel")
                        .font(.inter(14, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showEmptyConfirm = false }
                    TrashStore.shared.empty()
                    reload()
                } label: {
                    Text("Empty All")
                        .font(.inter(14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.danger.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(24)
        .background(Color(hex: "#081221"))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.danger.opacity(0.35), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color.danger.opacity(0.15), radius: 20)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.danger.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "trash")
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(.danger.opacity(0.5))
            }
            Text("Recycle Bin is Empty")
                .font(.inter(16, weight: .heavy))
                .foregroundColor(.textSecondary)
            Text("Deleted collections, items, texts and notes\nwill appear here for recovery.")
                .font(.inter(13))
                .foregroundColor(.textQuaternary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ kind: TrashKind) -> some View {
        HStack(spacing: 6) {
            Image(systemName: kindIcon(kind))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(kindColor(kind))
            Text(kindLabel(kind))
                .font(.inter(10, weight: .heavy))
                .foregroundColor(.textQuaternary)
                .tracking(0.7)
                .textCase(.uppercase)
            Spacer()
            Text("\(entries.filter { $0.kind == kind }.count)")
                .font(.inter(10, weight: .heavy))
                .foregroundColor(.textQuaternary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    // MARK: - Trash row

    @ViewBuilder
    private func trashRow(_ entry: TrashEntry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(kindColor(entry.kind).opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: kindIcon(entry.kind))
                        .font(.system(size: 16))
                        .foregroundColor(kindColor(entry.kind))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.inter(14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if let parent = entry.parentName {
                        Text(parent)
                            .font(.inter(11))
                            .foregroundColor(.textQuaternary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(relativeDate(entry.deletedAt))
                    .font(.inter(10))
                    .foregroundColor(.textQuaternary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 8) {
                Button {
                    tryRestore(entry)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: restoredId == entry.id ? "checkmark" : "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .bold))
                        Text(restoredId == entry.id ? "Restored!" : "Restore")
                            .font(.inter(12, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "#34d399"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#34d399").opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "#34d399").opacity(0.3), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }

                Button {
                    TrashStore.shared.permanentlyDelete(entry.id)
                    reload()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .bold))
                        Text("Delete")
                            .font(.inter(12, weight: .bold))
                    }
                    .foregroundColor(.danger)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(Color.danger.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.danger.opacity(0.25), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Restore logic with dependency check

    private func tryRestore(_ entry: TrashEntry) {
        switch entry.kind {

        case .collection:
            commit(entry)

        case .item:
            guard let item = decode(LocalStoredItem.self, from: entry.payload) else { return }
            guard let colId = item.collectionId else {
                // No collection — safe to restore as-is
                commit(entry); return
            }
            if LocalCollectionStore.shared.all().contains(where: { $0.id == colId }) {
                commit(entry)   // Collection still exists ✓
            } else {
                // Collection is gone — find it in trash or offer My Collection
                let trashedCol = entries.first {
                    $0.kind == .collection &&
                    (decode(ScrivanoCollection.self, from: $0.payload)?.id == colId) == true
                }
                let colName: String = {
                    if let col = trashedCol.flatMap({ decode(ScrivanoCollection.self, from: $0.payload) }) {
                        return col.name
                    }
                    return item.collection ?? "Unknown Collection"
                }()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    resolution = .collectionMissing(
                        entry: entry, item: item,
                        collectionName: colName,
                        trashedCollection: trashedCol
                    )
                }
            }

        case .transcript:
            guard let t = decode(LocalTranscriptEntry.self, from: entry.payload) else { return }
            if LocalItemStore.shared.all().contains(where: { $0.id == t.itemId }) {
                commit(entry)   // Parent item still exists ✓
            } else {
                let trashedItem = entries.first {
                    $0.kind == .item &&
                    (decode(LocalStoredItem.self, from: $0.payload)?.id == t.itemId) == true
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    resolution = .itemMissing(
                        entry: entry,
                        parentItemName: entry.parentName ?? "Unknown Item",
                        trashedItem: trashedItem
                    )
                }
            }

        case .note:
            guard let n = decode(LocalNoteEntry.self, from: entry.payload) else { return }
            if LocalItemStore.shared.all().contains(where: { $0.id == n.itemId }) {
                commit(entry)   // Parent item still exists ✓
            } else {
                let trashedItem = entries.first {
                    $0.kind == .item &&
                    (decode(LocalStoredItem.self, from: $0.payload)?.id == n.itemId) == true
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    resolution = .itemMissing(
                        entry: entry,
                        parentItemName: entry.parentName ?? "Unknown Item",
                        trashedItem: trashedItem
                    )
                }
            }

        case .recording:
            guard let rec = decode(LocalRecordingEntry.self, from: entry.payload) else { return }
            guard FileManager.default.fileExists(atPath: rec.fileURL.path) else {
                // File is gone — permanently remove the trash entry
                TrashStore.shared.permanentlyDelete(entry.id)
                reload()
                return
            }
            if LocalItemStore.shared.all().contains(where: { $0.id == rec.itemId }) {
                commit(entry)   // Parent item still exists ✓
            } else {
                let trashedItem = entries.first {
                    $0.kind == .item &&
                    (decode(LocalStoredItem.self, from: $0.payload)?.id == rec.itemId) == true
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    resolution = .itemMissing(
                        entry: entry,
                        parentItemName: entry.parentName ?? "Unknown Item",
                        trashedItem: trashedItem
                    )
                }
            }
        }
    }

    private func commit(_ entry: TrashEntry) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { resolution = nil }
        TrashStore.shared.restore(entry)
        if entry.kind == .item, let item = decode(LocalStoredItem.self, from: entry.payload) {
            restoreDependents(of: item)
        }
        restoredId = entry.id
        reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { restoredId = nil }
    }

    private func finishRestore(_ entry: TrashEntry) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { resolution = nil }
        restoredId = entry.id
        reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { restoredId = nil }
    }

    /// Auto-restores all trashed transcripts, notes and recordings that belong to `item`.
    private func restoreDependents(of item: LocalStoredItem) {
        let dependents = TrashStore.shared.entries.filter { dep in
            switch dep.kind {
            case .transcript:
                return decode(LocalTranscriptEntry.self, from: dep.payload)?.itemId == item.id
            case .note:
                return decode(LocalNoteEntry.self, from: dep.payload)?.itemId == item.id
            case .recording:
                return decode(LocalRecordingEntry.self, from: dep.payload)?.itemId == item.id
            default:
                return false
            }
        }
        for dep in dependents { TrashStore.shared.restore(dep) }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Helpers

    private func reload() {
        entries = TrashStore.shared.entries
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        if diff < 604800 { return "\(Int(diff / 86400))d ago" }
        let f = DateFormatter(); f.dateStyle = .short
        return f.string(from: date)
    }

    private func kindLabel(_ kind: TrashKind) -> String {
        switch kind {
        case .collection: return "Collections"
        case .item:       return "Items"
        case .transcript: return "Texts"
        case .note:       return "Notes"
        case .recording:  return "Audio Files"
        }
    }

    private func kindIcon(_ kind: TrashKind) -> String {
        switch kind {
        case .collection: return "folder"
        case .item:       return "doc.text"
        case .transcript: return "text.alignleft"
        case .note:       return "note.text"
        case .recording:  return "waveform"
        }
    }

    private func kindColor(_ kind: TrashKind) -> Color {
        switch kind {
        case .collection: return .brandCyan
        case .item:       return Color(hex: "#a78bfa")
        case .transcript: return .stageText
        case .note:       return .stageNotes
        case .recording:  return .stageMedia
        }
    }
}

extension TrashView.Resolution: Equatable {
    static func == (lhs: TrashView.Resolution, rhs: TrashView.Resolution) -> Bool {
        switch (lhs, rhs) {
        case (.collectionMissing(let a, _, _, _), .collectionMissing(let b, _, _, _)): return a.id == b.id
        case (.itemMissing(let a, _, _), .itemMissing(let b, _, _)): return a.id == b.id
        default: return false
        }
    }
}
