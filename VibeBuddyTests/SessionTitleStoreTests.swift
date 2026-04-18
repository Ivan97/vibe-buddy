import Foundation
import Testing
@testable import VibeBuddy

@Suite("SessionTitleStore")
struct SessionTitleStoreTests {

    @Test("setTitle stores + retrieves")
    @MainActor
    func setAndRead() {
        let store = SessionTitleStore()
        // Use a unique id so we don't collide with real user state in AS dir.
        let id = "test-\(UUID().uuidString)"
        store.setTitle("Custom name", for: id)
        #expect(store.customTitle(for: id) == "Custom name")
        store.setTitle(nil, for: id)
        #expect(store.customTitle(for: id) == nil)
    }

    @Test("empty / whitespace-only titles clear the override")
    @MainActor
    func emptyClears() {
        let store = SessionTitleStore()
        let id = "test-\(UUID().uuidString)"
        store.setTitle("Real title", for: id)
        #expect(store.customTitle(for: id) == "Real title")

        store.setTitle("   ", for: id)
        #expect(store.customTitle(for: id) == nil)
    }

    @Test("titles trim surrounding whitespace on save")
    @MainActor
    func trims() {
        let store = SessionTitleStore()
        let id = "test-\(UUID().uuidString)"
        store.setTitle("  Spaced  ", for: id)
        #expect(store.customTitle(for: id) == "Spaced")
    }

    @Test("persistence survives a new instance")
    @MainActor
    func persists() {
        let id = "persisted-\(UUID().uuidString)"
        let first = SessionTitleStore()
        first.setTitle("Persisted title", for: id)

        // New instance reads the same on-disk file.
        let second = SessionTitleStore()
        #expect(second.customTitle(for: id) == "Persisted title")

        // Clean up.
        second.setTitle(nil, for: id)
    }
}
