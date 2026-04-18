import Foundation
import Testing
@testable import VibeBuddy

@Suite("JSONLIndex")
struct JSONLIndexTests {

    @Test("empty data yields no ranges")
    func empty() {
        let index = JSONLIndex.build(from: Data())
        #expect(index.lineCount == 0)
        #expect(index.scannedUpTo == 0)
    }

    @Test("well-formed two-line buffer produces two ranges")
    func twoLines() {
        let buf = "alpha\nbeta\n"
        let index = JSONLIndex.build(from: Data(buf.utf8))
        #expect(index.lineCount == 2)
        #expect(lineBytes(buf, index.lineRanges[0]) == "alpha")
        #expect(lineBytes(buf, index.lineRanges[1]) == "beta")
        #expect(index.scannedUpTo == buf.utf8.count)
    }

    @Test("empty lines are skipped")
    func skipsEmptyLines() {
        let buf = "one\n\n\ntwo\n"
        let index = JSONLIndex.build(from: Data(buf.utf8))
        #expect(index.lineCount == 2)
        #expect(lineBytes(buf, index.lineRanges[0]) == "one")
        #expect(lineBytes(buf, index.lineRanges[1]) == "two")
    }

    @Test("trailing partial line (no newline) is left unindexed")
    func partialTrailingLine() {
        let buf = "alpha\nbeta"
        let index = JSONLIndex.build(from: Data(buf.utf8))
        #expect(index.lineCount == 1)
        #expect(lineBytes(buf, index.lineRanges[0]) == "alpha")
        // scannedUpTo points at the start of "beta" so next extend picks it up
        #expect(index.scannedUpTo == 6)
    }

    @Test("extend picks up newly appended lines without re-scanning")
    func extendAppendOnly() {
        var index = JSONLIndex()
        let first = Data("alpha\nbeta\n".utf8)
        index.extend(with: first)
        #expect(index.lineCount == 2)

        // Simulate a grown mmap: same bytes as `first` plus two more lines.
        let grown = Data("alpha\nbeta\ngamma\ndelta\n".utf8)
        index.extend(with: grown)
        #expect(index.lineCount == 4)
        #expect(stringForRange(grown, index.lineRanges[2]) == "gamma")
        #expect(stringForRange(grown, index.lineRanges[3]) == "delta")
    }

    @Test("extend across a partial line finishes the pending line on next write")
    func extendAcrossPartial() {
        var index = JSONLIndex()
        index.extend(with: Data("alpha\nbet".utf8))
        #expect(index.lineCount == 1)

        index.extend(with: Data("alpha\nbeta\n".utf8))
        #expect(index.lineCount == 2)
        #expect(stringForRange(Data("alpha\nbeta\n".utf8), index.lineRanges[1]) == "beta")
    }

    // MARK: - helpers

    private func lineBytes(_ source: String, _ range: Range<Int>) -> String {
        let data = Data(source.utf8)
        return String(data: data.subdata(in: range), encoding: .utf8) ?? ""
    }

    private func stringForRange(_ data: Data, _ range: Range<Int>) -> String {
        String(data: data.subdata(in: range), encoding: .utf8) ?? ""
    }
}
