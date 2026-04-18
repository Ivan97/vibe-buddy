import SwiftUI

struct SubagentsRoot: View {
    @EnvironmentObject private var store: AgentStore

    var body: some View {
        SubagentsShell(store: store)
            .task {
                if store.handles.isEmpty {
                    await store.reload()
                }
                store.startWatching()
            }
    }
}

private struct SubagentsShell: View {
    @ObservedObject var store: AgentStore
    @EnvironmentObject private var navigator: Navigator
    @State private var selectedID: AgentHandle.ID?
    @State private var searchText: String = ""
    @State private var showNewAgentSheet = false

    var body: some View {
        HSplitView {
            AgentListView(
                handles: filteredHandles,
                selected: $selectedID,
                searchText: $searchText,
                totalCount: store.handles.count,
                isLoading: store.isLoading,
                error: store.loadError,
                onNewAgent: { showNewAgentSheet = true },
                onRefresh: { Task { await store.reload() } }
            )
            .frame(minWidth: 260, idealWidth: 400)

            Group {
                if let handle = selectedHandle {
                    // No .id — see SessionListView note: forcing fresh
                    // identity resets HSplitView's divider on every pick.
                    AgentEditorView(store: store, handle: handle)
                } else {
                    EmptyDetailView()
                }
            }
            .frame(minWidth: 400, maxHeight: .infinity)
        }
        .sheet(isPresented: $showNewAgentSheet) {
            NewAgentSheet(store: store) { handle in
                selectedID = handle.id
                showNewAgentSheet = false
            }
        }
        .onAppear(perform: consumePendingOpen)
        .onChange(of: navigator.pendingAgentID) { _, _ in consumePendingOpen() }
        .onChange(of: store.handles) { _, _ in consumePendingOpen() }
    }

    private func consumePendingOpen() {
        guard let id = navigator.pendingAgentID else { return }
        if store.handles.contains(where: { $0.id == id }) {
            selectedID = id
            navigator.pendingAgentID = nil
        }
    }

    private var filteredHandles: [AgentHandle] {
        guard !searchText.isEmpty else { return store.handles }
        let q = searchText.lowercased()
        return store.handles.filter {
            $0.name.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
        }
    }

    private var selectedHandle: AgentHandle? {
        guard let id = selectedID else { return nil }
        return store.handles.first { $0.id == id }
    }
}

private struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select an agent")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
