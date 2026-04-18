import Foundation
import Testing
@testable import VibeBuddy

@Suite("TextDiff")
struct TextDiffTests {

    @Test("identical inputs produce only context lines")
    func identical() {
        let lines = TextDiff.unified(before: "a\nb\nc", after: "a\nb\nc")
        #expect(lines == [.context("a"), .context("b"), .context("c")])
    }

    @Test("addition at end appends an .added line")
    func additionAtEnd() {
        let lines = TextDiff.unified(before: "a\nb", after: "a\nb\nc")
        #expect(lines == [.context("a"), .context("b"), .added("c")])
    }

    @Test("removal in the middle produces a .removed line")
    func removalInMiddle() {
        let lines = TextDiff.unified(before: "a\nb\nc", after: "a\nc")
        #expect(lines == [.context("a"), .removed("b"), .context("c")])
    }

    @Test("replacement interleaves removed then added at the same position")
    func replacement() {
        let lines = TextDiff.unified(before: "a\nold\nc", after: "a\nnew\nc")
        #expect(lines == [.context("a"), .removed("old"), .added("new"), .context("c")])
    }

    @Test("empty before produces all additions")
    func emptyBefore() {
        let lines = TextDiff.unified(before: "", after: "x\ny")
        let added = lines.compactMap { if case .added(let s) = $0 { return s } else { return nil } }
        #expect(added == ["x", "y"])
    }

    @Test("empty after produces all removals")
    func emptyAfter() {
        let lines = TextDiff.unified(before: "x\ny", after: "")
        let removed = lines.compactMap { if case .removed(let s) = $0 { return s } else { return nil } }
        #expect(removed == ["x", "y"])
    }

    @Test("completely different content produces only non-context lines")
    func completelyDifferent() {
        let lines = TextDiff.unified(before: "a\nb", after: "c\nd")
        let ctx = lines.compactMap { if case .context(let s) = $0 { return s } else { return nil } }
        let removed = lines.compactMap { if case .removed(let s) = $0 { return s } else { return nil } }
        let added = lines.compactMap { if case .added(let s) = $0 { return s } else { return nil } }
        #expect(ctx.isEmpty)
        #expect(removed.sorted() == ["a", "b"])
        #expect(added.sorted() == ["c", "d"])
    }
}
