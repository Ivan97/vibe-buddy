import Foundation

/// Parse / serialize the `hooks` field from `settings.json`.
///
/// The raw on-disk shape (verified against `~/.claude/settings.json`) is:
///
/// ```json
/// "hooks": {
///   "PreToolUse": [
///     { "matcher": "*", "hooks": [{ "type": "command", "command": "...", "timeout": 15 }] }
///   ],
///   ...
/// }
/// ```
enum HooksCodec {

    /// Parses the raw object — permissive by design. Missing / malformed
    /// pieces degrade to empty lists rather than aborting the load.
    static func parse(_ any: Any?) -> HooksConfig {
        guard let dict = any as? [String: Any] else { return .empty }

        // Preserve the event ordering Claude Code put on disk so a
        // serialize-back with no edits produces a stable diff.
        let knownOrder = HookEventKind.allCases.map(\.rawValue)
        let keys = dict.keys
        let sortedKeys = keys.sorted { lhs, rhs in
            let li = knownOrder.firstIndex(of: lhs) ?? Int.max
            let ri = knownOrder.firstIndex(of: rhs) ?? Int.max
            if li != ri { return li < ri }
            return lhs < rhs
        }

        var events: [HookEvent] = []
        for key in sortedKeys {
            guard let groups = dict[key] as? [[String: Any]] else { continue }
            let matchers = groups.compactMap(parseMatcherGroup(_:))
            events.append(HookEvent(name: key, matchers: matchers))
        }
        return HooksConfig(events: events)
    }

    static func toJSON(_ config: HooksConfig) -> [String: Any] {
        var out: [String: Any] = [:]
        for event in config.events {
            out[event.name] = event.matchers.map { matcherGroupToJSON($0) }
        }
        return out
    }

    // MARK: - group

    private static func parseMatcherGroup(_ obj: [String: Any]) -> HookMatcherGroup? {
        // Claude Code writes an explicit "hooks" array of objects; skip
        // silently when malformed rather than losing the group on save.
        let matcher = obj["matcher"] as? String
        let rawCommands = obj["hooks"] as? [[String: Any]] ?? []
        let commands = rawCommands.compactMap(parseCommand(_:))
        return HookMatcherGroup(matcher: matcher, commands: commands)
    }

    private static func matcherGroupToJSON(_ group: HookMatcherGroup) -> [String: Any] {
        var out: [String: Any] = ["hooks": group.commands.map { commandToJSON($0) }]
        if let matcher = group.matcher, !matcher.isEmpty {
            out["matcher"] = matcher
        }
        return out
    }

    // MARK: - command

    private static func parseCommand(_ obj: [String: Any]) -> HookCommand? {
        guard let command = obj["command"] as? String else { return nil }
        let type = (obj["type"] as? String) ?? "command"
        let timeout = obj["timeout"] as? Int
        var extras: [String: String] = [:]
        for (key, value) in obj where !["type", "command", "timeout"].contains(key) {
            if let s = value as? String { extras[key] = s }
        }
        return HookCommand(type: type, command: command, timeout: timeout, extras: extras)
    }

    private static func commandToJSON(_ cmd: HookCommand) -> [String: Any] {
        var out: [String: Any] = [
            "type": cmd.type,
            "command": cmd.command
        ]
        if let timeout = cmd.timeout {
            out["timeout"] = timeout
        }
        for (k, v) in cmd.extras {
            out[k] = v
        }
        return out
    }
}
