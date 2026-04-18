import Foundation

/// One entry from `~/.claude/plugins/known_marketplaces.json`. `autoUpdate`
/// is marketplace-scoped — when true, every plugin shipped by this
/// marketplace is pulled by Claude Code on launch. The other fields are
/// read-only metadata rendered for context; unknown top-level keys in the
/// JSON round-trip through `extras` untouched.
struct MarketplaceEntry: Identifiable, Equatable, Sendable {
    /// Key in the outer `known_marketplaces.json` dictionary.
    let id: String

    /// e.g. `"anthropics/claude-plugins-official"`. Present only when
    /// `source.source == "github"`; custom sources are kept verbatim in
    /// `sourceExtras`.
    let repo: String?
    let sourceType: String?       // usually "github"
    let sourceExtras: [String: Any]

    let installLocation: URL?
    let lastUpdated: Date?
    var autoUpdate: Bool

    /// Anything we don't explicitly type goes here so we can write back
    /// without dropping forward-compat fields.
    var extras: [String: Any]

    static func == (lhs: MarketplaceEntry, rhs: MarketplaceEntry) -> Bool {
        guard
            lhs.id == rhs.id,
            lhs.repo == rhs.repo,
            lhs.sourceType == rhs.sourceType,
            lhs.installLocation == rhs.installLocation,
            lhs.lastUpdated == rhs.lastUpdated,
            lhs.autoUpdate == rhs.autoUpdate
        else { return false }
        return dataEquals(lhs.sourceExtras, rhs.sourceExtras)
            && dataEquals(lhs.extras, rhs.extras)
    }

    private static func dataEquals(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        let aData = try? JSONSerialization.data(
            withJSONObject: a, options: [.prettyPrinted, .sortedKeys]
        )
        let bData = try? JSONSerialization.data(
            withJSONObject: b, options: [.prettyPrinted, .sortedKeys]
        )
        return aData == bData
    }
}
