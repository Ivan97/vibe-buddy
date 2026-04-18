import Foundation

@MainActor
final class PluginsStore: ObservableObject {
    @Published private(set) var plugins: [InstalledPlugin] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    let claudeHome: ClaudeHome
    private let scanner: PluginScanner
    private let settings: SafeJSONStore
    private var watcher: DirectoryWatcher?
    private var debounceTask: Task<Void, Never>?

    init(
        claudeHome: ClaudeHome = .discover(),
        scanner: PluginScanner = PluginScanner()
    ) {
        self.claudeHome = claudeHome
        self.scanner = scanner
        self.settings = SafeJSONStore(url: claudeHome.settingsFile)
    }

    deinit { watcher?.stop() }

    // MARK: - read

    func reload() async {
        isLoading = true
        loadError = nil

        let pluginsDir = claudeHome.pluginsDir
        let enabledIds = (try? Self.loadEnabledPlugins(from: settings)) ?? []
        let scanner = self.scanner

        let result = await Task.detached(priority: .userInitiated) {
            scanner.scan(pluginsDir: pluginsDir, enabledPlugins: Set(enabledIds))
        }.value

        isLoading = false
        plugins = result
    }

    private static func loadEnabledPlugins(from store: SafeJSONStore) throws -> [String] {
        let dict = try store.load()
        guard let enabled = dict["enabledPlugins"] as? [String: Any] else { return [] }
        return enabled.compactMap { key, value -> String? in
            // Claude Code stores either `true` or a config dict; absence is
            // 'disabled'. We treat any non-false value as enabled.
            if let flag = value as? Bool { return flag ? key : nil }
            return key   // object → enabled with config
        }
    }

    // MARK: - write

    /// Returns the (before, after, updated) triple the caller can feed into
    /// a DiffPreviewSheet. Does NOT touch disk — caller commits via
    /// `commitToggle(plugin:isEnabled:)`.
    func previewToggle(plugin: InstalledPlugin, isEnabled: Bool) throws -> (before: String, after: String) {
        let current = try settings.load()
        var updated = current
        var enabled = (current["enabledPlugins"] as? [String: Any]) ?? [:]

        if isEnabled {
            enabled[plugin.id] = true
        } else {
            enabled.removeValue(forKey: plugin.id)
        }
        updated["enabledPlugins"] = enabled

        let before = try SafeJSONStore.serializedString(current)
        let after = try SafeJSONStore.serializedString(updated)
        return (before, after)
    }

    func commitToggle(plugin: InstalledPlugin, isEnabled: Bool) throws {
        var dict = try settings.load()
        var enabled = (dict["enabledPlugins"] as? [String: Any]) ?? [:]
        if isEnabled {
            enabled[plugin.id] = true
        } else {
            enabled.removeValue(forKey: plugin.id)
        }
        dict["enabledPlugins"] = enabled
        try settings.save(dict)

        if let idx = plugins.firstIndex(where: { $0.id == plugin.id }) {
            plugins[idx].isEnabled = isEnabled
        }
    }

    // MARK: - watch

    func startWatching() {
        guard watcher == nil else { return }
        // Watch the plugins root so install/uninstall is picked up. Also
        // watching settings.json would be nicer for enabledPlugins drift
        // but one watcher is enough for this phase.
        let dir = claudeHome.pluginsDir
        let w = DirectoryWatcher(url: dir) { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        w.start()
        watcher = w
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }
}
