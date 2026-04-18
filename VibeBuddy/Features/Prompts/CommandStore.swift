import Foundation

@MainActor
final class CommandStore: ObservableObject {
    @Published private(set) var handles: [CommandHandle] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    let claudeHome: ClaudeHome
    private let scanner: CommandScanner
    private var watcher: DirectoryWatcher?
    private var debounceTask: Task<Void, Never>?

    init(
        claudeHome: ClaudeHome = .discover(),
        scanner: CommandScanner = CommandScanner()
    ) {
        self.claudeHome = claudeHome
        self.scanner = scanner
    }

    deinit { watcher?.stop() }

    // MARK: - read

    func reload() async {
        isLoading = true
        loadError = nil
        let userDir = claudeHome.commandsDir
        let pluginsDir = claudeHome.pluginsDir
        let scanner = self.scanner

        let result = await Task.detached(priority: .userInitiated) {
            scanner.scan(userCommandsDir: userDir, pluginsDir: pluginsDir)
        }.value

        isLoading = false
        handles = result
    }

    func load(_ handle: CommandHandle) throws -> FrontmatterDocument<CommandFrontmatter> {
        let raw = try String(contentsOf: handle.url, encoding: .utf8)
        return FrontmatterDocument<CommandFrontmatter>(raw: raw)
    }

    // MARK: - write

    @discardableResult
    func save(
        _ document: FrontmatterDocument<CommandFrontmatter>,
        to handle: CommandHandle
    ) throws -> CommandHandle {
        guard handle.isEditable else {
            throw NSError(
                domain: "VibeBuddy.CommandStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Plugin-provided commands are read-only."]
            )
        }
        try SafeTextWriter.write(document.serialized(), to: handle.url)
        return handle
    }

    /// Creates a new user command. Name can include `/` for subdir
    /// namespacing (e.g. `frontend/lint` → `commands/frontend/lint.md`).
    func create(
        name: String,
        description: String
    ) throws -> CommandHandle {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "VibeBuddy.CommandStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty."]
            )
        }

        // Split on '/' — last component becomes the filename stem, earlier
        // components become the subdirectory namespace.
        let parts = trimmed.split(separator: "/").map(String.init)
        guard !parts.isEmpty else {
            throw NSError(
                domain: "VibeBuddy.CommandStore",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid command name."]
            )
        }

        var dir = claudeHome.commandsDir
        for comp in parts.dropLast() {
            dir = dir.appending(path: comp, directoryHint: .isDirectory)
        }
        let fileName = "\(parts.last!).md"
        let url = dir.appending(path: fileName)

        if FileManager.default.fileExists(atPath: url.path) {
            throw NSError(
                domain: "VibeBuddy.CommandStore",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "A command at '\(trimmed)' already exists."]
            )
        }

        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )

        let schema = CommandFrontmatter(
            description: description.isEmpty ? nil : description,
            argumentHint: nil,
            allowedTools: nil,
            extras: []
        )
        let doc = FrontmatterDocument(schema: schema, body: "")
        try SafeTextWriter.write(doc.serialized(), to: url, makeBackup: false)

        let handle = CommandHandle(
            id: url.path,
            name: parts.last!,
            namespace: Array(parts.dropLast()),
            description: description,
            url: url,
            scope: .user
        )
        handles.insert(handle, at: 0)
        return handle
    }

    func delete(_ handle: CommandHandle) throws {
        guard handle.isEditable else {
            throw NSError(
                domain: "VibeBuddy.CommandStore",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Cannot delete a plugin-provided command."]
            )
        }
        try FileManager.default.removeItem(at: handle.url)
        handles.removeAll { $0.id == handle.id }
    }

    // MARK: - watch

    func startWatching() {
        guard watcher == nil else { return }
        let dir = claudeHome.commandsDir
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
