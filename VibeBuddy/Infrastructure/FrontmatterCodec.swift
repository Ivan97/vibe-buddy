import Foundation

/// YAML-lite frontmatter used by Claude Code's markdown artifacts
/// (agents / commands / skills). Supports only the subset observed in the
/// wild: `key: value` scalars and simple `- item` string lists. Unknown
/// shapes (nested maps, multi-line folded scalars, tags) fall back to
/// opaque string values so a round-trip never silently drops data.
enum FrontmatterValue: Equatable, Sendable {
    case scalar(String)
    case list([String])
}

/// Ordered pairs — order is preserved through parse/serialize so that a
/// round-trip produces a diff that's only about fields the user actually
/// edited.
typealias FrontmatterMap = [(key: String, value: FrontmatterValue)]

struct FrontmatterDocumentRaw: Equatable, Sendable {
    var frontmatter: FrontmatterMap
    var body: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.body == rhs.body && frontmatterEquals(lhs.frontmatter, rhs.frontmatter)
    }
}

private func frontmatterEquals(_ a: FrontmatterMap, _ b: FrontmatterMap) -> Bool {
    guard a.count == b.count else { return false }
    for (lhs, rhs) in zip(a, b) where lhs.key != rhs.key || lhs.value != rhs.value {
        return false
    }
    return true
}

// MARK: - Codec

enum FrontmatterCodec {

    /// Splits a markdown file into its (optional) frontmatter and body.
    /// Missing or malformed frontmatter is treated as "no frontmatter" —
    /// the whole source becomes the body.
    static func parse(_ source: String) -> FrontmatterDocumentRaw {
        guard let (yaml, body) = splitFrontmatter(source) else {
            return FrontmatterDocumentRaw(frontmatter: [], body: source)
        }
        let map = parseYAML(yaml)
        return FrontmatterDocumentRaw(frontmatter: map, body: body)
    }

    static func serialize(_ document: FrontmatterDocumentRaw) -> String {
        if document.frontmatter.isEmpty {
            return document.body
        }
        var out = "---\n"
        for pair in document.frontmatter {
            out += emit(key: pair.key, value: pair.value)
        }
        out += "---\n"
        if !document.body.isEmpty, !document.body.hasPrefix("\n") {
            out += "\n"
        }
        out += document.body
        return out
    }

    // MARK: split

    private static func splitFrontmatter(_ source: String) -> (yaml: String, body: String)? {
        // Must start with "---" on its own line (with optional leading BOM stripped).
        let trimmed: String
        if source.hasPrefix("\u{FEFF}") {
            trimmed = String(source.dropFirst())
        } else {
            trimmed = source
        }

        guard trimmed.hasPrefix("---") else { return nil }

        // Require a newline after the opening fence.
        var cursor = trimmed.index(trimmed.startIndex, offsetBy: 3)
        guard cursor < trimmed.endIndex else { return nil }
        if trimmed[cursor] == "\r" {
            cursor = trimmed.index(after: cursor)
        }
        guard cursor < trimmed.endIndex, trimmed[cursor] == "\n" else { return nil }
        cursor = trimmed.index(after: cursor)

        // Find closing fence: a line that is exactly "---".
        let rest = trimmed[cursor...]
        guard let closeRange = findClosingFence(rest) else { return nil }

        let yaml = String(rest[rest.startIndex..<closeRange.lowerBound])
        var bodyStart = closeRange.upperBound
        // Strip any number of newline characters immediately following the
        // closing fence. The serializer always emits a single blank line
        // between `---` and the body, so the round-trip is stable even
        // though this collapses multiple consecutive blank lines to zero
        // on the body side — a conscious trade for a nicer edit surface.
        while bodyStart < rest.endIndex,
              rest[bodyStart] == "\n" || rest[bodyStart] == "\r" {
            bodyStart = rest.index(after: bodyStart)
        }
        let body = String(rest[bodyStart..<rest.endIndex])
        return (yaml, body)
    }

