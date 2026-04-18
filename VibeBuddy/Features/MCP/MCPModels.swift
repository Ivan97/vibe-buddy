import Foundation

/// One entry in the `mcpServers` map. Claude Code reads these from two
/// places: the user's `~/.claude.json` (editable) and each installed
/// plugin's `plugin.json` under the `mcpServers` key (read-only, shipped
/// by the plugin). `scope` tells them apart so the editor can gate saves.
/// Unknown string fields round-trip through `extras` so new Claude Code
/// versions don't lose data on save.
struct MCPServer: Identifiable, Equatable, Sendable {
    var name: String
    var transport: Transport
    var command: String          // stdio
    var args: [String]           // stdio
    var env: [String: String]    // stdio
    var url: String              // http / sse
    var headers: [String: String] // http / sse
    var extras: [String: String] // unknown string fields
    var scope: Scope

    var id: String { name }

    enum Scope: Hashable, Sendable {
        case user
        case plugin(marketplace: String, pluginName: String)
    }

    var isEditable: Bool {
        if case .user = scope { return true }
        return false
    }

    /// `InstalledPlugin.id` when this server is shipped by a plugin.
    var pluginID: String? {
        if case .plugin(let marketplace, let name) = scope {
            return "\(name)@\(marketplace)"
        }
        return nil
    }

    enum Transport: String, Hashable, CaseIterable, Sendable {
        case stdio
        case http
        case sse

        var label: String {
            switch self {
            case .stdio: return "stdio"
            case .http:  return "HTTP"
            case .sse:   return "SSE"
            }
        }

        var icon: String {
            switch self {
            case .stdio: return "terminal"
            case .http:  return "network"
            case .sse:   return "dot.radiowaves.left.and.right"
            }
        }
    }

    static func empty(named name: String) -> MCPServer {
        MCPServer(
            name: name,
            transport: .stdio,
            command: "",
            args: [],
            env: [:],
            url: "",
            headers: [:],
            extras: [:],
            scope: .user
        )
    }
}
