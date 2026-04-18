import Foundation
import Testing
@testable import VibeBuddy

@Suite("AgentFrontmatter")
struct AgentFrontmatterTests {

    @Test("parses the canonical three-field shape")
    func parsesCanonical() {
        let source = """
        ---
        name: code-reviewer
        description: Elite code review expert.
        model: opus
        ---
        You are an elite code reviewer.
        """
        let doc = FrontmatterDocument<AgentFrontmatter>(raw: source)
        #expect(doc.schema.name == "code-reviewer")
        #expect(doc.schema.description == "Elite code review expert.")
        #expect(doc.schema.model == "opus")
        #expect(doc.schema.extras.isEmpty)
        #expect(doc.body == "You are an elite code reviewer.")
    }

    @Test("round-trip preserves unknown keys after known ones")
    func preservesUnknownKeys() {
        let source = """
        ---
        name: x
        description: y
        model: opus
        tools:
          - Read
          - Edit
        color: blue
        ---
        body
        """
        let doc = FrontmatterDocument<AgentFrontmatter>(raw: source)
        #expect(doc.schema.extras.list("tools") == ["Read", "Edit"])
        #expect(doc.schema.extras.scalar("color") == "blue")

        let emitted = doc.serialized()
        let reparsed = FrontmatterDocument<AgentFrontmatter>(raw: emitted)
        #expect(reparsed.schema == doc.schema)
        #expect(reparsed.body == "body")
    }

    @Test("omits model field when nil or empty on emit")
    func omitsEmptyModel() {
        let agent = AgentFrontmatter(
            name: "x",
            description: "desc",
            model: nil,
            extras: []
        )
        let doc = FrontmatterDocument<AgentFrontmatter>(schema: agent, body: "b")
        let out = doc.serialized()
        #expect(out.contains("model") == false)
    }

    @Test("missing frontmatter yields empty schema")
    func missingFrontmatterGivesEmpty() {
        let doc = FrontmatterDocument<AgentFrontmatter>(raw: "just a body")
        #expect(doc.schema == .empty)
        #expect(doc.body == "just a body")
    }
}
