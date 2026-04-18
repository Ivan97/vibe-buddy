import Foundation
import Testing
@testable import VibeBuddy

@Suite("CommandFrontmatter")
struct CommandFrontmatterTests {

    @Test("parses all three known fields")
    func parsesKnownFields() {
        let source = """
        ---
        description: Code review a pull request
        argument-hint: "[pr-number]"
        allowed-tools: "Bash(gh pr diff:*), Bash(gh pr view:*)"
        ---
        body
        """
        let doc = FrontmatterDocument<CommandFrontmatter>(raw: source)
        #expect(doc.schema.description == "Code review a pull request")
        #expect(doc.schema.argumentHint == "[pr-number]")
        #expect(doc.schema.allowedTools?.contains("gh pr diff") == true)
    }

    @Test("missing frontmatter yields an empty schema + keeps body")
    func noFrontmatter() {
        let source = "Just a body with no frontmatter.\n"
        let doc = FrontmatterDocument<CommandFrontmatter>(raw: source)
        #expect(doc.schema == .empty)
        #expect(doc.body == "Just a body with no frontmatter.\n")
    }

    @Test("unknown keys round-trip through extras")
    func extrasRoundTrip() {
        let source = """
        ---
        description: x
        command: /x
        disable-model-invocation: "false"
        ---
        """
        let doc = FrontmatterDocument<CommandFrontmatter>(raw: source)
        #expect(doc.schema.extras.scalar("command") == "/x")
        #expect(doc.schema.extras.scalar("disable-model-invocation") == "false")

        let reparsed = FrontmatterDocument<CommandFrontmatter>(raw: doc.serialized())
        #expect(reparsed.schema == doc.schema)
    }

    @Test("empty strings clear owned fields on emit")
    func emptyStringsOmitted() {
        let cmd = CommandFrontmatter(description: "", argumentHint: "", allowedTools: "", extras: [])
        let doc = FrontmatterDocument<CommandFrontmatter>(schema: cmd, body: "x")
        let out = doc.serialized()
        #expect(out.contains("description") == false)
        #expect(out.contains("argument-hint") == false)
        #expect(out.contains("allowed-tools") == false)
    }
}
