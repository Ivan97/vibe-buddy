import Foundation
import Testing
@testable import VibeBuddy

@Suite("SkillFrontmatter")
struct SkillFrontmatterTests {

    @Test("parses canonical SKILL.md frontmatter")
    func parsesCanonical() {
        let source = """
        ---
        name: pdf
        description: Comprehensive PDF manipulation toolkit.
        license: Proprietary.
        ---
        body
        """
        let doc = FrontmatterDocument<SkillFrontmatter>(raw: source)
        #expect(doc.schema.name == "pdf")
        #expect(doc.schema.description == "Comprehensive PDF manipulation toolkit.")
        #expect(doc.schema.license == "Proprietary.")
        #expect(doc.schema.extras.isEmpty)
        #expect(doc.body == "body")
    }

    @Test("preserves plugin-specific extras through round-trip")
    func preservesExtras() {
        let source = """
        ---
        name: agent-skills:example
        description: An example from a plugin bundle.
        license: MIT
        category: productivity
        disable-model-invocation: "false"
        parent: agent-skills
        metadata: "{version: 1}"
        ---
        body
        """
        let doc = FrontmatterDocument<SkillFrontmatter>(raw: source)
        #expect(doc.schema.extras.scalar("category") == "productivity")
        #expect(doc.schema.extras.scalar("disable-model-invocation") == "false")
        #expect(doc.schema.extras.scalar("parent") == "agent-skills")

        let reparsed = FrontmatterDocument<SkillFrontmatter>(raw: doc.serialized())
        #expect(reparsed.schema == doc.schema)
    }

    @Test("omits license when nil or empty on emit")
    func omitsEmptyLicense() {
        let skill = SkillFrontmatter(
            name: "x",
            description: "y",
            license: nil,
            extras: []
        )
        let doc = FrontmatterDocument<SkillFrontmatter>(schema: skill, body: "")
        #expect(doc.serialized().contains("license") == false)
    }
}
