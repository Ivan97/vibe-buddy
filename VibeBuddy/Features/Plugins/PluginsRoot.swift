import SwiftUI

struct PluginsRoot: View {
    @EnvironmentObject private var store: PluginsStore
    @EnvironmentObject private var marketplaces: MarketplacesStore

    var body: some View {
        PluginsShell(store: store, marketplaces: marketplaces)
            .task {
                if store.plugins.isEmpty {
                    await store.reload()
                }
                store.startWatching()
                await marketplaces.reload()
                marketplaces.startWatching()
            }
    }
}

private struct PluginsShell: View {
    @ObservedObject var store: PluginsStore
    @ObservedObject var marketplaces: MarketplacesStore
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
                isCheckingUpdates: store.isCheckingUpdates,
                updateStatus: { store.status(for: $0) },
                autoUpdate: { marketplaces.entry(named: $0)?.autoUpdate ?? false },
                onRefresh: { Task { await store.reload() } },
                onCheckUpdates: { Task { await store.checkAllForUpdates() } },
                onToggleMarketplaceAutoUpdate: { name, enabled in
                    prepareMarketplaceToggle(name: name, enabled: enabled)
                }
            )
            .frame(minWidth: 300, idealWidth: 400)

            Group {
                if let plugin = selectedPlugin {
                    // No .id — PluginDetailView is stateless beyond hover,
                    // so it re-renders fine on parameter change. Forcing
                    // fresh identity would reset HSplitView's divider.
                    PluginDetailView(
                        plugin: plugin,
                        status: store.status(for: plugin.id),
                        isUpdating: store.updatesInFlight.contains(plugin.id),
                        lastUpdateResult: store.lastUpdateResult[plugin.id],
                        onToggle: { newValue in prepareToggle(plugin, isEnabled: newValue) },
                        onCheckUpdate: { Task { await store.checkForUpdate(plugin.id) } },
                        onUpdateNow: { Task { await store.runUpdate(plugin.id) } },
                        onDismissUpdateResult: { store.clearUpdateResult(plugin.id) }
                    )
                } else {
                    ContentUnavailableView(
                        "Select a plugin",
                        systemImage: "puzzlepiece.extension"
                    )
                }
            }
            .frame(minWidth: 400, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(
            get: { diffPair != nil },
            set: { if !$0 { diffPair = nil } }
        )) {
            if let pair = diffPair {
                DiffPreviewSheet(
                    title: pair.title,
                    message: pair.file.path(percentEncoded: false),
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

    /// Unified pending-diff envelope — one sheet handles both plugin
    /// enable/disable and marketplace autoUpdate flips. The `apply`
    /// closure carries the commit-time side effect so we don't need
    /// parallel commit paths per target file.
    private struct DiffPair {
        let title: String
        let file: URL
        let before: String
        let after: String
        let apply: () throws -> Void
    }

    private func prepareToggle(_ plugin: InstalledPlugin, isEnabled: Bool) {
        do {
            let pair = try store.previewToggle(plugin: plugin, isEnabled: isEnabled)
            diffPair = DiffPair(
                title: "\(isEnabled ? "Enable" : "Disable") \(plugin.pluginName)?",
                file: store.claudeHome.settingsFile,
                before: pair.before,
                after: pair.after,
                apply: { try store.commitToggle(plugin: plugin, isEnabled: isEnabled) }
            )
        } catch {
            saveError = (error as NSError).localizedDescription
        }
    }

    private func prepareMarketplaceToggle(name: String, enabled: Bool) {
        do {
            let pair = try marketplaces.previewAutoUpdate(name, enabled: enabled)
            diffPair = DiffPair(
                title: "\(enabled ? "Enable" : "Disable") auto-update for \(name)?",
                file: marketplaces.url,
                before: pair.before,
                after: pair.after,
                apply: { try marketplaces.commitAutoUpdate(name, enabled: enabled) }
            )
        } catch {
            saveError = (error as NSError).localizedDescription
        }
    }

    private func commit(_ pair: DiffPair) {
        do {
            try pair.apply()
            saveError = nil
        } catch {
            saveError = (error as NSError).localizedDescription
        }
        diffPair = nil
    }
}
