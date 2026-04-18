import Foundation

/// The three config files that Claude Code reads. `.claude.json` sits next
/// to the home dir (not inside `.claude/`) and is where MCP servers + a
/// pile of internal state live. `settings.json` / `settings.local.json`
/// live inside `.claude/` and carry user-chosen options like model,
/// theme, permissions, and env.
enum SettingsTarget: String, CaseIterable, Identifiable, Hashable, Sendable {
    case main         // ~/.claude.json
    case global       // ~/.claude/settings.json
    case local        // ~/.claude/settings.local.json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main:   return "Main config"
        case .global: return "Global settings"
        case .local:  return "Local settings"
        }
    }

    var subtitle: String {
        switch self {
        case .main:
            return "~/.claude.json — MCP, project index, and internal state"
        case .global:
            return "~/.claude/settings.json — shared defaults"
        case .local:
            return "~/.claude/settings.local.json — machine-only overrides (usually permissions)"
        }
    }

    var systemImage: String {
        switch self {
        case .main:   return "doc.text.fill"
        case .global: return "gearshape.fill"
        case .local:  return "gearshape.2.fill"
        }
    }

    func url(in home: ClaudeHome) -> URL {
        switch self {
        case .main:   return home.mainConfigFile
        case .global: return home.settingsFile
        case .local:  return home.url.appending(path: "settings.local.json")
        }
    }

    /// `true` if this file participates in the schema-aware form. `.main`
    /// (aka `~/.claude.json`) is mostly internal state — the form still
    /// exposes the handful of user-facing keys that do appear there, but
    /// the banner warns the user to tread carefully.
    var isPrimarilyUserEditable: Bool {
        switch self {
        case .main:              return false
        case .global, .local:    return true
        }
    }
}
