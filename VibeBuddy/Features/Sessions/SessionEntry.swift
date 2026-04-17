import Foundation

/// Typed view of one line in a session jsonl file. Metadata-only line types
/// (permission-mode, last-prompt, file-history-snapshot, progress) never reach
/// this enum — they are dropped at decode time.
struct SessionEntry: Identifiable, Hashable, Sendable {
    let id: String
    let kind: Kind
    let timestamp: Date?

    enum Kind: Hashable, Sendable {
        case userText(String)
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
    case text(String)
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
