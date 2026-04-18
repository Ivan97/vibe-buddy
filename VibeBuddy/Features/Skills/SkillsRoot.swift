import SwiftUI

struct SkillsRoot: View {
    @EnvironmentObject private var store: SkillStore

    var body: some View {
        SkillsShell(store: store)
            .task {
                if store.handles.isEmpty {
                    await store.reload()
                }
                store.startWatching()
            }
    }
}

private struct SkillsShell: View {
    @ObservedObject var store: SkillStore
    @EnvironmentObject private var pluginsStore: PluginsStore
    @EnvironmentObject private var navigator: Navigator
    @State private var selectedID: SkillHandle.ID?
    @State private var searchText: String = ""
    @State private var showNewSkillSheet = false

    /// Resolve a handle's update status against the right store:
    /// plugin-scope piggy-backs on `PluginsStore`, userSymlink checks
    /// live in `SkillStore`, everything else reports nothing.
    private func status(for handle: SkillHandle) -> GitUpdateChecker.Status {
        switch handle.scope {
        case .userSymlink:
            return store.status(for: handle.id)
        case .plugin:
            guard let pluginID = handle.pluginID else { return .unchecked }
            return pluginsStore.status(for: pluginID)
        case .user, .malformed:
            return .unchecked
        }
    }

    /// "Check updates" in Skills fans out to both stores so plugin-scope
    /// badges light up alongside symlinked ones.
    private func checkAllUpdates() {
        Task {
            async let skills: Void = store.checkAllForUpdates()
            async let plugins: Void = pluginsStore.checkAllForUpdates()
            _ = await (skills, plugins)
        }
    }

    var body: some View {
        HSplitView {
            SkillListView(
                handles: filteredHandles,
                selected: $selectedID,
                searchText: $searchText,
                totalCount: store.handles.count,
                isLoading: store.isLoading,
                isCheckingUpdates: store.isCheckingUpdates || pluginsStore.isCheckingUpdates,
                updateStatus: status,
                error: store.loadError,
                onNewSkill: { showNewSkillSheet = true },
                onRefresh: { Task { await store.reload() } },
                onCheckUpdates: checkAllUpdates
            )
            .frame(minWidth: 280, idealWidth: 400)

            Group {
                if let handle = selectedHandle {
                    // No .id(handle.id) — that would give HSplitView a
                    // fresh child on every selection change and reset the
                    // divider. Editor observes handle.id internally.
                    SkillEditorView(store: store, handle: handle)
                } else {
                    EmptyDetailView()
                }
            }
            .frame(minWidth: 400, maxHeight: .infinity)
        }
        .sheet(isPresented: $showNewSkillSheet) {
            NewSkillSheet(store: store) { handle in
                selectedID = handle.id
                showNewSkillSheet = false
            }
        }
        .onAppear(perform: consumePendingOpen)
        .onChange(of: navigator.pendingSkillID) { _, _ in consumePendingOpen() }
        .onChange(of: store.handles) { _, _ in consumePendingOpen() }
    }

    private func consumePendingOpen() {
        guard let id = navigator.pendingSkillID else { return }
        if store.handles.contains(where: { $0.id == id }) {
            selectedID = id
            navigator.pendingSkillID = nil
        }
    }

    private var filteredHandles: [SkillHandle] {
        guard !searchText.isEmpty else { return store.handles }
        let q = searchText.lowercased()
        return store.handles.filter {
            $0.name.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
        }
    }

    private var selectedHandle: SkillHandle? {
        guard let id = selectedID else { return nil }
        return store.handles.first { $0.id == id }
    }
}

private struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a skill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
