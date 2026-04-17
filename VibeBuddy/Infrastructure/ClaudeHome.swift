import Foundation

/// Pointer to the Claude Code config directory on disk.
///
/// Honors the `CLAUDE_CONFIG_DIR` environment variable (same mechanism
/// used by the Claude Code CLI) and otherwise falls back to `~/.claude`.
struct ClaudeHome: Sendable, Equatable {
    let url: URL

    var projectsDir: URL { url.appending(path: "projects", directoryHint: .isDirectory) }
    var settingsFile: URL { url.appending(path: "settings.json") }
    var commandsDir: URL { url.appending(path: "commands", directoryHint: .isDirectory) }
    var agentsDir: URL { url.appending(path: "agents", directoryHint: .isDirectory) }
    var skillsDir: URL { url.appending(path: "skills", directoryHint: .isDirectory) }
    var pluginsDir: URL { url.appending(path: "plugins", directoryHint: .isDirectory) }

    static let envOverrideKey = "CLAUDE_CONFIG_DIR"

    /// Resolves the effective config directory from the environment and home
    /// directory. Pure function — does not touch disk. Callers can inject
    /// fakes in tests by passing custom `environment` / `homeDirectory`.
    static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> ClaudeHome {
        if let override = environment[envOverrideKey], !override.isEmpty {
            return ClaudeHome(url: URL(fileURLWithPath: override, isDirectory: true))
        }
        return ClaudeHome(
            url: homeDirectory.appending(path: ".claude", directoryHint: .isDirectory)
        )
    }
}
