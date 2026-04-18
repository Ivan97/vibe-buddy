import Foundation

/// Parse / serialize between an untyped JSON dictionary and `ClaudeSettings`.
/// The parser is forgiving — fields that don't match the expected shape
/// slide into `extras` instead of being dropped, so hand-written settings
/// round-trip even when Claude Code ships a key we don't know about yet.
enum SettingsCodec {

    /// Keys the typed struct claims. Anything not in this set lands in
    /// `extras` on parse and is pass-through on serialize.
    private static let ownedKeys: Set<String> = [
        "model", "theme", "env", "permissions",
        "apiKeyHelper", "includeCoAuthoredBy", "cleanupPeriodDays",
        "outputStyle", "forceLoginMethod", "verbose"
    ]

    private static let ownedPermissionKeys: Set<String> = [
        "allow", "deny", "ask"
    ]

    // MARK: - parse

    static func parse(_ dict: [String: Any]) -> ClaudeSettings {
        let permissions = parsePermissions(dict["permissions"])

        var extras: [String: Any] = [:]
        for (k, v) in dict where !ownedKeys.contains(k) {
            extras[k] = v
        }

        return ClaudeSettings(
            model: dict["model"] as? String,
            theme: dict["theme"] as? String,
            env: (dict["env"] as? [String: String]) ?? [:],
            permissions: permissions,
            apiKeyHelper: dict["apiKeyHelper"] as? String,
            includeCoAuthoredBy: dict["includeCoAuthoredBy"] as? Bool,
            cleanupPeriodDays: dict["cleanupPeriodDays"] as? Int,
            outputStyle: dict["outputStyle"] as? String,
            forceLoginMethod: dict["forceLoginMethod"] as? String,
            verbose: dict["verbose"] as? Bool,
            extras: extras
        )
    }

    private static func parsePermissions(_ any: Any?) -> ClaudeSettings.Permissions {
        guard let dict = any as? [String: Any] else { return .empty }
        var extras: [String: Any] = [:]
        for (k, v) in dict where !ownedPermissionKeys.contains(k) {
            extras[k] = v
        }
        return ClaudeSettings.Permissions(
            allow: (dict["allow"] as? [String]) ?? [],
            deny: (dict["deny"] as? [String]) ?? [],
            ask: (dict["ask"] as? [String]) ?? [],
            extras: extras
        )
    }

    // MARK: - serialize

    /// Emit a fresh dictionary from `settings`, dropping keys whose value
    /// is "unset" (nil/empty). `extras` is merged last so an unknown key
    /// can't accidentally overwrite a typed one — typed keys win.
    static func serialize(_ settings: ClaudeSettings) -> [String: Any] {
        var out: [String: Any] = settings.extras

        if let model = settings.model, !model.isEmpty { out["model"] = model } else { out.removeValue(forKey: "model") }
        if let theme = settings.theme, !theme.isEmpty { out["theme"] = theme } else { out.removeValue(forKey: "theme") }
        if !settings.env.isEmpty { out["env"] = settings.env } else { out.removeValue(forKey: "env") }

        let permDict = serializePermissions(settings.permissions)
        if permDict.isEmpty {
            out.removeValue(forKey: "permissions")
        } else {
            out["permissions"] = permDict
        }

        if let helper = settings.apiKeyHelper, !helper.isEmpty {
            out["apiKeyHelper"] = helper
        } else {
            out.removeValue(forKey: "apiKeyHelper")
        }
        if let v = settings.includeCoAuthoredBy { out["includeCoAuthoredBy"] = v } else { out.removeValue(forKey: "includeCoAuthoredBy") }
        if let v = settings.cleanupPeriodDays { out["cleanupPeriodDays"] = v } else { out.removeValue(forKey: "cleanupPeriodDays") }
        if let v = settings.outputStyle, !v.isEmpty { out["outputStyle"] = v } else { out.removeValue(forKey: "outputStyle") }
        if let v = settings.forceLoginMethod, !v.isEmpty { out["forceLoginMethod"] = v } else { out.removeValue(forKey: "forceLoginMethod") }
        if let v = settings.verbose { out["verbose"] = v } else { out.removeValue(forKey: "verbose") }

        return out
    }

    private static func serializePermissions(_ p: ClaudeSettings.Permissions) -> [String: Any] {
        var dict: [String: Any] = p.extras
        if !p.allow.isEmpty { dict["allow"] = p.allow } else { dict.removeValue(forKey: "allow") }
        if !p.deny.isEmpty  { dict["deny"]  = p.deny  } else { dict.removeValue(forKey: "deny") }
        if !p.ask.isEmpty   { dict["ask"]   = p.ask   } else { dict.removeValue(forKey: "ask") }
        return dict
    }
}