    private static func findClosingFence(_ text: Substring) -> Range<Substring.Index>? {
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            // Find end of this line.
            var lineEnd = lineStart
            while lineEnd < text.endIndex, text[lineEnd] != "\n" {
                lineEnd = text.index(after: lineEnd)
            }
            let line = text[lineStart..<lineEnd]
            // Allow optional trailing \r.
            let trimmedLine: Substring
            if line.hasSuffix("\r") {
                trimmedLine = line.dropLast()
            } else {
                trimmedLine = line
            }
            if trimmedLine == "---" {
                return lineStart..<lineEnd
            }
            if lineEnd == text.endIndex { return nil }
            lineStart = text.index(after: lineEnd)
        }
        return nil
    }

    // MARK: parse YAML-lite

    private static func parseYAML(_ yaml: String) -> FrontmatterMap {
        var result: FrontmatterMap = []
        let rawLines = yaml.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })

        var index = 0
        while index < rawLines.count {
            let rawLine = String(rawLines[index])
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine

            // Skip blank lines and # comments at column zero.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }

            // Top-level key: only matches `^\S[^:]*:.*$`.
            guard let colonRange = line.range(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else {
                index += 1
                continue
            }

            let key = String(line[line.startIndex..<colonRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[colonRange.upperBound...])
            let valuePart = rawValue.trimmingCharacters(in: .whitespaces)

            if valuePart.isEmpty {
                // List-valued key: collect indented `- item` lines.
                var items: [String] = []
                var j = index + 1
                while j < rawLines.count {
                    let next = String(rawLines[j])
                    let nextTrimmed = next.hasSuffix("\r") ? String(next.dropLast()) : next
                    if nextTrimmed.trimmingCharacters(in: .whitespaces).isEmpty {
                        j += 1
                        continue
                    }
                    let leadingWhitespace = nextTrimmed.prefix { $0 == " " || $0 == "\t" }
                    guard !leadingWhitespace.isEmpty else { break }
                    let stripped = nextTrimmed.drop { $0 == " " || $0 == "\t" }
                    guard stripped.hasPrefix("- ") || stripped == "-" else { break }
                    let itemRaw = stripped.dropFirst(2).trimmingCharacters(in: .whitespaces)
                    items.append(unquote(itemRaw))
                    j += 1
                }
                result.append((key, .list(items)))
                index = j
            } else {
                result.append((key, .scalar(unquote(valuePart))))
                index += 1
            }
        }

        return result
    }

    private static func unquote(_ s: String) -> String {
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            let inner = String(s.dropFirst().dropLast())
            return inner
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2 {
            return String(s.dropFirst().dropLast())
                .replacingOccurrences(of: "''", with: "'")
        }
        return s
    }

    // MARK: emit

    private static func emit(key: String, value: FrontmatterValue) -> String {
        switch value {
        case .scalar(let s):
            return "\(key): \(quoteIfNeeded(s))\n"
        case .list(let items):
            if items.isEmpty {
                return "\(key): []\n"
            }
            var out = "\(key):\n"
            for item in items {
                out += "  - \(quoteIfNeeded(item))\n"
            }
            return out
        }
    }

    private static func quoteIfNeeded(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        if s.contains("\n") {
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(escaped)\""
        }
        let needsQuoting = s.contains(": ")
            || s.hasPrefix("-")
            || s.hasPrefix("?")
            || s.hasPrefix("@")
            || s.hasPrefix("`")
            || s.hasPrefix("|")
            || s.hasPrefix(">")
            || s.hasPrefix("[")
            || s.hasPrefix("{")
            || s.hasPrefix("!")
            || s.hasPrefix("#")
            || s.hasPrefix("&")
            || s.hasPrefix("*")
            || s.hasPrefix("%")
            || s.hasPrefix("\"")
            || s.hasPrefix("'")
            || s.hasSuffix(" ")
            || s.hasPrefix(" ")
        if needsQuoting {
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return s
    }
}

// MARK: - FrontmatterMap helpers

extension Array where Element == (key: String, value: FrontmatterValue) {
    func scalar(_ key: String) -> String? {
        for pair in self where pair.key == key {
            if case .scalar(let v) = pair.value { return v }
        }
        return nil
    }

    func list(_ key: String) -> [String]? {
        for pair in self where pair.key == key {
            if case .list(let v) = pair.value { return v }
        }
        return nil
    }

    func without(_ keys: Set<String>) -> Self {
        filter { !keys.contains($0.key) }
    }
}
