import Foundation

/// Plain text paired with an already-parsed `AttributedString`. Built once at
/// decode time so transcript rendering never re-parses markdown while the
/// user scrolls — a hot path that previously pegged CPU at 100 % with large
/// assistant turns.
struct RichText: Hashable, Sendable {
    let raw: String
    let markdown: AttributedString

    init(raw: String) {
        self.raw = raw
        let parsed = (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(raw)
        self.markdown = parsed
    }
}

/// Typed view of one line in a session jsonl file. Metadata-only line types
/// (permission-mode, last-prompt, file-history-snapshot, progress) never reach
/// this enum — they are dropped at decode time.
struct SessionEntry: Identifiable, Hashable, Sendable {
    let id: String
    let kind: Kind
    let timestamp: Date?

    enum Kind: Hashable, Sendable {
        case userText(RichText)
        case userToolResults([ToolResult])
        case assistantTurn(
            blocks: [AssistantBlock],
            model: String?,
            stopReason: String?,
            usage: Usage?
        )
        case systemNote(subtype: String, summary: String)
        case attachment(subtype: String, summary: String)
        case unknown(type: String)
    }
}

enum AssistantBlock: Hashable, Sendable {
    case text(RichText)
    case thinking(String)
    case toolUse(id: String, name: String, inputPreview: String)
}

struct ToolResult: Hashable, Sendable {
    let toolUseId: String
    let isError: Bool
    let content: String
}

struct Usage: Hashable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
}
