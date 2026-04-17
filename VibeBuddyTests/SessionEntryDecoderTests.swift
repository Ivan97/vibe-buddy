import Foundation
import Testing
@testable import VibeBuddy

@Suite("SessionEntryDecoder")
struct SessionEntryDecoderTests {
    let decoder = SessionEntryDecoder()

    // MARK: - user

    @Test("decodes user string content as .userText")
    func userStringContent() {
        let line = json(#"""
        {"type":"user","uuid":"u1","timestamp":"2026-04-17T10:00:00.000Z","message":{"role":"user","content":"Hi there"}}
        """#)
        let entry = try! #require(decoder.decode(line))
        guard case .userText(let text) = entry.kind else {
            Issue.record("expected .userText")
            return
        }
        #expect(text == "Hi there")
        #expect(entry.id == "u1")
        #expect(entry.timestamp != nil)
    }

    @Test("decodes tool_result-only user content as .userToolResults")
    func userToolResultContent() {
        let line = json(#"""
        {"type":"user","uuid":"u2","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu1","content":"exit 0","is_error":false}]}}
        """#)
        let entry = try! #require(decoder.decode(line))
        guard case .userToolResults(let results) = entry.kind else {
            Issue.record("expected .userToolResults; got \(entry.kind)")
            return
        }
        #expect(results.count == 1)
        #expect(results[0].toolUseId == "tu1")
        #expect(results[0].isError == false)
        #expect(results[0].content == "exit 0")
    }

    @Test("flattens list-of-text tool_result content")
    func toolResultListContent() {
        let line = json(#"""
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":[{"type":"text","text":"line 1"},{"type":"text","text":"line 2"}]}]}}
        """#)
        let entry = try! #require(decoder.decode(line))
        guard case .userToolResults(let results) = entry.kind else {
            Issue.record("expected userToolResults")
            return
        }
        #expect(results.first?.content == "line 1\nline 2")
    }

    // MARK: - assistant

    @Test("decodes assistant text + thinking + tool_use blocks")
    func assistantBlocks() {
        let line = json(#"""
        {"type":"assistant","uuid":"a1","timestamp":"2026-04-17T10:00:05.000Z","message":{"role":"assistant","model":"claude-opus-4-7","stop_reason":"tool_use","usage":{"input_tokens":100,"output_tokens":42,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"thinking","thinking":"reasoning...","signature":"x"},{"type":"text","text":"Here you go"},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}
        """#)
        let entry = try! #require(decoder.decode(line))
        guard case .assistantTurn(let blocks, let model, let stopReason, let usage) = entry.kind else {
            Issue.record("expected assistantTurn; got \(entry.kind)")
            return
        }
        #expect(model == "claude-opus-4-7")
        #expect(stopReason == "tool_use")
        #expect(usage?.inputTokens == 100)
        #expect(usage?.outputTokens == 42)
        #expect(blocks.count == 3)
        if case .thinking(let t) = blocks[0] { #expect(t == "reasoning...") } else { Issue.record("expected thinking block") }
        if case .text(let t) = blocks[1] { #expect(t == "Here you go") } else { Issue.record("expected text block") }
        if case .toolUse(let id, let name, let preview) = blocks[2] {
            #expect(id == "t1")
            #expect(name == "Bash")
            #expect(preview.contains("\"command\""))
        } else {
            Issue.record("expected toolUse block")
        }
    }

    // MARK: - attachment & system

    @Test("summarizes hook_success attachment")
    func hookSuccessAttachment() {
        let line = json(#"""
        {"type":"attachment","uuid":"x","attachment":{"type":"hook_success","hookName":"session-start","command":"echo hi","exitCode":0,"stdout":"hi","stderr":"","hookEvent":"SessionStart","durationMs":12,"toolUseID":"","content":""}}
        """#)
        let entry = try! #require(decoder.decode(line))
        guard case .attachment(let subtype, let summary) = entry.kind else {
            Issue.record("expected attachment")
            return
        }
        #expect(subtype == "hook_success")
        #expect(summary.contains("session-start"))
        #expect(summary.contains("exit 0"))
    }

    @Test("summarizes stop_hook_summary system entry")
    func stopHookSummary() {
        let line = json(#"""
        {"type":"system","uuid":"s1","subtype":"stop_hook_summary","hookCount":3,"hookErrors":[],"hookInfos":[]}
        """#)
        let entry = try! #require(decoder.decode(line))
        guard case .systemNote(let subtype, let summary) = entry.kind else {
            Issue.record("expected systemNote")
            return
        }
        #expect(subtype == "stop_hook_summary")
        #expect(summary.contains("3"))
    }

    // MARK: - drops & unknowns

    @Test("drops metadata-only line types")
    func dropsMetadata() {
        for type in ["permission-mode", "last-prompt", "file-history-snapshot", "progress"] {
            let line = json("{\"type\":\"\(type)\",\"sessionId\":\"x\"}")
            #expect(decoder.decode(line) == nil, "expected nil for \(type)")
        }
    }

    @Test("decodes unknown type as .unknown")
    func unknownType() {
        let line = json(#"""
        {"type":"future-type","uuid":"f1","something":"whatever"}
        """#)
        let entry = try! #require(decoder.decode(line))
        guard case .unknown(let type) = entry.kind else {
            Issue.record("expected .unknown")
            return
        }
        #expect(type == "future-type")
    }

    @Test("returns nil on non-JSON")
    func nonJSON() {
        #expect(decoder.decode(Data("not json".utf8)) == nil)
    }

    // MARK: - helper

    private func json(_ s: String) -> Data {
        Data(s.utf8)
    }
}
