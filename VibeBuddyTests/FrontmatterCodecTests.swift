import Foundation
import Testing
@testable import VibeBuddy

@Suite("FrontmatterCodec")
struct FrontmatterCodecTests {

    @Test("parses the common agent frontmatter shape")
    func parsesAgentSample() {
        let source = """
        ---
        name: code-reviewer
        description: Elite code review expert.
        model: opus
        ---

        You are an elite code reviewer.
        """
        let doc = FrontmatterCodec.parse(source)
        #expect(doc.frontmatter.scalar("name") == "code-reviewer")
        #expect(doc.frontmatter.scalar("description") == "Elite code review expert.")
        #expect(doc.frontmatter.scalar("model") == "opus")
        #expect(doc.body == "You are an elite code reviewer.")
    }

    @Test("no frontmatter fence → whole source is body")
    func noFrontmatter() {
        let source = "just a body\nwith two lines"
        let doc = FrontmatterCodec.parse(source)
        #expect(doc.frontmatter.isEmpty)
        #expect(doc.body == source)
    }

    @Test("preserves order of unknown keys")
    func preservesKeyOrder() {
        let source = """
        ---
        z-last: 1
        a-first: 2
        m-middle: 3
        ---
        body
        """
        let doc = FrontmatterCodec.parse(source)
        let keys = doc.frontmatter.map(\.key)
        #expect(keys == ["z-last", "a-first", "m-middle"])
    }

    @Test("decodes a simple string list")
    func simpleStringList() {
        let source = """
        ---
        allowed-tools:
          - Read
          - Edit
          - Bash
        ---
        body
        """
        let doc = FrontmatterCodec.parse(source)
        #expect(doc.frontmatter.list("allowed-tools") == ["Read", "Edit", "Bash"])
    }

    @Test("unquotes double-quoted scalars with escapes")
    func decodesQuotedStrings() {
        let source = """
        ---
        name: "has: a colon"
        raw: "line1\\nline2"
        ---
        """
        let doc = FrontmatterCodec.parse(source)
        #expect(doc.frontmatter.scalar("name") == "has: a colon")
        #expect(doc.frontmatter.scalar("raw") == "line1\nline2")
    }

    @Test("round-trip preserves the observed agent shape")
    func roundTripAgent() {
        let source = """
        ---
        name: code-reviewer
        description: Elite code review expert.
        model: opus
        ---

        Body line 1.
        Body line 2.
        """
        let parsed = FrontmatterCodec.parse(source)
        let emitted = FrontmatterCodec.serialize(parsed)
        let reparsed = FrontmatterCodec.parse(emitted)
        #expect(reparsed == parsed)
    }

    @Test("quotes values that would otherwise be ambiguous")
    func serializerQuotesSpecials() {
        let emitted = FrontmatterCodec.serialize(
            FrontmatterDocumentRaw(
                frontmatter: [
                    (key: "ambiguous", value: .scalar("has: colon-space")),
                    (key: "flag",      value: .scalar("- dash start")),
                ],
                body: ""
            )
        )
        #expect(emitted.contains("ambiguous: \"has: colon-space\""))
        #expect(emitted.contains("flag: \"- dash start\""))
    }

    @Test("empty frontmatter list renders as [] inline")
    func emptyListInline() {
        let emitted = FrontmatterCodec.serialize(
            FrontmatterDocumentRaw(
                frontmatter: [(key: "tools", value: .list([]))],
                body: "body"
            )
        )
        #expect(emitted.contains("tools: []"))
    }

    @Test("malformed closing fence falls back to no frontmatter")
    func malformedFenceFallsBack() {
        let source = """
        ---
        name: x
        (no closing fence)
        """
        let doc = FrontmatterCodec.parse(source)
        #expect(doc.frontmatter.isEmpty)
        #expect(doc.body == source)
    }

    @Test("BOM at start of file is tolerated")
    func tolerateBOM() {
        let source = "\u{FEFF}---\nname: x\n---\nbody"
        let doc = FrontmatterCodec.parse(source)
        #expect(doc.frontmatter.scalar("name") == "x")
        #expect(doc.body == "body")
    }
}
