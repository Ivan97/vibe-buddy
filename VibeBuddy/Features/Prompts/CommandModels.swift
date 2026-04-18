import Foundation

/// Represents one discovered slash command on disk. `namespace` reflects
/// the subdirectory structure under `commands/` and becomes part of the
/// invocation slug (`commands/frontend/lint.md` → `/frontend:lint`).
struct CommandHandle: Identifiable, Hashable, Sendable {
    let id: String            // resolved file path (globally unique)
    let name: String          // filename stem without `.md`
    let namespace: [String]   // empty for flat; e.g. ["frontend"] for frontend/lint
    let description: String   // first-line preview for list rows
    let url: URL
    let scope: Scope

    enum Scope: Hashable, Sendable {
        case user                                               // ~/.claude/commands/
        case plugin(marketplace: String, pluginName: String)    // ~/.claude/plugins/cache/<marketplace>/<plugin>/.../commands/
    }

    /// Matches `InstalledPlugin.id` when this command is plugin-provided.
    var pluginID: String? {
        if case .plugin(let marketplace, let name) = scope {
            return "\(name)@\(marketplace)"
        }
        return nil
    }

    /// User-facing invocation like `frontend:lint` or `review`.
    var invocationSlug: String {
        namespace.isEmpty ? name : namespace.joined(separator: ":") + ":" + name
    }

    /// Sidebar sort key — namespace first so grouped commands cluster.
    var sortKey: String {
        namespace.joined(separator: "/") + "/" + name
    }

    var isEditable: Bool {
        switch scope {
        case .user:   return true
        case .plugin: return false
        }
    }

    var section: Section {
        switch scope {
        case .user:   return .user
        case .plugin: return .plugin
        }
    }

    enum Section: String, CaseIterable, Hashable, Sendable {
        case user, plugin

        var title: String {
            switch self {
            case .user:   return "User"
            case .plugin: return "Plugin-provided"
            }
        }
    }
}
