import Foundation

struct AgentHandle: Identifiable, Hashable, Sendable {
    let id: String           // file URL path, globally unique
    let name: String         // name field from frontmatter (falls back to filename stem)
    let description: String  // truncated preview for list rows
    let url: URL
    let scope: Scope

    enum Scope: Hashable, Sendable {
        case user
        case plugin(marketplace: String, pluginName: String)
    }

    var isEditable: Bool {
        switch scope {
        case .user:   return true
        case .plugin: return false
        }
    }

    /// `InstalledPlugin.id` when this agent is plugin-provided.
    var pluginID: String? {
        if case .plugin(let marketplace, let name) = scope {
            return "\(name)@\(marketplace)"
        }
        return nil
    }

    /// Helper for list sorts when loading fails — ensure deterministic order.
    var sortKey: String { name.isEmpty ? url.lastPathComponent : name }
}

@MainActor
final class AgentStore: ObservableObject {
    @Published private(set) var handles: [AgentHandle] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    let claudeHome: ClaudeHome
    private var watcher: DirectoryWatcher?
    private var debounceTask: Task<Void, Never>?

    init(claudeHome: ClaudeHome = .discover()) {
        self.claudeHome = claudeHome
    }

    deinit {
        watcher?.stop()
    }

    // MARK: - read

    func reload() async {
        isLoading = true
        loadError = nil
        let userDir = claudeHome.agentsDir
        let pluginsDir = claudeHome.pluginsDir
        let result = await Task.detached(priority: .userInitiated) {
            Self.scanAll(userDir: userDir, pluginsDir: pluginsDir)
        }.value
        isLoading = false
        switch result {
        case .success(let list):
            handles = list
        case .failure(let error):
            loadError = (error as NSError).localizedDescription
        }
    }

    func load(_ handle: AgentHandle) throws -> FrontmatterDocument<AgentFrontmatter> {
        let raw = try String(contentsOf: handle.url, encoding: .utf8)
        return FrontmatterDocument<AgentFrontmatter>(raw: raw)
    }

    // MARK: - write

    /// Returns the (possibly updated) handle that matches the saved file.
    @discardableResult
    func save(
        _ document: FrontmatterDocument<AgentFrontmatter>,
        to handle: AgentHandle
    ) throws -> AgentHandle {
        guard handle.isEditable else {
            throw NSError(
                domain: "VibeBuddy.AgentStore",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Plugin-provided agents are read-only."]
            )
        }
        try SafeTextWriter.write(document.serialized(), to: handle.url)
        let refreshed = AgentHandle(
            id: handle.id,
            name: document.schema.name.isEmpty
                ? handle.url.deletingPathExtension().lastPathComponent
                : document.schema.name,
            description: String(document.schema.description.prefix(160)),
            url: handle.url,
            scope: handle.scope
        )
        if let idx = handles.firstIndex(where: { $0.id == handle.id }) {
            handles[idx] = refreshed
        }
        return refreshed
    }

    /// Creates a new agent file in the global scope. Fails if the filename
    /// would collide. Returns the new handle.
    func create(
        name: String,
        description: String,
        model: String?
    ) throws -> AgentHandle {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "VibeBuddy.AgentStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty."]
            )
        }
        let fileName = "\(trimmed).md"
        let url = claudeHome.agentsDir.appending(path: fileName)

        if FileManager.default.fileExists(atPath: url.path) {
            throw NSError(
                domain: "VibeBuddy.AgentStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "An agent named '\(trimmed)' already exists."]
            )
        }

        let schema = AgentFrontmatter(
            name: trimmed,
            description: description,
            model: model,
            extras: []
        )
        let doc = FrontmatterDocument(schema: schema, body: "")
        try SafeTextWriter.write(doc.serialized(), to: url, makeBackup: false)

        let handle = AgentHandle(
            id: url.path,
            name: trimmed,
            description: description,
            url: url,
            scope: .user
        )
        handles.insert(handle, at: 0)
        return handle
    }

    func delete(_ handle: AgentHandle) throws {
        guard handle.isEditable else {
            throw NSError(
                domain: "VibeBuddy.AgentStore",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Plugin-provided agents are read-only."]
            )
        }
        try FileManager.default.removeItem(at: handle.url)
        handles.removeAll { $0.id == handle.id }
    }

    // MARK: - watch

    func startWatching() {
        guard watcher == nil else { return }
        let dir = claudeHome.agentsDir
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

    // MARK: - scan

    nonisolated private static func scanAll(userDir: URL, pluginsDir: URL) -> Result<[AgentHandle], Error> {
        var out: [AgentHandle] = []
        out.append(contentsOf: scanUser(dir: userDir))
        out.append(contentsOf: scanPlugins(pluginsDir: pluginsDir))
        return .success(out.sorted { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending })
    }

    nonisolated private static func scanUser(dir: URL) -> [AgentHandle] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { url -> AgentHandle? in
            guard url.pathExtension == "md" else { return nil }
            let stem = url.deletingPathExtension().lastPathComponent
            if stem.uppercased() == "README" || stem.uppercased() == "LICENSE" {
                return nil
            }
            return readHandle(from: url, scope: .user)
        }
    }

    nonisolated private static func scanPlugins(pluginsDir: URL) -> [AgentHandle] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: pluginsDir.path) else { return [] }
        // Don't pass .skipsHiddenFiles — the same hidden-folder gotcha that
        // bit us with .claude-plugin. We filter /docs/ and /.opencode/
        // components manually below.
        guard let enumerator = fm.enumerator(
            at: pluginsDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }

        var out: [AgentHandle] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "md" else { continue }
            let parts = url.standardizedFileURL.pathComponents
            guard let agentsIdx = parts.firstIndex(of: "agents"),
                  agentsIdx > 0, agentsIdx < parts.count - 1 else { continue }
            // Make sure this is a plugin bundle's `agents/` dir, not a
            // sibling like `docs/agents` or `.opencode/agents`.
            if parts.contains(".opencode") || parts.contains("docs") { continue }

            // Expected layout: cache/<marketplace>/<plugin>/<version>/agents/<file>.md
            // Derive marketplace + plugin by finding "cache" in the prefix.
            guard let cacheIdx = parts.firstIndex(of: "cache") else { continue }
            let marketplace = parts.count > cacheIdx + 1 ? parts[cacheIdx + 1] : "unknown"
            let plugin = parts.count > cacheIdx + 2 ? parts[cacheIdx + 2] : marketplace

            let stem = url.deletingPathExtension().lastPathComponent
            if stem.uppercased() == "README" || stem.uppercased() == "LICENSE" { continue }

            if let handle = readHandle(
                from: url,
                scope: .plugin(marketplace: marketplace, pluginName: plugin)
            ) {
                out.append(handle)
            }
        }
        return out
    }

    nonisolated private static func readHandle(from url: URL, scope: AgentHandle.Scope) -> AgentHandle? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let doc = FrontmatterDocument<AgentFrontmatter>(raw: raw)
        let fallbackName = url.deletingPathExtension().lastPathComponent
        return AgentHandle(
            id: url.path,
            name: doc.schema.name.isEmpty ? fallbackName : doc.schema.name,
            description: String(doc.schema.description.prefix(160)),
            url: url,
            scope: scope
        )
    }
}
