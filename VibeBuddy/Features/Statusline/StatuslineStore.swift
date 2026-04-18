import Foundation

/// Typed view of the `statusLine` field in `~/.claude/settings.json`.
/// Only the two known fields; anything Claude Code might add later lands
/// in `extras` and round-trips untouched.
struct StatuslineConfig: Equatable, Sendable {
    var type: String
    var command: String
    var extras: [String: String]

    static let empty = StatuslineConfig(type: "command", command: "", extras: [:])

    var isEmpty: Bool { command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

@MainActor
final class StatuslineStore: ObservableObject {
    @Published private(set) var config: StatuslineConfig = .empty
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

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
            self.config = Self.decode(dict["statusLine"])
        } catch {
            self.config = .empty
            self.loadError = (error as NSError).localizedDescription
        }
        isLoading = false
    }

    private static func decode(_ any: Any?) -> StatuslineConfig {
        guard let dict = any as? [String: Any] else { return .empty }
        var extras: [String: String] = [:]
        for (k, v) in dict where k != "type" && k != "command" {
            if let s = v as? String { extras[k] = s }
        }
        return StatuslineConfig(
            type: (dict["type"] as? String) ?? "command",
            command: (dict["command"] as? String) ?? "",
            extras: extras
        )
    }

    private static func encode(_ config: StatuslineConfig) -> [String: Any] {
        var out: [String: Any] = [
            "type": config.type,
            "command": config.command
        ]
        for (k, v) in config.extras {
            out[k] = v
        }
        return out
    }

    // MARK: - write

    func previewSave(_ updated: StatuslineConfig) throws -> (before: String, after: String) {
        let current = try settings.load()
        var next = current
        if updated.isEmpty {
            next.removeValue(forKey: "statusLine")
        } else {
            next["statusLine"] = Self.encode(updated)
        }
        let before = try SafeJSONStore.serializedString(current)
        let after = try SafeJSONStore.serializedString(next)
        return (before, after)
    }

    func commit(_ updated: StatuslineConfig) throws {
        var dict = try settings.load()
        if updated.isEmpty {
            dict.removeValue(forKey: "statusLine")
        } else {
            dict["statusLine"] = Self.encode(updated)
        }
        try settings.save(dict)
        config = updated
    }

    // MARK: - watch

    func startWatching() {
        guard watcher == nil else { return }
        let dir = claudeHome.settingsFile.deletingLastPathComponent()
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
