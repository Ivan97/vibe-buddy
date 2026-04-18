import Foundation

/// Per-target cached state: what we read from disk plus a lightweight
/// snapshot used by the file list (mtime, size, existence).
struct SettingsFileState: Equatable, Sendable {
    let target: SettingsTarget
    let exists: Bool
    let byteSize: Int64
    let modifiedAt: Date?
    let loadError: String?
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var files: [SettingsTarget: SettingsFileState] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    let claudeHome: ClaudeHome
    private var watchers: [SettingsTarget: DirectoryWatcher] = [:]
    private var debounceTask: Task<Void, Never>?

    init(claudeHome: ClaudeHome = .discover()) {
        self.claudeHome = claudeHome
    }

    deinit {
        for w in watchers.values { w.stop() }
    }

    // MARK: - reads

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        var next: [SettingsTarget: SettingsFileState] = [:]
        for target in SettingsTarget.allCases {
            next[target] = probe(target: target)
        }
        self.files = next
    }

    /// Load a single target as `ClaudeSettings`. Throws if the file exists
    /// but fails to parse — the editor surfaces this inline rather than
    /// wiping the user's data.
    func loadSettings(_ target: SettingsTarget) throws -> ClaudeSettings {
        let store = SafeJSONStore(url: target.url(in: claudeHome))
        let dict = try store.load()
        return SettingsCodec.parse(dict)
    }

    /// Returns (before, after) JSON strings so the diff sheet can show
    /// exactly what will hit disk. Other callers' keys (MCP, hooks,
    /// plugins, statusline) flow through unchanged — `SettingsCodec` only
    /// writes the typed keys + `extras`.
    func previewSave(_ updated: ClaudeSettings, for target: SettingsTarget) throws -> (before: String, after: String) {
        let store = SafeJSONStore(url: target.url(in: claudeHome))
        let current = try store.load()
        let next = SettingsCodec.serialize(updated)
        let before = try SafeJSONStore.serializedString(current)
        let after = try SafeJSONStore.serializedString(next)
        return (before, after)
    }

    func commit(_ updated: ClaudeSettings, for target: SettingsTarget) throws {
        let store = SafeJSONStore(url: target.url(in: claudeHome))
        let next = SettingsCodec.serialize(updated)
        try store.save(next)
        files[target] = probe(target: target)
    }

    // MARK: - watchers

    func startWatching() {
        for target in SettingsTarget.allCases {
            guard watchers[target] == nil else { continue }
            let dir = target.url(in: claudeHome).deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }
            let w = DirectoryWatcher(url: dir) { [weak self] in
                Task { @MainActor in self?.scheduleReload() }
            }
            w.start()
            watchers[target] = w
        }
    }

    func stopWatching() {
        for (key, w) in watchers {
            w.stop()
            watchers[key] = nil
        }
    }

    private func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    // MARK: - helpers

    private func probe(target: SettingsTarget) -> SettingsFileState {
        let url = target.url(in: claudeHome)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return SettingsFileState(target: target, exists: false, byteSize: 0, modifiedAt: nil, loadError: nil)
        }
        let attrs = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = attrs[.modificationDate] as? Date
        let err: String?
        do {
            _ = try SafeJSONStore(url: url).load()
            err = nil
        } catch {
            err = (error as NSError).localizedDescription
        }
        return SettingsFileState(
            target: target,
            exists: true,
            byteSize: size,
            modifiedAt: mtime,
            loadError: err
        )
    }
}
