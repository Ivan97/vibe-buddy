import Foundation

/// Frontmatter for a Claude Code slash command (`~/.claude/commands/*.md`
/// and plugin-provided `<plugin>/commands/*.md`). Observed in the wild:
/// most commands ship with no frontmatter at all, so every claimed field
/// is optional. `allowed-tools` uses a rich syntax like
/// `Bash(gh pr diff:*)` — kept as a raw string for editing.
struct CommandFrontmatter: FrontmatterSchema {
    var description: String?
    var argumentHint: String?
    var allowedTools: String?
    var extras: FrontmatterMap

    static let empty = CommandFrontmatter(
        description: nil,
        argumentHint: nil,
        allowedTools: nil,
        extras: []
    )

    static let ownedKeys: Set<String> = ["description", "argument-hint", "allowed-tools"]

    init(
        description: String?,
        argumentHint: String?,
        allowedTools: String?,
        extras: FrontmatterMap
    ) {
        self.description = description
        self.argumentHint = argumentHint
        self.allowedTools = allowedTools
        self.extras = extras
    }

    init(from map: FrontmatterMap) {
        self.description = Self.nonEmpty(map.scalar("description"))
        self.argumentHint = Self.nonEmpty(map.scalar("argument-hint"))
        self.allowedTools = Self.nonEmpty(map.scalar("allowed-tools"))
        self.extras = map.without(Self.ownedKeys)
    }

    func toMap() -> FrontmatterMap {
        var out: FrontmatterMap = []
        if let description, !description.isEmpty {
            out.append((key: "description", value: .scalar(description)))
        }
        if let argumentHint, !argumentHint.isEmpty {
            out.append((key: "argument-hint", value: .scalar(argumentHint)))
        }
        if let allowedTools, !allowedTools.isEmpty {
            out.append((key: "allowed-tools", value: .scalar(allowedTools)))
        }
        out.append(contentsOf: extras)
        return out
    }

    static func == (lhs: CommandFrontmatter, rhs: CommandFrontmatter) -> Bool {
        lhs.description == rhs.description
            && lhs.argumentHint == rhs.argumentHint
            && lhs.allowedTools == rhs.allowedTools
            && FrontmatterMap.isEqual(lhs.extras, rhs.extras)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
