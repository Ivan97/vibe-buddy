import SwiftUI

struct PromptsRoot: View {
    @EnvironmentObject private var store: CommandStore

    var body: some View {
        PromptsShell(store: store)
            .task {
                if store.handles.isEmpty {
                    await store.reload()
                }
                store.startWatching()
            }
    }
}

private struct PromptsShell: View {
    @ObservedObject var store: CommandStore
    @EnvironmentObject private var navigator: Navigator
    @State private var selectedID: CommandHandle.ID?
    @State private var searchText: String = ""
    @State private var showNewSheet = false

    var body: some View {
        HSplitView {
            CommandListView(
                handles: filtered,
                selected: $selectedID,
                searchText: $searchText,
                totalCount: store.handles.count,
                isLoading: store.isLoading,
                error: store.loadError,
                onNewCommand: { showNewSheet = true },
                onRefresh: { Task { await store.reload() } }
            )
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)

            Group {
                if let handle = selectedHandle {
                    CommandEditorView(store: store, handle: handle)
                        .id(handle.id)
                } else {
                    EmptyDetailView()
                }
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showNewSheet) {
            NewCommandSheet(store: store) { handle in
                selectedID = handle.id
                showNewSheet = false
            }
        }
        .onAppear(perform: consumePendingOpen)
        .onChange(of: navigator.pendingCommandID) { _, _ in consumePendingOpen() }
        .onChange(of: store.handles) { _, _ in consumePendingOpen() }
    }

    private func consumePendingOpen() {
        guard let id = navigator.pendingCommandID else { return }
        if store.handles.contains(where: { $0.id == id }) {
            selectedID = id
            navigator.pendingCommandID = nil
        }
    }

    private var filtered: [CommandHandle] {
        guard !searchText.isEmpty else { return store.handles }
        let q = searchText.lowercased()
        return store.handles.filter {
            $0.invocationSlug.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
        }
    }

    private var selectedHandle: CommandHandle? {
        guard let id = selectedID else { return nil }
        return store.handles.first { $0.id == id }
    }
}

private struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.quote")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a command")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
