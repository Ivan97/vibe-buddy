import Foundation
import Testing
@testable import VibeBuddy

@Suite("SafeJSONStore")
struct SafeJSONStoreTests {

    @Test("missing file loads as empty dictionary")
    func missingFile() throws {
        let url = try tempURL()
        let store = SafeJSONStore(url: url)
        #expect(try store.load().isEmpty)
    }

    @Test("round-trips top-level keys")
    func roundTrip() throws {
        let url = try tempURL()
        let store = SafeJSONStore(url: url)
        let payload: [String: Any] = [
            "a": "hello",
            "b": 42,
            "c": ["nested": ["x": 1]]
        ]
        try store.save(payload)
        let loaded = try store.load()
        #expect(loaded["a"] as? String == "hello")
        #expect(loaded["b"] as? Int == 42)
        #expect((loaded["c"] as? [String: Any])?["nested"] as? [String: Int] == ["x": 1])
    }

    @Test("patch preserves unrelated keys")
    func patchPreservesOtherKeys() throws {
        let url = try tempURL()
        let store = SafeJSONStore(url: url)
        try store.save(["keep": "intact", "replace": "before"])

        try store.patch(field: "replace", value: "after")

        let loaded = try store.load()
        #expect(loaded["keep"] as? String == "intact")
        #expect(loaded["replace"] as? String == "after")
    }

    @Test("patch with nil removes the key")
    func patchNilRemoves() throws {
        let url = try tempURL()
        let store = SafeJSONStore(url: url)
        try store.save(["a": 1, "b": 2])
        try store.patch(field: "a", value: nil)
        let loaded = try store.load()
        #expect(loaded["a"] == nil)
        #expect(loaded["b"] as? Int == 2)
    }

    @Test("save writes pretty-printed JSON with sorted keys and trailing newline")
    func prettySortedWrite() throws {
        let url = try tempURL()
        let store = SafeJSONStore(url: url)
        try store.save(["z": 1, "a": 2])
        let text = try String(contentsOf: url, encoding: .utf8)
        // Keys sorted: a should come before z
        let aIndex = try #require(text.range(of: "\"a\""))
        let zIndex = try #require(text.range(of: "\"z\""))
        #expect(aIndex.lowerBound < zIndex.lowerBound)
        #expect(text.hasSuffix("\n"))
        // Pretty printing implies at least one indented line
        #expect(text.contains("  "))
    }

    @Test("non-dict root throws")
    func nonDictRoot() throws {
        let url = try tempURL()
        try "[1,2,3]".write(to: url, atomically: true, encoding: .utf8)
        let store = SafeJSONStore(url: url)
        #expect(throws: SafeJSONStore.StoreError.notADictionary) {
            try store.load()
        }
    }

    @Test("save creates a .bak on overwrite")
    func backsUpOnOverwrite() throws {
        let url = try tempURL()
        let store = SafeJSONStore(url: url)
        try store.save(["v": 1])
        try store.save(["v": 2])
        let bak = url.appendingPathExtension("bak")
        let backupText = try String(contentsOf: bak, encoding: .utf8)
        #expect(backupText.contains("\"v\" : 1"))
    }

    // MARK: - helper

    private func tempURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "VibeBuddy-SafeJSONStore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "settings.json")
    }
}
