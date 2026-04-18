import Foundation

/// Frontmatter schema for files under `~/.claude/agents/` (and the
/// project-scoped equivalent). Mirrors the shape consistently produced by
/// Claude Code across 83 sampled agents: three named fields plus a slot
/// for unknown keys that shouldn't be dropped on save.
struct AgentFrontmatter: FrontmatterSchema {
    var name: String
    var description: String
    var model: String?
    /// Keys not recognized by this schema — preserved verbatim through
    /// round-trip so user-authored fields (e.g. `tools`, `color`,
    /// `temperature`) aren't silently erased.
    var extras: FrontmatterMap

    static let empty = AgentFrontmatter(name: "", description: "", model: nil, extras: [])

    /// Fields this schema claims as its own; everything else goes into
    /// `extras` on parse and is re-emitted after the known fields on save.
    static let ownedKeys: Set<String> = ["name", "description", "model"]

    init(
        name: String,
        description: String,
        model: String?,
        extras: FrontmatterMap
    ) {
        self.name = name
        self.description = description
        self.model = model
        self.extras = extras
    }

    init(from map: FrontmatterMap) {
        self.name = map.scalar("name") ?? ""
        self.description = map.scalar("description") ?? ""
        self.model = map.scalar("model")
        self.extras = map.without(Self.ownedKeys)
    }

    func toMap() -> FrontmatterMap {
        var out: FrontmatterMap = []
        out.append((key: "name", value: .scalar(name)))
        out.append((key: "description", value: .scalar(description)))
        if let model, !model.isEmpty {
            out.append((key: "model", value: .scalar(model)))
        }
        out.append(contentsOf: extras)
        return out
    }

    static func == (lhs: AgentFrontmatter, rhs: AgentFrontmatter) -> Bool {
        lhs.name == rhs.name
            && lhs.description == rhs.description
            && lhs.model == rhs.model
            && FrontmatterMap.isEqual(lhs.extras, rhs.extras)
    }
}

extension Array where Element == (key: String, value: FrontmatterValue) {
    /// Free-function equality helper because `[(String, FrontmatterValue)]`
    /// can't synthesize `Equatable` on its own.
    static func isEqual(_ a: Self, _ b: Self) -> Bool {
        guard a.count == b.count else { return false }
        for (lhs, rhs) in zip(a, b) where lhs.key != rhs.key || lhs.value != rhs.value {
            return false
        }
        return true
    }
}
