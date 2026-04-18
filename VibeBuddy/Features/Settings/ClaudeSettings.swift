import Foundation

/// Typed view over the user-editable keys that appear in
/// `~/.claude/settings.json` (and its local override). Unknown keys are
/// kept in `extras` so saves round-trip cleanly — the same contract the
/// rest of VibeBuddy's config surfaces follow.
///
/// Equatable on the typed keys only; `extras` equality is compared via
/// serialized JSON to avoid the `[String: Any]`-isn't-Equatable dance.
struct ClaudeSettings: Equatable {
    /// Default model selector: `"sonnet"`, `"opus"`, `"haiku"`, or a
    /// fully-qualified model id the user typed in. `nil` → inherit.
    var model: String?

    /// Theme selector. Claude Code ships `dark`, `light`,
    /// `dark-daltonized`, `light-daltonized`, `dark-ansi`, `light-ansi`.
    /// Stored as a raw string so new themes work without a code change.
    var theme: String?

    /// Environment variables Claude Code will inject into every session.
    var env: [String: String]

    /// Permission policy. Each arm is a list of match patterns the user
    /// has pinned to that outcome.
    var permissions: Permissions

    var apiKeyHelper: String?
    var includeCoAuthoredBy: Bool?
    var cleanupPeriodDays: Int?
    var outputStyle: String?
    var forceLoginMethod: String?
    var verbose: Bool?

    /// Unknown top-level keys, preserved verbatim on save. Includes keys
    /// owned by other VibeBuddy modules (`hooks`, `mcpServers`,
    /// `enabledPlugins`, `statusLine`) so those modules remain the single
    /// writer for their field.
    var extras: [String: Any]

    static func == (lhs: ClaudeSettings, rhs: ClaudeSettings) -> Bool {
        guard
            lhs.model == rhs.model,
            lhs.theme == rhs.theme,
            lhs.env == rhs.env,
            lhs.permissions == rhs.permissions,
            lhs.apiKeyHelper == rhs.apiKeyHelper,
            lhs.includeCoAuthoredBy == rhs.includeCoAuthoredBy,
            lhs.cleanupPeriodDays == rhs.cleanupPeriodDays,
            lhs.outputStyle == rhs.outputStyle,
            lhs.forceLoginMethod == rhs.forceLoginMethod,
            lhs.verbose == rhs.verbose
        else { return false }
        return Self.sameExtras(lhs.extras, rhs.extras)
    }

    private static func sameExtras(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        let aData = try? JSONSerialization.data(
            withJSONObject: a,
            options: [.prettyPrinted, .sortedKeys]
        )
        let bData = try? JSONSerialization.data(
            withJSONObject: b,
            options: [.prettyPrinted, .sortedKeys]
        )
        return aData == bData
    }

    struct Permissions: Equatable {
        var allow: [String]
        var deny: [String]
        var ask: [String]
        /// Keys like `defaultMode`, `additionalDirectories`, `disableBypassPermissionsMode`.
        var extras: [String: Any]

        static let empty = Permissions(allow: [], deny: [], ask: [], extras: [:])

        static func == (lhs: Permissions, rhs: Permissions) -> Bool {
            guard
                lhs.allow == rhs.allow,
                lhs.deny == rhs.deny,
                lhs.ask == rhs.ask
            else { return false }
            let aData = try? JSONSerialization.data(
                withJSONObject: lhs.extras,
                options: [.prettyPrinted, .sortedKeys]
            )
            let bData = try? JSONSerialization.data(
                withJSONObject: rhs.extras,
                options: [.prettyPrinted, .sortedKeys]
            )
            return aData == bData
        }
    }

    static let empty = ClaudeSettings(
        model: nil,
        theme: nil,
        env: [:],
        permissions: .empty,
        apiKeyHelper: nil,
        includeCoAuthoredBy: nil,
        cleanupPeriodDays: nil,
        outputStyle: nil,
        forceLoginMethod: nil,
        verbose: nil,
        extras: [:]
    )
}
