import Foundation

/// Parses one jsonl line into a `SessionEntry`. Unknown top-level `type`
/// values surface as `.unknown` so new Claude Code versions can still render.
/// Metadata-only lines (`permission-mode`, `last-prompt`,
/// `file-history-snapshot`, `progress`) return `nil` and are dropped from the
/// transcript.
struct SessionEntryDecoder: Sendable {

    func decode(_ raw: Data) -> SessionEntry? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
            let type = obj["type"] as? String
        else {
            return nil
        }

        let id = (obj["uuid"] as? String)
            ?? (obj["messageId"] as? String)
            ?? UUID().uuidString
        let timestamp = (obj["timestamp"] as? String).flatMap(ISO8601Tolerant.parse)

        switch type {
        case "permission-mode", "last-prompt", "file-history-snapshot", "progress":
            return nil

        case "user":
            guard let kind = decodeUser(obj) else {
                return SessionEntry(id: id, kind: .unknown(type: type), timestamp: timestamp)
            }
            return SessionEntry(id: id, kind: kind, timestamp: timestamp)

        case "assistant":
            guard let kind = decodeAssistant(obj) else {
                return SessionEntry(id: id, kind: .unknown(type: type), timestamp: timestamp)
            }
            return SessionEntry(id: id, kind: kind, timestamp: timestamp)

        case "system":
            return SessionEntry(id: id, kind: decodeSystem(obj), timestamp: timestamp)

        case "attachment":
            return SessionEntry(id: id, kind: decodeAttachment(obj), timestamp: timestamp)

        default:
            return SessionEntry(id: id, kind: .unknown(type: type), timestamp: timestamp)
        }
    }

    // MARK: - user

    private func decodeUser(_ obj: [String: Any]) -> SessionEntry.Kind? {
        guard let message = obj["message"] as? [String: Any] else { return nil }

        if let text = message["content"] as? String {
            return .userText(RichText(raw: text))
        }

        guard let blocks = message["content"] as? [[String: Any]] else { return nil }

        var texts: [String] = []
        var toolResults: [ToolResult] = []

        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let t = block["text"] as? String { texts.append(t) }
            case "tool_result":
                let id = block["tool_use_id"] as? String ?? ""
                let isError = (block["is_error"] as? Bool) ?? false
                let content: String
                if let s = block["content"] as? String {
                    content = s
                } else if let arr = block["content"] as? [[String: Any]] {
                    content = arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
                } else {
                    content = ""
                }
                toolResults.append(ToolResult(toolUseId: id, isError: isError, content: content))
            default:
                break
            }
        }

        if !toolResults.isEmpty, texts.isEmpty {
            return .userToolResults(toolResults)
        }
        if !texts.isEmpty, toolResults.isEmpty {
            return .userText(RichText(raw: texts.joined(separator: "\n\n")))
        }
        if !toolResults.isEmpty {
            // Mixed (rare). Surface tool results; text fragments get dropped.
            return .userToolResults(toolResults)
        }
        return nil
    }

    // MARK: - assistant

    private func decodeAssistant(_ obj: [String: Any]) -> SessionEntry.Kind? {
        guard
            let message = obj["message"] as? [String: Any],
            let blocks = message["content"] as? [[String: Any]]
        else { return nil }

        var out: [AssistantBlock] = []
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let t = block["text"] as? String { out.append(.text(RichText(raw: t))) }
            case "thinking":
                if let t = block["thinking"] as? String { out.append(.thinking(t)) }
            case "tool_use":
                let id = block["id"] as? String ?? ""
                let name = block["name"] as? String ?? "?"
                let preview = formatToolInput(block["input"])
                out.append(.toolUse(id: id, name: name, inputPreview: preview))
            default:
                break
            }
        }

        return .assistantTurn(
            blocks: out,
            model: message["model"] as? String,
            stopReason: message["stop_reason"] as? String,
            usage: decodeUsage(message["usage"] as? [String: Any])
        )
    }

    private func decodeUsage(_ dict: [String: Any]?) -> Usage? {
        guard let dict else { return nil }
        return Usage(
            inputTokens: (dict["input_tokens"] as? Int) ?? 0,
            outputTokens: (dict["output_tokens"] as? Int) ?? 0,
            cacheReadTokens: (dict["cache_read_input_tokens"] as? Int) ?? 0,
            cacheCreationTokens: (dict["cache_creation_input_tokens"] as? Int) ?? 0
        )
    }

    // MARK: - system & attachment

    private func decodeSystem(_ obj: [String: Any]) -> SessionEntry.Kind {
        let subtype = (obj["subtype"] as? String) ?? "system"
        let summary: String
        switch subtype {
        case "stop_hook_summary":
            let count = obj["hookCount"] as? Int ?? 0
            summary = "Stop hooks ran (\(count))"
        case "turn_duration":
            if let ms = obj["durationMs"] as? Int {
                summary = "Turn took \(ms) ms"
            } else {
                summary = "Turn duration"
            }
        default:
            summary = subtype
        }
        return .systemNote(subtype: subtype, summary: summary)
    }

    private func decodeAttachment(_ obj: [String: Any]) -> SessionEntry.Kind {
        let att = (obj["attachment"] as? [String: Any]) ?? [:]
        let subtype = (att["type"] as? String) ?? "attachment"
        let summary: String

        switch subtype {
        case "hook_success":
            let hookName = (att["hookName"] as? String) ?? "?"
            let cmd = (att["command"] as? String) ?? ""
            let code = (att["exitCode"] as? Int) ?? 0
            summary = "Hook \(hookName) · exit \(code)" + (cmd.isEmpty ? "" : " — \(cmd)")

        case "hook_system_message", "hook_additional_context":
            let content = (att["content"] as? String) ?? ""
            let preview = content.prefix(120)
            summary = String(preview) + (content.count > 120 ? "…" : "")

        case "hook_permission_decision":
            let decision = (att["decision"] as? String) ?? "?"
            summary = "Permission decision: \(decision)"

        case "skill_listing":
            let count = att["skillCount"] as? Int ?? 0
            summary = "Skill listing (\(count) skills)"

        case "deferred_tools_delta":
            let added = (att["addedNames"] as? [String])?.count ?? 0
            let removed = (att["removedNames"] as? [String])?.count ?? 0
            summary = "Deferred tools: +\(added) / -\(removed)"

        case "mcp_instructions_delta":
            let added = (att["addedNames"] as? [String])?.count ?? 0
            summary = "MCP instructions: +\(added)"

        case "task_reminder":
            summary = "Task reminder (\(att["itemCount"] as? Int ?? 0))"

        default:
            summary = subtype
        }
        return .attachment(subtype: subtype, summary: summary)
    }

    // MARK: - helpers

    private func formatToolInput(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return s }
        if JSONSerialization.isValidJSONObject(value) {
            if let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.prettyPrinted, .sortedKeys]
            ), let str = String(data: data, encoding: .utf8) {
                return str
            }
        }
        return String(describing: value)
    }
}
