import Foundation

/// One entry in the `mcpServers` map in `~/.claude.json`. The transport
/// determines which fields apply; unknown fields round-trip through
/// `extras` so new Claude Code versions don't lose data on save.
struct MCPServer: Identifiable, Equatable, Sendable {
    var name: String
    var transport: Transport
    var command: String          // stdio
    var args: [String]           // stdio
    var env: [String: String]    // stdio
    var url: String              // http / sse
    var headers: [String: String] // http / sse
    var extras: [String: String] // unknown string fields

    var id: String { name }

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
            extras: [:]
        )
    }
}
