import Foundation

/// Frontmatter schema for `SKILL.md` files. Observed across 241 on-disk
/// samples: `description` (100 %), `name` (99 %), `license` (46 %). Everything
/// else is stashed in `extras` so niche plugin fields (category, parent,
/// disable-model-invocation, metadata, …) round-trip unchanged.
struct SkillFrontmatter: FrontmatterSchema {
    var name: String
    var description: String
    var license: String?
    var extras: FrontmatterMap

    static let empty = SkillFrontmatter(
        name: "",
        description: "",
        license: nil,
        extras: []
    )

    static let ownedKeys: Set<String> = ["name", "description", "license"]

    init(name: String, description: String, license: String?, extras: FrontmatterMap) {
        self.name = name
        self.description = description
        self.license = license
        self.extras = extras
    }

    init(from map: FrontmatterMap) {
        self.name = map.scalar("name") ?? ""
        self.description = map.scalar("description") ?? ""
        self.license = map.scalar("license")
        self.extras = map.without(Self.ownedKeys)
    }

    func toMap() -> FrontmatterMap {
        var out: FrontmatterMap = []
        out.append((key: "name", value: .scalar(name)))
        out.append((key: "description", value: .scalar(description)))
        if let license, !license.isEmpty {
            out.append((key: "license", value: .scalar(license)))
        }
        out.append(contentsOf: extras)
        return out
    }

    static func == (lhs: SkillFrontmatter, rhs: SkillFrontmatter) -> Bool {
        lhs.name == rhs.name
            && lhs.description == rhs.description
            && lhs.license == rhs.license
            && FrontmatterMap.isEqual(lhs.extras, rhs.extras)
    }
}
