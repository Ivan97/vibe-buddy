import SwiftUI

struct MCPRoot: View {
    @EnvironmentObject private var store: MCPStore

    var body: some View {
        MCPShell(store: store)
            .task {
                await store.reload()
                store.startWatching()
            }
    }
}

private struct MCPShell: View {
    @ObservedObject var store: MCPStore
    @EnvironmentObject private var navigator: Navigator

    @State private var editing: [MCPServer] = []
    @State private var original: [MCPServer] = []
    @State private var selectedName: String?
    @State private var diffPair: DiffPair?
    @State private var saveError: String?
    @State private var showNewSheet = false

    private var isDirty: Bool { editing != original }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            editing = store.servers
            original = store.servers
            if selectedName == nil {
                selectedName = store.servers.first?.name
            }
        }
        .onChange(of: store.servers) { _, new in
            if !isDirty {
                editing = new
                original = new
            }
            consumePendingOpen()
        }
        .onChange(of: navigator.pendingMCPServerName) { _, _ in consumePendingOpen() }
        .sheet(isPresented: $showNewSheet) {
            NewMCPServerSheet(existingNames: Set(editing.map(\.name))) { server in
                editing.append(server)
                editing.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                selectedName = server.name
                showNewSheet = false
            }
        }
        .sheet(isPresented: Binding(
            get: { diffPair != nil },
            set: { if !$0 { diffPair = nil } }
        )) {
            if let pair = diffPair {
                DiffPreviewSheet(
                    title: "Save MCP servers?",
                    message: store.claudeHome.mainConfigFile.path(percentEncoded: false),
                    beforeText: pair.before,
                    afterText: pair.after,
                    onConfirm: { commit(pair.updated) }
                )
            }
        }
    }

    // MARK: - toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MCP Servers").font(.headline)
                Text(store.claudeHome.mainConfigFile.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isDirty {
                Label("Unsaved", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
            if let err = saveError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Revert") {
                editing = original
                saveError = nil
            }
            .disabled(!isDirty)
            Button("Save") { prepareSave() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)
        }
        .padding(12)
    }

    private var content: some View {
        HSplitView {
            MCPListView(
                servers: editing,
                selectedName: $selectedName,
                onNew: { showNewSheet = true },
                onDelete: deleteSelected
            )
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

            Group {
                if let idx = editing.firstIndex(where: { $0.name == selectedName }) {
                    MCPServerEditor(server: $editing[idx])
                } else if editing.isEmpty {
                    ContentUnavailableView(
                        "No MCP servers",
                        systemImage: "bolt.horizontal",
                        description: Text("Click + New Server to add one.")
                    )
                } else {
                    ContentUnavailableView(
                        "Select a server",
                        systemImage: "bolt.horizontal"
                    )
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func consumePendingOpen() {
        guard let name = navigator.pendingMCPServerName else { return }
        if editing.contains(where: { $0.name == name }) {
            selectedName = name
            navigator.pendingMCPServerName = nil
        }
    }

    // MARK: - actions

    private func deleteSelected() {
        guard let name = selectedName,
              let idx = editing.firstIndex(where: { $0.name == name }) else { return }
        editing.remove(at: idx)
        selectedName = editing.first?.name
    }

    private struct DiffPair {
        let before: String
        let after: String
        let updated: [MCPServer]
    }

    private func prepareSave() {
        do {
            let pair = try store.previewSave(editing)
            diffPair = DiffPair(before: pair.before, after: pair.after, updated: editing)
        } catch {
            saveError = (error as NSError).localizedDescription
        }
    }

    private func commit(_ updated: [MCPServer]) {
        do {
            try store.commit(updated)
            original = updated
            editing = updated
            saveError = nil
        } catch {
            saveError = (error as NSError).localizedDescription
        }
        diffPair = nil
    }
}
