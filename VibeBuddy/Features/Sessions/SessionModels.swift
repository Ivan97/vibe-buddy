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

    /// True when the jsonl's tail implies Claude owes a reply:
    ///  - last non-meta line is `type=user` (AI yet to respond), OR
    ///  - last `type=assistant` line's `stop_reason` isn't `"end_turn"`
    ///    (tool_use, max_tokens, missing stop_reason all qualify).
    /// Meta lines (`summary`, `system`, attachments, …) are ignored so a
    /// trailing hook artifact doesn't flip the flag. Paired with the mtime
    /// check in `isWorking` to rule out sessions that crashed mid-turn.
    let inProgress: Bool

    /// Mtime window used by `isLive`. Stays forgiving enough to cover
    /// brief idle periods between turns, short enough that a Claude Code
    /// window closed 10+ minutes ago doesn't keep showing a green dot.
    static let defaultLivenessThreshold: TimeInterval = 5 * 60

    /// `true` when the session *window* is still alive — i.e. Claude Code
    /// hasn't quit. There's no explicit "quit" marker in the jsonl, so we
    /// treat recent file mtime as the proxy: Claude Code writes on every
    /// turn, hook fire, summary, etc., so a session whose file has gone
    /// quiet for `threshold` seconds is almost certainly closed.
    ///
    /// This is a separate signal from `inProgress` / `isWorking`: an
    /// open-but-idle session is still "live" (green dot) but not
    /// "working" (no pulse animation).
    func isLive(
        now: Date = Date(),
        threshold: TimeInterval = SessionSummary.defaultLivenessThreshold
    ) -> Bool {
        now.timeIntervalSince(lastActivity) < threshold
    }

    /// AI is actively generating a response right now. Requires the
    /// session to be alive AND the tail to signal a pending turn.
    /// The mtime gate filters out sessions that got stuck mid-turn when
    /// Claude Code crashed — `inProgress` stays true on disk forever in
    /// that case, but the session isn't actually working.
    func isWorking(
        now: Date = Date(),
        threshold: TimeInterval = SessionSummary.defaultLivenessThreshold
    ) -> Bool {
        inProgress && isLive(now: now, threshold: threshold)
    }
}
