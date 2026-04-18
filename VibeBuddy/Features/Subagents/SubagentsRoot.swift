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
            .frame(minWidth: 260, idealWidth: 320, maxWidth: 400)

            Group {
                if let handle = selectedHandle {
                    AgentEditorView(store: store, handle: handle)
                        .id(handle.id)
                } else {
                    EmptyDetailView()
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showNewAgentSheet) {
            NewAgentSheet(store: store) { handle in
                selectedID = handle.id
                showNewAgentSheet = false
            }
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
