import Foundation

/// Byte-range index into a `*.jsonl` file. Each entry in `lineRanges` points
/// at one *complete* line (terminated by `\n`) — partial trailing lines are
/// left out so streaming writes from Claude Code can't produce a half-parsed
/// record. `scannedUpTo` is the next byte to resume from on `extend(with:)`,
/// which makes append-only growth cheap to incorporate.
struct JSONLIndex: Sendable, Equatable {
    private(set) var lineRanges: [Range<Int>] = []
    private(set) var scannedUpTo: Int = 0

    var lineCount: Int { lineRanges.count }

    mutating func extend(with data: Data) {
        var start = scannedUpTo
        let end = data.count
        var i = start
        while i < end {
            if data[i] == 0x0A { // '\n'
                if start < i {
                    lineRanges.append(start..<i)
                }
                start = i + 1
            }
            i += 1
        }
        scannedUpTo = start
    }

    static func build(from data: Data) -> JSONLIndex {
        var index = JSONLIndex()
        index.extend(with: data)
        return index
    }
}
