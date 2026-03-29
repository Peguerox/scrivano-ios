import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = DashboardViewModel()
    @State private var showSettings = false
    @State private var showCollections = false
    @State private var showDotsMenu = false
    @State private var showNewItem = false
    @State private var selectedItem: Item? = nil
    @State private var itemMenuTarget: Item? = nil
    @State private var showItemMenu = false
    @State private var viewMode: ViewMode = .card

    enum ViewMode { case card, list }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.phoneBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar
                    dashBar

                    // Action row
                    actionRow

                    // Sort row
                    sortRow

                    // Items list
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.items) { item in
                                ItemCardView(
                                    item: item,
                                    isSelected: selectedItem?.id == item.id,
                                    onTap: { selectedItem = item },
                                    onMenu: {
                                        itemMenuTarget = item
                                        showItemMenu = true
                                    },
                                    onStageTap: { stage in
                                        selectedItem = item
                                        vm.navigateTo(stage: stage, item: item)
                                    }
                                )
                            }
                            if vm.items.isEmpty && !vm.isLoading {
                                emptyState
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .padding(.bottom, 80)
                    }
                }

                // FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button { showNewItem = true } label: {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 58, height: 58)
                                    .shadow(color: Color.brandBlue.opacity(0.6), radius: 16, y: 6)
                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 28)
                    }
                }

                if vm.isLoading { LoadingOverlay() }
            }
            .navigationBarHidden(true)
            // Stage navigation
            .navigationDestination(isPresented: $vm.navigateToMedia) {
                if let item = vm.navigationItem {
                    MediaListView(item: item)
                }
            }
            .navigationDestination(isPresented: $vm.navigateToText) {
                if let item = vm.navigationItem {
                    TextListView(item: item)
                }
            }
            .navigationDestination(isPresented: $vm.navigateToNotes) {
                if let item = vm.navigationItem {
                    NotesListView(item: item)
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showCollections) { CollectionPickerView(vm: vm) }
        .sheet(isPresented: $showNewItem) { NewItemView(vm: vm) }
        .sheet(isPresented: $showItemMenu) {
            if let item = itemMenuTarget {
                ItemMenuView(item: item, vm: vm)
                    .presentationDetents([.medium])
            }
        }
        .confirmationDialog("Collection Actions", isPresented: $showDotsMenu, titleVisibility: .hidden) {
            Button("Transcribe Items") {}
            Button("Apply Prompts") {}
            Button("Prompt Database") {}
            Button("New Collection") { vm.createCollection() }
            Button("Rename Collection") {}
            Button("Delete Collection", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        }
        .task { await vm.load() }
    }

    // MARK: - Sub-views

    private var dashBar: some View {
        HStack {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color.white.opacity(0.6))
                    .frame(width: 36, height: 36)
            }

            Spacer()

            Button { showCollections = true } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.brandCyan)
                        .frame(width: 7, height: 7)
                    Text(vm.activeCollection?.name ?? "All Items")
                        .font(.inter(13, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .clipShape(Capsule())
            }

            Spacer()

            Button { showDotsMenu = true } label: {
                Text("···")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.6))
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button { showNewItem = true } label: {
                Text("＋ New Item")
                    .font(.inter(13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(LinearGradient(colors: [Color.brandBlue, Color.brandNavy], startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
                    .shadow(color: Color.brandBlue.opacity(0.4), radius: 8, y: 3)
            }
            Button("Clear Task") {}
                .font(.inter(13, weight: .semibold))
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.07))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .clipShape(Capsule())
            Button("Submit") {}
                .font(.inter(13, weight: .semibold))
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.07))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var sortRow: some View {
        HStack {
            Text("\(vm.items.count) items · A–Z ↑")
                .font(.inter(11, weight: .semibold))
                .foregroundColor(.textTertiary)

            Spacer()

            HStack(spacing: 8) {
                Button("⇅ Sort") {}
                    .font(.inter(11, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .clipShape(Capsule())

                HStack(spacing: 0) {
                    ForEach([ViewMode.card, .list], id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { viewMode = mode }
                        } label: {
                            Text(mode == .card ? "▤" : "≡")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(viewMode == mode ? .brandCyan : .textTertiary)
                                .frame(width: 28, height: 26)
                                .background(viewMode == mode ? Color.brandBlue.opacity(0.22) : .clear)
                        }
                    }
                }
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.textQuaternary)
            Text("No items yet")
                .font(.inter(16, weight: .bold))
                .foregroundColor(.textTertiary)
            Text("Tap ＋ New Item to create your first entry")
                .font(.inter(12))
                .foregroundColor(.textQuaternary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}

// MARK: - ViewModel
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var collections: [ScrivanoCollection] = []
    @Published var activeCollection: ScrivanoCollection?
    @Published var isLoading = false
    @Published var error: String?

    // Navigation
    @Published var navigateToMedia = false
    @Published var navigateToText = false
    @Published var navigateToNotes = false
    @Published var navigationItem: Item?

    enum Stage { case media, text, notes }

    let api = APIClient.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await loadCollections()
        await loadItems()
    }

    func loadItems() async {
        struct ItemsResponse: Decodable {
            let success: Bool
            let items: [Item]
        }
        do {
            let collId = activeCollection?.id
            let path = collId != nil ? "/api/items?collection_id=\(collId!)" : "/api/items"
            let res = try await api.request(path: path, responseType: ItemsResponse.self)
            if res.success { items = res.items }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadCollections() async {
        struct CollRes: Decodable {
            let success: Bool
            let collections: [ScrivanoCollection]
        }
        do {
            let res = try await api.request(path: "/api/collections", responseType: CollRes.self)
            if res.success { collections = res.collections }
        } catch {}
    }

    func navigateTo(stage: DashboardViewModel.Stage, item: Item) {
        navigationItem = item
        switch stage {
        case .media:  navigateToMedia = true
        case .text:   navigateToText = true
        case .notes:  navigateToNotes = true
        }
    }

    func createCollection() {}

    func selectCollection(_ c: ScrivanoCollection?) {
        activeCollection = c
        Task { await loadItems() }
    }
}
