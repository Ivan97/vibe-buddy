import Foundation
import Testing
@testable import VibeBuddy

@Suite("HooksCodec")
struct HooksCodecTests {

    @Test("parses the canonical PostToolUse shape from settings.json")
    func parsesCanonical() {
        let raw: [String: Any] = [
            "PostToolUse": [
                [
                    "matcher": "Edit|Write|Bash",
                    "hooks": [
                        ["type": "command", "command": "/bin/true", "timeout": 15]
                    ]
                ]
            ]
        ]
        let config = HooksCodec.parse(raw)
        #expect(config.events.count == 1)
        let event = try! #require(config.events.first)
        #expect(event.name == "PostToolUse")
        #expect(event.matchers.count == 1)
        let group = event.matchers[0]
        #expect(group.matcher == "Edit|Write|Bash")
        #expect(group.commands.count == 1)
        let cmd = group.commands[0]
        #expect(cmd.type == "command")
        #expect(cmd.command == "/bin/true")
        #expect(cmd.timeout == 15)
    }

    @Test("missing matcher is allowed (means match-all)")
    func missingMatcher() {
        let raw: [String: Any] = [
            "PreCompact": [
                ["hooks": [["type": "command", "command": "/bin/true"]]]
            ]
        ]
        let config = HooksCodec.parse(raw)
        #expect(config.events.first?.matchers.first?.matcher == nil)
    }

    @Test("unknown event names round-trip")
    func unknownEvent() {
        let raw: [String: Any] = [
            "FutureEvent": [
                ["matcher": "*", "hooks": [["type": "command", "command": "cmd"]]]
            ]
        ]
        let config = HooksCodec.parse(raw)
        #expect(config.events.first?.name == "FutureEvent")
        #expect(config.events.first?.kind == nil)

        let reserialized = HooksCodec.toJSON(config)
        let arr = try! #require(reserialized["FutureEvent"] as? [[String: Any]])
        #expect(arr.count == 1)
    }

    @Test("extras on a hook command are preserved")
    func preservesCommandExtras() {
        let raw: [String: Any] = [
            "Stop": [
                [
                    "matcher": "*",
                    "hooks": [[
                        "type": "command",
                        "command": "cmd",
                        "future-field": "value"
                    ]]
                ]
            ]
        ]
        let config = HooksCodec.parse(raw)
        let cmd = try! #require(config.events.first?.matchers.first?.commands.first)
        #expect(cmd.extras["future-field"] == "value")

        let reserialized = HooksCodec.toJSON(config)
        let stopGroup = try! #require((reserialized["Stop"] as? [[String: Any]])?.first)
        let emitted = try! #require((stopGroup["hooks"] as? [[String: Any]])?.first)
        #expect(emitted["future-field"] as? String == "value")
    }

    @Test("events are emitted in canonical order (known first, unknown after)")
    func stableOrdering() {
        let raw: [String: Any] = [
            "Stop": [["hooks": [["type": "command", "command": "a"]]]],
            "PreToolUse": [["hooks": [["type": "command", "command": "b"]]]],
            "FutureZ": [["hooks": [["type": "command", "command": "c"]]]]
        ]
        let config = HooksCodec.parse(raw)
        let names = config.events.map(\.name)
        #expect(names.firstIndex(of: "PreToolUse")! < names.firstIndex(of: "Stop")!)
        #expect(names.firstIndex(of: "Stop")! < names.firstIndex(of: "FutureZ")!)
    }

    @Test("empty / missing hooks dict is handled")
    func emptyInput() {
        #expect(HooksCodec.parse(nil) == .empty)
        #expect(HooksCodec.parse([:] as [String: Any]) == .empty)
    }

    @Test("round-trip is stable for settings.json-shaped input")
    func roundTripStable() {
        let raw: [String: Any] = [
            "PostToolUse": [
                [
                    "matcher": "Edit",
                    "hooks": [["type": "command", "command": "a", "timeout": 10]]
                ],
                [
                    "matcher": "*",
                    "hooks": [["type": "command", "command": "b"]]
                ]
            ],
            "PreToolUse": [
                [
                    "matcher": "*",
                    "hooks": [["type": "command", "command": "c"]]
                ]
            ]
        ]
        let once = HooksCodec.parse(raw)
        let twice = HooksCodec.parse(HooksCodec.toJSON(once))
        #expect(once == twice)
    }
}
