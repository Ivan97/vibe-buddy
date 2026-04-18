import Foundation

@MainActor
final class SkillStore: ObservableObject {
    @Published private(set) var handles: [SkillHandle] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

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
}
