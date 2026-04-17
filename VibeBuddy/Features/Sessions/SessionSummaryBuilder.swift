import Foundation

/// Streams a single `*.jsonl` session file once and produces a
/// `SessionSummary`. Ignores unknown `type` values and malformed lines so a
/// single bad record never kills a whole project's list.
struct SessionSummaryBuilder: Sendable {

    /// Builds a summary, or returns `nil` if the file had nothing useful
    /// (no user/assistant lines and no cwd). Throws only on hard IO errors;
    /// parse errors per line are swallowed and the line is skipped.
    func build(from url: URL, slug: String) throws -> SessionSummary? {
        var firstPrompt: String?
        var cwd: String?
        var gitBranch: String?
        var claudeVersion: String?
        var lastTimestamp: Date?
        var messageCount = 0

        try JSONLReader(url: url).forEachLine { line in
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                return
            }

            if cwd == nil, let v = obj["cwd"] as? String, !v.isEmpty {
                cwd = v
            }
            if gitBranch == nil, let v = obj["gitBranch"] as? String, !v.isEmpty {
                gitBranch = v
            }
            if let v = obj["version"] as? String, !v.isEmpty {
                claudeVersion = v
            }
            if let ts = obj["timestamp"] as? String, let parsed = ISO8601Tolerant.parse(ts) {
                lastTimestamp = parsed
            }

            switch obj["type"] as? String {
            case "user":
                messageCount += 1
                if firstPrompt == nil,
                   let msg = obj["message"] as? [String: Any],
                   let content = msg["content"] as? String,
                   !content.isEmpty {
                    firstPrompt = String(content.prefix(120))
                }
            case "assistant":
                messageCount += 1
            default:
                break
            }
        }

        guard messageCount > 0 || cwd != nil else { return nil }

        let id = url.deletingPathExtension().lastPathComponent
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let lastActivity = mtime ?? lastTimestamp ?? .distantPast

        return SessionSummary(
            id: id,
            path: url,
            projectPath: cwd ?? slug,
            projectSlug: slug,
            firstPrompt: firstPrompt,
            messageCount: messageCount,
            lastActivity: lastActivity,
            claudeVersion: claudeVersion,
            gitBranch: gitBranch
        )
    }
}
