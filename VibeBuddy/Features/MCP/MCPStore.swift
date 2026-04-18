import Foundation

@MainActor
final class MCPStore: ObservableObject {
    @Published private(set) var servers: [MCPServer] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    let claudeHome: ClaudeHome
    private let json: SafeJSONStore
    private var watcher: DirectoryWatcher?
    private var debounceTask: Task<Void, Never>?

    init(claudeHome: ClaudeHome = .discover()) {
        self.claudeHome = claudeHome
        self.json = SafeJSONStore(url: claudeHome.mainConfigFile)
    }

    deinit { watcher?.stop() }

    // MARK: - read

    func reload() async {
        isLoading = true
        loadError = nil
        do {
            let dict = try json.load()
            self.servers = MCPCodec.parse(dict["mcpServers"])
        } catch {
            self.servers = []
            self.loadError = (error as NSError).localizedDescription
        }
        isLoading = false
    }

    // MARK: - write

    func previewSave(_ updated: [MCPServer]) throws -> (before: String, after: String) {
        let current = try json.load()
        var next = current
        if updated.isEmpty {
            next.removeValue(forKey: "mcpServers")
        } else {
            next["mcpServers"] = MCPCodec.toJSON(updated)
        }
        let before = try SafeJSONStore.serializedString(current)
        let after = try SafeJSONStore.serializedString(next)
        return (before, after)
    }

    func commit(_ updated: [MCPServer]) throws {
        var dict = try json.load()
        if updated.isEmpty {
            dict.removeValue(forKey: "mcpServers")
        } else {
            dict["mcpServers"] = MCPCodec.toJSON(updated)
        }
        try json.save(dict)
        servers = updated.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - watch

    func startWatching() {
        guard watcher == nil else { return }
        let dir = claudeHome.mainConfigFile.deletingLastPathComponent()
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
