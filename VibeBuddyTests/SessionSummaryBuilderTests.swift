import Foundation
import Testing
@testable import VibeBuddy

@Suite("SessionSummaryBuilder")
struct SessionSummaryBuilderTests {

    @Test("extracts first prompt, cwd, version, and counts user + assistant lines")
    func basicParse() throws {
        let fixture = """
        {"type":"permission-mode","permissionMode":"default","sessionId":"s1"}
        {"type":"user","cwd":"/Users/alice/project","gitBranch":"main","timestamp":"2026-04-17T10:00:00.000Z","version":"2.1.112","message":{"role":"user","content":"Help me fix this bug"}}
        {"type":"assistant","cwd":"/Users/alice/project","timestamp":"2026-04-17T10:00:05.000Z","version":"2.1.112","message":{"role":"assistant","content":[{"type":"text","text":"Sure"}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
        {"type":"file-history-snapshot","snapshot":{}}
        """
        let url = try writeTempJSONL(fixture)
        let summary = try #require(
            try SessionSummaryBuilder().build(from: url, slug: "-Users-alice-project")
        )

        #expect(summary.firstPrompt == "Help me fix this bug")
        #expect(summary.projectPath == "/Users/alice/project")
        #expect(summary.projectSlug == "-Users-alice-project")
        #expect(summary.gitBranch == "main")
        #expect(summary.claudeVersion == "2.1.112")
        #expect(summary.messageCount == 3)  // 2 user + 1 assistant
        #expect(summary.id == url.deletingPathExtension().lastPathComponent)
    }

    @Test("first prompt skips tool_result-only user lines")
    func firstPromptSkipsToolResult() throws {
        let fixture = """
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
        {"type":"user","cwd":"/w","message":{"role":"user","content":"Real question"}}
        """
        let url = try writeTempJSONL(fixture)
        let summary = try #require(try SessionSummaryBuilder().build(from: url, slug: "-w"))
        #expect(summary.firstPrompt == "Real question")
        #expect(summary.messageCount == 2)
    }

    @Test("truncates long prompts to 120 chars")
    func truncatesLongPrompt() throws {
        let longText = String(repeating: "x", count: 500)
        let fixture = """
        {"type":"user","cwd":"/w","message":{"role":"user","content":"\(longText)"}}
        """
        let url = try writeTempJSONL(fixture)
        let summary = try #require(try SessionSummaryBuilder().build(from: url, slug: "-w"))
        #expect(summary.firstPrompt?.count == 120)
    }

    @Test("returns nil for an empty file")
    func emptyFileReturnsNil() throws {
        let url = try writeTempJSONL("")
        let summary = try SessionSummaryBuilder().build(from: url, slug: "-w")
        #expect(summary == nil)
    }

    @Test("ignores malformed lines instead of throwing")
    func toleratesMalformedLines() throws {
        let fixture = """
        this is not json at all
        {"type":"user","cwd":"/w","message":{"role":"user","content":"Valid"}}
        {broken json here
        """
        let url = try writeTempJSONL(fixture)
        let summary = try #require(try SessionSummaryBuilder().build(from: url, slug: "-w"))
        #expect(summary.firstPrompt == "Valid")
        #expect(summary.messageCount == 1)
    }

    @Test("falls back to slug when no cwd is present")
    func noCwdFallsBackToSlug() throws {
        let fixture = """
        {"type":"user","message":{"role":"user","content":"Hello"}}
        """
        let url = try writeTempJSONL(fixture)
        let summary = try #require(try SessionSummaryBuilder().build(from: url, slug: "-fallback-slug"))
        #expect(summary.projectPath == "-fallback-slug")
    }

    // MARK: - helpers

    private func writeTempJSONL(_ content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "\(UUID().uuidString).jsonl")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
