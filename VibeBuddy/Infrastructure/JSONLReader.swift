import Foundation

/// Lightweight line-oriented reader for `*.jsonl` files. Loads the whole file
/// into memory (acceptable for Claude Code session files, typically <10 MB)
/// and splits on `\n`. Skips blank lines. Returns each line as `Data` so the
/// caller can `JSONSerialization` / `JSONDecoder` it without another copy.
struct JSONLReader: Sendable {
    let url: URL

    init(url: URL) { self.url = url }

    func forEachLine(_ body: (Data) throws -> Void) throws {
        let data = try Data(contentsOf: url)
        var cursor = data.startIndex
        while cursor < data.endIndex {
            let remaining = data[cursor...]
            if let newline = remaining.firstIndex(of: 0x0A) {
                let slice = data[cursor..<newline]
                if !slice.isEmpty { try body(Data(slice)) }
                cursor = data.index(after: newline)
            } else {
                let slice = data[cursor..<data.endIndex]
                if !slice.isEmpty { try body(Data(slice)) }
                break
            }
        }
    }
}

/// Tolerant ISO-8601 parser. Session timestamps observed in the wild usually
/// include fractional seconds (`2026-04-17T16:06:44.488Z`), but fall back to
/// no-fractional form just in case older/newer formats differ.
enum ISO8601Tolerant {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String) -> Date? {
        withFraction.date(from: s) ?? plain.date(from: s)
    }
}
