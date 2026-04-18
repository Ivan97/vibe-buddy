import Foundation

/// User-defined titles for sessions. Keyed by the session's jsonl uuid.
/// Persisted in Application Support so it survives restarts without
/// touching Claude Code's own data under `~/.claude/`.
@MainActor
final class SessionTitleStore: ObservableObject {
    @Published private(set) var titles: [String: String] = [:]

    private let url: URL

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support")
        let appDir = support.appending(
            path: "tech.iooo.vibebuddy",
            directoryHint: .isDirectory
        )
        self.url = appDir.appending(path: "session-titles.json")

        try? FileManager.default.createDirectory(
            at: appDir,
            withIntermediateDirectories: true
        )
        load()
    }

    /// Returns the custom title for a session, or `nil` if the user hasn't
    /// overridden it.
    func customTitle(for sessionID: String) -> String? {
        titles[sessionID]
    }

    /// Sets a custom title. Passing `nil` or an empty string removes the
    /// override (the session falls back to its first-prompt preview).
    func setTitle(_ newTitle: String?, for sessionID: String) {
        let trimmed = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            titles[sessionID] = trimmed
        } else {
            titles.removeValue(forKey: sessionID)
        }
        persist()
    }

    // MARK: - persistence

    private func load() {
        guard
            FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        self.titles = decoded
    }

    private func persist() {
        guard
            let data = try? JSONEncoder().encode(titles),
            let text = String(data: data, encoding: .utf8)
        else { return }
        try? SafeTextWriter.write(text, to: url, makeBackup: false)
    }
}
