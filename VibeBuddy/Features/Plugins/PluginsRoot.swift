import SwiftUI

struct PluginsRoot: View {
    @EnvironmentObject private var store: PluginsStore

    var body: some View {
        PluginsShell(store: store)
            .task {
                if store.plugins.isEmpty {
                    await store.reload()
                }
                store.startWatching()
            }
    }
}

private struct PluginsShell: View {
    @ObservedObject var store: PluginsStore
    @EnvironmentObject private var navigator: Navigator
    @State private var selectedID: InstalledPlugin.ID?
    @State private var searchText: String = ""
    @State private var diffPair: DiffPair?
    @State private var saveError: String?

    var body: some View {
        HSplitView {
            PluginsListView(
                plugins: filtered,
                selected: $selectedID,
                searchText: $searchText,
                totalCount: store.plugins.count,
                enabledCount: store.plugins.filter(\.isEnabled).count,
                isLoading: store.isLoading,
                onRefresh: { Task { await store.reload() } }
            )
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 440)

            Group {
                if let plugin = selectedPlugin {
                    PluginDetailView(
                        plugin: plugin,
                        onToggle: { newValue in prepareToggle(plugin, isEnabled: newValue) }
                    )
                    .id(plugin.id)
                } else {
                    ContentUnavailableView(
                        "Select a plugin",
                        systemImage: "puzzlepiece.extension"
                    )
                }
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(
            get: { diffPair != nil },
            set: { if !$0 { diffPair = nil } }
        )) {
            if let pair = diffPair {
                DiffPreviewSheet(
                    title: pair.title,
                    message: store.claudeHome.settingsFile.path(percentEncoded: false),
                    beforeText: pair.before,
                    afterText: pair.after,
                    onConfirm: { commit(pair) }
                )
            }
        }
        .onAppear(perform: consumePendingOpen)
        .onChange(of: navigator.pendingPluginID) { _, _ in consumePendingOpen() }
        .onChange(of: store.plugins) { _, _ in consumePendingOpen() }
    }

    private func consumePendingOpen() {
        guard let id = navigator.pendingPluginID else { return }
        if store.plugins.contains(where: { $0.id == id }) {
            selectedID = id
            navigator.pendingPluginID = nil
        }
    }

    // MARK: - state

    private var filtered: [InstalledPlugin] {
        guard !searchText.isEmpty else { return store.plugins }
        let q = searchText.lowercased()
        return store.plugins.filter {
            $0.pluginName.lowercased().contains(q)
                || $0.marketplaceName.lowercased().contains(q)
                || ($0.manifest.description ?? "").lowercased().contains(q)
        }
    }

    private var selectedPlugin: InstalledPlugin? {
        guard let id = selectedID else { return nil }
        return store.plugins.first { $0.id == id }
    }

    // MARK: - toggle

    private struct DiffPair {
        let title: String
        let before: String
        let after: String
        let plugin: InstalledPlugin
        let newValue: Bool
    }

    private func prepareToggle(_ plugin: InstalledPlugin, isEnabled: Bool) {
        do {
            let pair = try store.previewToggle(plugin: plugin, isEnabled: isEnabled)
            diffPair = DiffPair(
                title: "\(isEnabled ? "Enable" : "Disable") \(plugin.pluginName)?",
                before: pair.before,
                after: pair.after,
                plugin: plugin,
                newValue: isEnabled
            )
        } catch {
            saveError = (error as NSError).localizedDescription
        }
    }

    private func commit(_ pair: DiffPair) {
        do {
            try store.commitToggle(plugin: pair.plugin, isEnabled: pair.newValue)
            saveError = nil
        } catch {
            saveError = (error as NSError).localizedDescription
        }
        diffPair = nil
    }
}
