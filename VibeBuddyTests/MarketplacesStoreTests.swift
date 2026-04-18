import Foundation
import Testing
@testable import VibeBuddy

@Suite("MarketplacesStore.parse")
struct MarketplacesStoreTests {

    @Test("parses a canonical known_marketplaces.json entry")
    func parsesCanonical() {
        let raw: [String: Any] = [
            "frontend-slides": [
                "source": [
                    "source": "github",
                    "repo": "zarazhangrui/frontend-slides"
                ],
                "installLocation": "/Users/x/.claude/plugins/marketplaces/frontend-slides",
                "lastUpdated": "2026-04-18T09:54:41.778Z",
                "autoUpdate": true
            ]
        ]
        let parsed = MarketplacesStore.parse(raw)
        #expect(parsed.count == 1)
        let entry = try! #require(parsed.first)
        #expect(entry.id == "frontend-slides")
        #expect(entry.repo == "zarazhangrui/frontend-slides")
        #expect(entry.sourceType == "github")
        #expect(entry.installLocation?.lastPathComponent == "frontend-slides")
        #expect(entry.lastUpdated != nil)
        #expect(entry.autoUpdate == true)
    }

    @Test("absent autoUpdate field defaults to false")
    func autoUpdateDefaultsFalse() {
        let raw: [String: Any] = [
            "foo": [
                "source": ["source": "github", "repo": "a/b"],
                "installLocation": "/tmp/foo"
            ]
        ]
        let entry = try! #require(MarketplacesStore.parse(raw).first)
        #expect(entry.autoUpdate == false)
    }

    @Test("entries sort case-insensitively by name")
    func sortedOrder() {
        let raw: [String: Any] = [
            "Zulu":  ["source": ["source": "github", "repo": "z/z"]],
            "alpha": ["source": ["source": "github", "repo": "a/a"]],
            "Bravo": ["source": ["source": "github", "repo": "b/b"]]
        ]
        let ids = MarketplacesStore.parse(raw).map(\.id)
        #expect(ids == ["alpha", "Bravo", "Zulu"])
    }

    @Test("unknown top-level entry keys land in extras (round-tripable)")
    func extrasPreserved() {
        let raw: [String: Any] = [
            "foo": [
                "source": ["source": "github", "repo": "a/b"],
                "someUnknownFutureField": "keep-me",
                "nested": ["a": 1]
            ]
        ]
        let entry = try! #require(MarketplacesStore.parse(raw).first)
        #expect(entry.extras["someUnknownFutureField"] as? String == "keep-me")
        #expect((entry.extras["nested"] as? [String: Any])?["a"] as? Int == 1)
    }

    @Test("skips non-dictionary entries instead of crashing")
    func tolerantToGarbage() {
        let raw: [String: Any] = [
            "good": ["source": ["source": "github", "repo": "a/b"]],
            "bad": "not a dict"
        ]
        let parsed = MarketplacesStore.parse(raw)
        #expect(parsed.count == 1)
        #expect(parsed.first?.id == "good")
    }
}
