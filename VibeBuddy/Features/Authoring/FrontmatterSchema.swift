import Foundation

/// Anything that can round-trip through a `FrontmatterMap`. Concrete schemas
/// live next to their feature (`AgentFrontmatter`, later
/// `CommandFrontmatter`, `SkillFrontmatter`) and own their own editable
/// fields — but they must preserve any unknown keys they don't understand
/// so a user's custom fields survive a save.
protocol FrontmatterSchema: Equatable, Sendable {
    init(from map: FrontmatterMap)
    func toMap() -> FrontmatterMap
    static var empty: Self { get }
}

/// A parsed markdown document paired with a typed view of its frontmatter.
struct FrontmatterDocument<Schema: FrontmatterSchema>: Equatable, Sendable {
    var schema: Schema
    var body: String

    init(schema: Schema, body: String) {
        self.schema = schema
        self.body = body
    }

    init(raw source: String) {
        let parsed = FrontmatterCodec.parse(source)
        self.schema = Schema(from: parsed.frontmatter)
        self.body = parsed.body
    }

    func serialized() -> String {
        let raw = FrontmatterDocumentRaw(frontmatter: schema.toMap(), body: body)
        return FrontmatterCodec.serialize(raw)
    }
}
