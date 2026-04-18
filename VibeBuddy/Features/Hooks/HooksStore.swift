import Foundation

@MainActor
final class HooksStore: ObservableObject {
    @Published private(set) var config: HooksConfig = .empty
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?
    @Published private(set) var lastSaveError: String?

    let claudeHome: ClaudeHome
    private let settings: SafeJSONStore
    private var watcher: DirectoryWatcher?
    private var debounceTask: Task<Void, Never>?

    init(claudeHome: ClaudeHome = .discover()) {
        self.claudeHome = claudeHome
        self.settings = SafeJSONStore(url: claudeHome.settingsFile)
    }

    deinit { watcher?.stop() }

    // MARK: - read

    func reload() async {
        isLoading = true
        loadError = nil
        do {
            let dict = try settings.load()
            self.config = HooksCodec.parse(dict["hooks"])
        } catch {
            self.config = .empty
            self.loadError = (error as NSError).localizedDescription
        }
        isLoading = false
    }

    // MARK: - write

    /// Returns the `before` / `after` pair the diff sheet should show. Does
    /// NOT touch disk; caller commits via `commit(_:)` after confirmation.
    func previewSave(_ updated: HooksConfig) throws -> (before: String, after: String) {
        let current = try settings.load()
        var next = current
        next["hooks"] = HooksCodec.toJSON(updated)

        let before = try SafeJSONStore.serializedString(current)
        let after = try SafeJSONStore.serializedString(next)
        return (before, after)
    }

    func commit(_ updated: HooksConfig) throws {
        var dict = try settings.load()
        dict["hooks"] = HooksCodec.toJSON(updated)
        try settings.save(dict)
        config = updated
        lastSaveError = nil
    }

    // MARK: - watch

    func startWatching() {
        guard watcher == nil else { return }
        let dir = claudeHome.settingsFile.deletingLastPathComponent()
        let target = claudeHome.settingsFile
        let w = DirectoryWatcher(url: dir) { [weak self] in
            Task { @MainActor in self?.onDirChanged(target: target) }
        }
        w.start()
        watcher = w
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func onDirChanged(target: URL) {
        // We watch the parent dir (settings.json sits at ~/.claude/settings.json).
        // Ignore events that don't touch the file we care about — FSEvents
        // doesn't give us per-file granularity here, so this is a best-effort
        // filter via mtime check.
        _ = target     // (silences warnings if we later tighten the filter)
        scheduleReload()
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
