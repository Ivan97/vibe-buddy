import Foundation

@MainActor
final class PluginsStore: ObservableObject {
    @Published private(set) var plugins: [InstalledPlugin] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    /// Per-plugin upstream status, keyed by `InstalledPlugin.id`. Populated
    /// on demand by `checkForUpdates()` — never automatic, so we don't
    /// fire network I/O on launch. Absent key → `.unchecked`.
    @Published private(set) var updateStatus: [String: GitUpdateChecker.Status] = [:]
    @Published private(set) var isCheckingUpdates: Bool = false

    /// Plugin IDs with a `claude plugin update` call in flight. UI uses
    /// this to show a spinner on the update button.
    @Published private(set) var updatesInFlight: Set<String> = []
    /// Last CLI outcome per plugin — stdout on success, error description
    /// on failure. Rendered as a trailing banner in the detail view.
    @Published private(set) var lastUpdateResult: [String: UpdateResult] = [:]

    enum UpdateResult: Equatable, Sendable {
        case success(output: String, at: Date)
        case failure(message: String, at: Date)
    }

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

    // MARK: - update checks

    func status(for pluginID: String) -> GitUpdateChecker.Status {
        updateStatus[pluginID] ?? .unchecked
    }

    /// Fires `git ls-remote` for every plugin whose bundle sits inside a
    /// git checkout. Caps concurrency at 4 to avoid hammering the network
    /// and to play nice with rate-limited hosts (GitHub, self-hosted
    /// forges). Updates `updateStatus` as each result lands.
    func checkAllForUpdates() async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        // Snapshot — avoid racing against a concurrent reload.
        let targets: [(id: String, root: URL)] = plugins.compactMap { plugin in
            guard let root = GitUpdateChecker.findRepoRoot(startingFrom: plugin.bundleRoot) else {
                return nil
            }
            return (plugin.id, root)
        }
        // Mark un-tracked bundles explicitly so the user can tell
        // "nothing reported" apart from "no git upstream".
        for plugin in plugins {
            if GitUpdateChecker.findRepoRoot(startingFrom: plugin.bundleRoot) == nil {
                updateStatus[plugin.id] = .notTracked
            } else {
                updateStatus[plugin.id] = .checking
            }
        }

        await withTaskGroup(of: (String, GitUpdateChecker.Status).self) { group in
            var inFlight = 0
            var iterator = targets.makeIterator()
            let limit = 4

            func enqueueNext() {
                guard let next = iterator.next() else { return }
                group.addTask {
                    let status = await GitUpdateChecker.check(repoRoot: next.root)
                    return (next.id, status)
                }
                inFlight += 1
            }

            for _ in 0..<min(limit, targets.count) { enqueueNext() }

            while inFlight > 0 {
                if let (id, status) = await group.next() {
                    updateStatus[id] = status
                    inFlight -= 1
                    enqueueNext()
                }
            }
        }
    }

    /// Refresh just one plugin's status — used by the per-row "check"
    /// action. Cheaper than walking every bundle when the user only
    /// cares about one.
    func checkForUpdate(_ pluginID: String) async {
        guard let plugin = plugins.first(where: { $0.id == pluginID }) else { return }
        guard let root = GitUpdateChecker.findRepoRoot(startingFrom: plugin.bundleRoot) else {
            updateStatus[pluginID] = .notTracked
            return
        }
        updateStatus[pluginID] = .checking
        let status = await GitUpdateChecker.check(repoRoot: root)
        updateStatus[pluginID] = status
    }

    // MARK: - apply updates via `claude plugin update`

    /// Shell out to `claude plugin update <id>` — Claude Code pulls the
    /// latest commit into its cache. Running sessions still see the old
    /// version until they restart; we surface that caveat in the UI.
    /// On success, re-check the upstream status so the banner flips to
    /// "up to date" without a manual re-click.
    func runUpdate(_ pluginID: String) async {
        guard !updatesInFlight.contains(pluginID) else { return }
        updatesInFlight.insert(pluginID)
        defer { updatesInFlight.remove(pluginID) }

        do {
            let output = try await ClaudeCLI.run(["plugin", "update", pluginID])
            lastUpdateResult[pluginID] = .success(output: output, at: Date())
            // Re-scan so the version / mtime / contributions refresh.
            await reload()
            await checkForUpdate(pluginID)
        } catch {
            lastUpdateResult[pluginID] = .failure(
                message: (error as NSError).localizedDescription,
                at: Date()
            )
        }
    }

    /// Drop a plugin's last-run banner once the user acknowledges it.
    func clearUpdateResult(_ pluginID: String) {
        lastUpdateResult.removeValue(forKey: pluginID)
    }
}
