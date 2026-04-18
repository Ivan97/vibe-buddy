import Foundation

/// Holds a memory-mapped view of a session jsonl file plus a line-offset
/// index. Lives on its own actor so the main actor never blocks on IO or
/// decode.
///
/// The mmap is refreshed via `refreshIfGrown()` — jsonl files are append-only,
/// so old byte offsets stay valid and the index just grows at the tail.
actor SessionFileBackend {
    let url: URL
    private var data: Data
    private var index: JSONLIndex

    init(url: URL) throws {
        self.url = url
        self.data = try Data(contentsOf: url, options: [.mappedIfSafe])
        var idx = JSONLIndex()
        idx.extend(with: self.data)
        self.index = idx
    }

    var lineCount: Int { index.lineCount }

    /// Re-map the file and extend the index if the file grew. Returns the
    /// number of newly indexed lines (0 if nothing changed).
    @discardableResult
    func refreshIfGrown() throws -> Int {
        let newData = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard newData.count > data.count else { return 0 }
        let before = index.lineCount
        data = newData
        index.extend(with: data)
        return index.lineCount - before
    }

    /// Decode a forward range of lines. Metadata-only lines (dropped by the
    /// entry decoder) are silently skipped, so the returned count may be less
    /// than `range.count`.
    func decode(linesIn range: Range<Int>) -> [SessionEntry] {
        let clamped = range.clamped(to: 0..<index.lineCount)
        let decoder = SessionEntryDecoder()
        var out: [SessionEntry] = []
        out.reserveCapacity(clamped.count)
        for i in clamped {
            let r = index.lineRanges[i]
            let line = data.subdata(in: r)
            if let entry = decoder.decode(line) {
                out.append(entry)
            }
        }
        return out
    }

    /// Walk backwards from `upperExclusive` decoding one line at a time until
    /// at least `minEntries` are produced or the file's start is reached.
    /// Returns the produced entries (in chronological order) and the new line
    /// cursor (lower-bound, exclusive).
    func decodeBackwards(
        from upperExclusive: Int,
        minEntries: Int
    ) -> (entries: [SessionEntry], newCursor: Int) {
        let decoder = SessionEntryDecoder()
        var cursor = min(upperExclusive, index.lineCount)
        var out: [SessionEntry] = []

        while cursor > 0, out.count < minEntries {
            cursor -= 1
            let r = index.lineRanges[cursor]
            let line = data.subdata(in: r)
            if let entry = decoder.decode(line) {
                out.insert(entry, at: 0)
            }
        }

        return (out, cursor)
    }
}
