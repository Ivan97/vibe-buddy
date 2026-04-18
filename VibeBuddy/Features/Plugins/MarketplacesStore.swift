import Foundation

/// Reads and writes `~/.claude/plugins/known_marketplaces.json` — the file
/// Claude Code keeps its marketplace registry in. Primary reason we care:
/// the per-marketplace `autoUpdate` flag, which Claude Code respects on
/// next launch. Other fields we round-trip untouched.
@MainActor
final class MarketplacesStore: ObservableObject {
    @Published private(set) var marketplaces: [MarketplaceEntry] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    let url: URL
    private let json: SafeJSONStore
    private var watcher: DirectoryWatcher?
    private var debounceTask: Task<Void, Never>?

    init(claudeHome: ClaudeHome = .discover()) {
        self.url = claudeHome.pluginsDir
            .appending(path: "known_marketplaces.json")
        self.json = SafeJSONStore(url: url)
    }

    deinit { watcher?.stop() }

    // MARK: - read

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let dict = try json.load()
            marketplaces = Self.parse(dict)
            loadError = nil
        } catch {
            marketplaces = []
            loadError = (error as NSError).localizedDescription
        }
    }

    /// Convenience lookup. Returns `.unchecked`-equivalent `nil` when the
    /// marketplace isn't in the registry (e.g. fresh install).
    func entry(named name: String) -> MarketplaceEntry? {
        marketplaces.first { $0.id == name }
    }

    // MARK: - write

    /// Build a (before, after) diff for flipping `autoUpdate` on one
    /// marketplace. Caller feeds this into `DiffPreviewSheet`, then
    /// `commitAutoUpdate` if confirmed.
    func previewAutoUpdate(_ name: String, enabled: Bool) throws -> (before: String, after: String) {
        let current = try json.load()
        var next = current
        var entry = (current[name] as? [String: Any]) ?? [:]
        if enabled {
            entry["autoUpdate"] = true
        } else {
            entry.removeValue(forKey: "autoUpdate")
        }
        next[name] = entry
        let before = try SafeJSONStore.serializedString(current)
        let after = try SafeJSONStore.serializedString(next)
        return (before, after)
    }

    func commitAutoUpdate(_ name: String, enabled: Bool) throws {
        var dict = try json.load()
        var entry = (dict[name] as? [String: Any]) ?? [:]
        if enabled {
            entry["autoUpdate"] = true
        } else {
            entry.removeValue(forKey: "autoUpdate")
        }
        dict[name] = entry
        try json.save(dict)

        if let idx = marketplaces.firstIndex(where: { $0.id == name }) {
            marketplaces[idx].autoUpdate = enabled
        } else {
            // Entry didn't exist yet (edge case); reload to pick up the
            // new row we just wrote.
            marketplaces = Self.parse(dict)
        }
    }

    // MARK: - watch

    func startWatching() {
        guard watcher == nil else { return }
        let dir = url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
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

    // MARK: - parse

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let sourceOwnedKeys: Set<String> = ["source", "repo"]
    private static let entryOwnedKeys: Set<String> = [
        "source", "installLocation", "lastUpdated", "autoUpdate"
    ]

    nonisolated static func parse(_ dict: [String: Any]) -> [MarketplaceEntry] {
        var out: [MarketplaceEntry] = []
        for (name, raw) in dict {
            guard let entryDict = raw as? [String: Any] else { continue }

            let sourceDict = (entryDict["source"] as? [String: Any]) ?? [:]
            let sourceType = sourceDict["source"] as? String
            let repo = sourceDict["repo"] as? String
            var sourceExtras: [String: Any] = [:]
            for (k, v) in sourceDict where !sourceOwnedKeys.contains(k) {
                sourceExtras[k] = v
            }

            let installLocation = (entryDict["installLocation"] as? String)
                .map { URL(fileURLWithPath: $0) }
            let lastUpdated = (entryDict["lastUpdated"] as? String)
                .flatMap { iso.date(from: $0) ?? ISO8601Tolerant.parse($0) }
            let autoUpdate = (entryDict["autoUpdate"] as? Bool) ?? false

            var extras: [String: Any] = [:]
            for (k, v) in entryDict where !entryOwnedKeys.contains(k) {
                extras[k] = v
            }

            out.append(MarketplaceEntry(
                id: name,
                repo: repo,
                sourceType: sourceType,
                sourceExtras: sourceExtras,
                installLocation: installLocation,
                lastUpdated: lastUpdated,
                autoUpdate: autoUpdate,
                extras: extras
            ))
        }
        return out.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }
}
