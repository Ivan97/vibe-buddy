import Foundation

@MainActor
final class SkillStore: ObservableObject {
    @Published private(set) var handles: [SkillHandle] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    /// Upstream status for `userSymlink`-scope skills only. User-authored
    /// skills have no upstream; plugin-scope skills piggy-back on
    /// `PluginsStore.status(for:)` — the list view composes both sources.
    @Published private(set) var updateStatus: [SkillHandle.ID: GitUpdateChecker.Status] = [:]
    @Published private(set) var isCheckingUpdates: Bool = false

    let claudeHome: ClaudeHome
    private let classifier: SkillClassifier
    private var userWatcher: DirectoryWatcher?
    private var debounceTask: Task<Void, Never>?

    init(
        claudeHome: ClaudeHome = .discover(),
        classifier: SkillClassifier = SkillClassifier()
    ) {
        self.claudeHome = claudeHome
        self.classifier = classifier
    }

    deinit { userWatcher?.stop() }

    // MARK: - read

    func reload() async {
        isLoading = true
        loadError = nil
        let skillsDir = claudeHome.skillsDir
        let pluginsDir = claudeHome.pluginsDir
        let classifier = self.classifier

        let result = await Task.detached(priority: .userInitiated) {
            classifier.scan(userSkillsDir: skillsDir, pluginsDir: pluginsDir)
        }.value

        isLoading = false
        handles = result
    }

    func load(_ handle: SkillHandle) throws -> FrontmatterDocument<SkillFrontmatter> {
        let raw = try String(contentsOf: handle.skillMdURL, encoding: .utf8)
        return FrontmatterDocument<SkillFrontmatter>(raw: raw)
    }

    // MARK: - write

    /// Saves the skill. Throws on plugin or malformed scopes; caller should
    /// gate the UI to avoid reaching here in those cases.
    @discardableResult
    func save(
        _ document: FrontmatterDocument<SkillFrontmatter>,
        to handle: SkillHandle
    ) throws -> SkillHandle {
        guard handle.isEditable else {
            throw NSError(
                domain: "VibeBuddy.SkillStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This skill is read-only in its current scope."]
            )
        }

        try SafeTextWriter.write(document.serialized(), to: handle.skillMdURL)

