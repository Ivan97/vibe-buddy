import Foundation

/// Per-session summary built from a single `*.jsonl` file under
/// `~/.claude/projects/<slug>/`. Contains enough metadata for list rendering
/// without having to parse the full transcript.
struct SessionSummary: Identifiable, Hashable, Sendable {
    let id: String               // file name stem (session uuid)
    let path: URL                // absolute path to the jsonl file
    let projectPath: String      // real cwd from the first user/assistant line (authoritative)
    let projectSlug: String      // directory name — ambiguous encoding of path, kept as fallback
    let firstPrompt: String?     // first user-text content, truncated
    let messageCount: Int        // user + assistant lines (incl. tool_result user turns)
    let lastActivity: Date       // file mtime, falling back to last seen timestamp
    let claudeVersion: String?   // last `version` field observed in the file
    let gitBranch: String?       // first `gitBranch` field observed

    /// Default window for treating a session as "live" — mtime within the
    /// last 5 minutes. Short enough that only truly-active sessions get the
    /// indicator; forgiving enough to cover brief idle periods mid-turn.
    static let defaultLivenessThreshold: TimeInterval = 5 * 60

    func isLive(
        now: Date = Date(),
        threshold: TimeInterval = SessionSummary.defaultLivenessThreshold
    ) -> Bool {
        now.timeIntervalSince(lastActivity) < threshold
    }
}
