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
    @EnvironmentObject private var navigator: Navigator
    @State private var selectedID: SkillHandle.ID?
    @State private var searchText: String = ""
    @State private var showNewSkillSheet = false

    var body: some View {
        HSplitView {
            SkillListView(
                handles: filteredHandles,
                selected: $selectedID,
                searchText: $searchText,
                totalCount: store.handles.count,
                isLoading: store.isLoading,
                error: store.loadError,
                onNewSkill: { showNewSkillSheet = true },
                onRefresh: { Task { await store.reload() } }
            )
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)

            Group {
                if let handle = selectedHandle {
                    SkillEditorView(store: store, handle: handle)
                        .id(handle.id)
                } else {
                    EmptyDetailView()
                }
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
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