        let refreshed = SkillHandle(
            id: handle.id,
            name: document.schema.name.isEmpty ? handle.displayURL.lastPathComponent : document.schema.name,
            description: String(document.schema.description.prefix(160)),
            displayURL: handle.displayURL,
            skillMdURL: handle.skillMdURL,
            scope: handle.scope
        )
        if let idx = handles.firstIndex(where: { $0.id == handle.id }) {
            handles[idx] = refreshed
        }
        return refreshed
    }

    /// Creates a SKILL.md for a malformed handle (empty directory). Used by
    /// the editor's "Create SKILL.md" action.
    func bootstrapSkillMd(at handle: SkillHandle) throws -> SkillHandle {
        guard case .malformed = handle.scope else {
            throw NSError(
                domain: "VibeBuddy.SkillStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Skill is already valid."]
            )
        }
        let dirURL = handle.displayURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(
                domain: "VibeBuddy.SkillStore",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Can only bootstrap inside a directory."]
            )
        }

        let defaultName = dirURL.lastPathComponent
        let schema = SkillFrontmatter(
            name: defaultName,
            description: "",
            license: nil,
            extras: []
        )
        let doc = FrontmatterDocument<SkillFrontmatter>(schema: schema, body: "")
        let skillMd = dirURL.appending(path: "SKILL.md")
        try SafeTextWriter.write(doc.serialized(), to: skillMd, makeBackup: false)

        let fixed = SkillHandle(
            id: skillMd.path,
            name: defaultName,
            description: "",
            displayURL: dirURL,
            skillMdURL: skillMd,
            scope: .user
        )
        if let idx = handles.firstIndex(where: { $0.id == handle.id }) {
            handles[idx] = fixed
        } else {
            handles.append(fixed)
        }
        return fixed
    }

    /// Creates a new user skill: directory + seeded SKILL.md.
    func create(name: String, description: String) throws -> SkillHandle {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "VibeBuddy.SkillStore",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty."]
            )
        }

        let dirURL = claudeHome.skillsDir.appending(path: trimmed, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: dirURL.path) {
            throw NSError(
                domain: "VibeBuddy.SkillStore",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "A skill named '\(trimmed)' already exists."]
            )
        }
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let schema = SkillFrontmatter(name: trimmed, description: description, license: nil, extras: [])
        let doc = FrontmatterDocument(schema: schema, body: "")
        let skillMd = dirURL.appending(path: "SKILL.md")
        try SafeTextWriter.write(doc.serialized(), to: skillMd, makeBackup: false)

        let handle = SkillHandle(
            id: skillMd.path,
            name: trimmed,
            description: description,
            displayURL: dirURL,
            skillMdURL: skillMd,
            scope: .user
        )
        handles.insert(handle, at: 0)
        return handle
    }

    func delete(_ handle: SkillHandle) throws {
        guard handle.isEditable else {
            throw NSError(
                domain: "VibeBuddy.SkillStore",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Cannot delete a plugin-provided or malformed skill from here."]
            )
        }
        // For user-owned skills we remove the directory; for symlinks we only
        // remove the link so the source bundle is untouched.
        if case .userSymlink = handle.scope {
            try FileManager.default.removeItem(at: handle.displayURL)
        } else {
            try FileManager.default.removeItem(at: handle.displayURL)
        }
        handles.removeAll { $0.id == handle.id }
    }

    // MARK: - watch

    func startWatching() {
        guard userWatcher == nil else { return }
        let dir = claudeHome.skillsDir
        let w = DirectoryWatcher(url: dir) { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        w.start()
        userWatcher = w
    }

    func stopWatching() {
        userWatcher?.stop()
        userWatcher = nil
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

    /// Status for a symlinked skill. Plugin-scope skills aren't stored
    /// here — callers read those from `PluginsStore` keyed by pluginID.
    func status(for handleID: SkillHandle.ID) -> GitUpdateChecker.Status {
        updateStatus[handleID] ?? .unchecked
    }

    /// Resolves a `userSymlink` handle's target to its enclosing git repo
    /// and runs an update check. No-op for other scopes.
    func checkForUpdate(_ handleID: SkillHandle.ID) async {
        guard let handle = handles.first(where: { $0.id == handleID }),
              case .userSymlink(let target) = handle.scope else { return }
        guard let root = GitUpdateChecker.findRepoRoot(startingFrom: target) else {
            updateStatus[handleID] = .notTracked
            return
        }
        updateStatus[handleID] = .checking
        updateStatus[handleID] = await GitUpdateChecker.check(repoRoot: root)
    }

    /// Bulk-check every `userSymlink` skill. Like the plugin variant,
    /// capped at 4 concurrent git calls.
    func checkAllForUpdates() async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        let targets: [(id: SkillHandle.ID, root: URL)] = handles.compactMap { handle in
            guard case .userSymlink(let target) = handle.scope else { return nil }
            guard let root = GitUpdateChecker.findRepoRoot(startingFrom: target) else {
                return nil
            }
            return (handle.id, root)
        }
        // Seed statuses so the UI flips to 'checking' / 'notTracked'
        // immediately — the async results backfill progressively.
        for handle in handles {
            guard case .userSymlink(let target) = handle.scope else { continue }
            if GitUpdateChecker.findRepoRoot(startingFrom: target) == nil {
                updateStatus[handle.id] = .notTracked
            } else {
                updateStatus[handle.id] = .checking
            }
        }

        await withTaskGroup(of: (SkillHandle.ID, GitUpdateChecker.Status).self) { group in
            var inFlight = 0
            var iterator = targets.makeIterator()
            let limit = 4

            func enqueueNext() {
                guard let next = iterator.next() else { return }
                group.addTask {
                    (next.id, await GitUpdateChecker.check(repoRoot: next.root))
                }
                inFlight += 1
            }

            for _ in 0..<min(limit, targets.count) { enqueueNext() }

            while inFlight > 0 {
                if let result = await group.next() {
                    updateStatus[result.0] = result.1
                    inFlight -= 1
                    enqueueNext()
                }
            }
        }
    }
}
