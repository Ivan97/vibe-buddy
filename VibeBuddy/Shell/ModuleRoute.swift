import Foundation

enum ModuleRoute: String, CaseIterable, Identifiable, Hashable, Sendable {
    case sessions
    case prompts
    case skills
    case subagents
    case statusline
    case mcp
    case hooks
    case plugins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions:   return "Sessions"
        case .prompts:    return "Prompts"
        case .skills:     return "Skills"
        case .subagents:  return "Subagents"
        case .statusline: return "Statusline"
        case .mcp:        return "MCP"
        case .hooks:      return "Hooks"
        case .plugins:    return "Plugins"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions:   return "bubble.left.and.bubble.right"
        case .prompts:    return "text.quote"
        case .skills:     return "wand.and.stars"
        case .subagents:  return "person.2"
        case .statusline: return "menubar.rectangle"
        case .mcp:        return "bolt.horizontal"
        case .hooks:      return "link"
        case .plugins:    return "puzzlepiece.extension"
        }
    }

    /// Phase in which this module ships its real feature (0 = already live).
    var phase: Int {
        switch self {
        case .sessions, .subagents, .skills, .prompts,
             .statusline, .mcp, .hooks, .plugins:    return 0
        }
    }

    var section: Section {
        switch self {
        case .sessions:                        return .data
        case .prompts, .skills, .subagents:    return .authoring
        case .statusline, .mcp, .hooks:        return .config
        case .plugins:                         return .ecosystem
        }
    }

    enum Section: String, CaseIterable, Hashable {
        case data, authoring, config, ecosystem

        var title: String {
            switch self {
            case .data:      return "Data"
            case .authoring: return "Authoring"
            case .config:    return "Config"
            case .ecosystem: return "Ecosystem"
            }
        }
    }
}
