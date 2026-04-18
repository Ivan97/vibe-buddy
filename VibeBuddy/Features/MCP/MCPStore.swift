import Foundation

@MainActor
final class MCPStore: ObservableObject {
    @Published private(set) var servers: [MCPServer] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    let claudeHome: ClaudeHome
    private let json: SafeJSONStore
    private var watcher: DirectoryWatcher?
    private var pluginsWatcher: DirectoryWatcher?
    private var debounceTask: Task<Void, Never>?

    init(claudeHome: ClaudeHome = .discover()) {
        self.claudeHome = claudeHome
        self.json = SafeJSONStore(url: claudeHome.mainConfigFile)
    }

    deinit {
        watcher?.stop()
        pluginsWatcher?.stop()
    }

    // MARK: - read

    func reload() async {
        isLoading = true
        loadError = nil
        let pluginsDir = claudeHome.pluginsDir
        let pluginScoped = await Task.detached(priority: .userInitiated) {
            Self.scanPluginServers(pluginsDir: pluginsDir)
        }.value
        do {
            let dict = try json.load()
            let userScoped = MCPCodec.parse(dict["mcpServers"], scope: .user)
            self.servers = Self.merge(user: userScoped, plugin: pluginScoped)
        } catch {
            self.servers = Self.merge(user: [], plugin: pluginScoped)
            self.loadError = (error as NSError).localizedDescription
        }
        isLoading = false
    }

    // MARK: - write

    func previewSave(_ updated: [MCPServer]) throws -> (before: String, after: String) {
        let userScoped = updated.filter { $0.isEditable }
        let current = try json.load()
        var next = current
        if userScoped.isEmpty {
            next.removeValue(forKey: "mcpServers")
        } else {
            next["mcpServers"] = MCPCodec.toJSON(userScoped)
        }
        let before = try SafeJSONStore.serializedString(current)
        let after = try SafeJSONStore.serializedString(next)
        return (before, after)
    }

    func commit(_ updated: [MCPServer]) throws {
        let userScoped = updated.filter { $0.isEditable }
        var dict = try json.load()
        if userScoped.isEmpty {
            dict.removeValue(forKey: "mcpServers")
        } else {
            dict["mcpServers"] = MCPCodec.toJSON(userScoped)
        }
        try json.save(dict)
        let pluginScoped = updated.filter { !$0.isEditable }
        servers = Self.merge(user: userScoped, plugin: pluginScoped)
    }

    // MARK: - watch

    func startWatching() {
        if watcher == nil {
            let dir = claudeHome.mainConfigFile.deletingLastPathComponent()
            let w = DirectoryWatcher(url: dir) { [weak self] in
                Task { @MainActor in self?.scheduleReload() }
            }
            w.start()
            watcher = w
        }
        if pluginsWatcher == nil {
            let dir = claudeHome.pluginsDir
            if FileManager.default.fileExists(atPath: dir.path) {
                let w = DirectoryWatcher(url: dir) { [weak self] in
                    Task { @MainActor in self?.scheduleReload() }
                }
                w.start()
                pluginsWatcher = w
            }
        }
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
        pluginsWatcher?.stop()
        pluginsWatcher = nil
    }

    private func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    // MARK: - merge

    /// User-scoped servers win on name collision — a plugin shouldn't be
    /// able to shadow a name the user has already configured manually.
    private static func merge(user: [MCPServer], plugin: [MCPServer]) -> [MCPServer] {
        let userNames = Set(user.map(\.name))
        let deduped = plugin.filter { !userNames.contains($0.name) }
        return (user + deduped).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - plugin scan

    /// Walks `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/.claude-plugin/plugin.json`,
    /// returning every `mcpServers` entry declared inline, tagged with its
    /// `<marketplace>, <plugin>` scope. Same hidden-dir trap as the agents
    /// scanner — DO NOT pass `.skipsHiddenFiles` or `.claude-plugin` will
    /// be skipped silently.
    nonisolated private static func scanPluginServers(pluginsDir: URL) -> [MCPServer] {
        let fm = FileManager.default
        let cacheDir = pluginsDir.appending(path: "cache", directoryHint: .isDirectory)
        guard fm.fileExists(atPath: cacheDir.path) else { return [] }
        guard let enumerator = fm.enumerator(
            at: cacheDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }

        var latest: [String: (server: MCPServer, mtime: Date)] = [:]
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "plugin.json",
                  url.deletingLastPathComponent().lastPathComponent == ".claude-plugin"
            else { continue }

            // Expected layout: cache/<marketplace>/<plugin>/<version>/.claude-plugin/plugin.json
            let parts = url.standardizedFileURL.pathComponents
            guard let cacheIdx = parts.firstIndex(of: "cache") else { continue }
            let marketplace = parts.count > cacheIdx + 1 ? parts[cacheIdx + 1] : "unknown"
            let plugin = parts.count > cacheIdx + 2 ? parts[cacheIdx + 2] : marketplace

            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let dict = obj as? [String: Any],
                  let mcpAny = dict["mcpServers"] else { continue }

            let bundleRoot = url
                .deletingLastPathComponent()  // .claude-plugin
                .deletingLastPathComponent()  // <version>
            let mtime = (try? fm.attributesOfItem(atPath: bundleRoot.path)[.modificationDate]) as? Date ?? .distantPast

            let scope = MCPServer.Scope.plugin(marketplace: marketplace, pluginName: plugin)
            for server in MCPCodec.parse(mcpAny, scope: scope) {
                // Dedup across plugin versions the same way PluginScanner
                // does — the most recently modified bundle wins.
                let key = "\(plugin)@\(marketplace)#\(server.name)"
                if let existing = latest[key], existing.mtime >= mtime { continue }
                latest[key] = (server, mtime)
            }
        }
        return latest.values.map(\.server)
    }
}
