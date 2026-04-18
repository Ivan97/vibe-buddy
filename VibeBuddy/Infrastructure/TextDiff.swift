import Foundation

/// One line of a unified diff.
enum DiffLine: Equatable, Sendable {
    case context(String)
    case removed(String)
    case added(String)
}

/// Line-level unified diff. Uses Swift's `CollectionDifference` for the core
/// edit script, then walks both sides in parallel to produce the interleaved
/// view a human wants to read (context → removals → additions → context).
enum TextDiff {

    static func unified(before: String, after: String) -> [DiffLine] {
        let beforeLines = split(before)
        let afterLines = split(after)
        return unified(beforeLines: beforeLines, afterLines: afterLines)
    }

    static func unified(beforeLines: [String], afterLines: [String]) -> [DiffLine] {
        let diff = afterLines.difference(from: beforeLines)

        var removalsByOffset: [Int: String] = [:]
        for change in diff.removals {
            if case .remove(let offset, let element, _) = change {
                removalsByOffset[offset] = element
            }
        }
        var insertionsByOffset: [Int: String] = [:]
        for change in diff.insertions {
            if case .insert(let offset, let element, _) = change {
                insertionsByOffset[offset] = element
            }
        }

        var result: [DiffLine] = []
        var i = 0
        var j = 0
        while i < beforeLines.count || j < afterLines.count {
            let removed = removalsByOffset[i]
            let added = insertionsByOffset[j]

            if let removed, let added {
                result.append(.removed(removed))
                result.append(.added(added))
                i += 1
                j += 1
            } else if let removed {
                result.append(.removed(removed))
                i += 1
            } else if let added {
                result.append(.added(added))
                j += 1
            } else if i < beforeLines.count, j < afterLines.count {
                // Matching context line.
                result.append(.context(beforeLines[i]))
                i += 1
                j += 1
            } else {
                break
            }
        }
        return result
    }

    private static func split(_ source: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
