import Foundation

/// Parse / serialize the `mcpServers` dictionary between untyped JSON and
/// the typed `[MCPServer]` list.
enum MCPCodec {

    static func parse(_ any: Any?) -> [MCPServer] {
        guard let dict = any as? [String: Any] else { return [] }
        return dict
            .map { (name, raw) in parseServer(name: name, raw: raw) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static let ownedKeys: Set<String> = [
        "type", "command", "args", "env", "url", "headers"
    ]

    private static func parseServer(name: String, raw: Any) -> MCPServer {
        let dict = (raw as? [String: Any]) ?? [:]
        let typeString = (dict["type"] as? String) ?? "stdio"
        let transport = MCPServer.Transport(rawValue: typeString) ?? .stdio

        let command = (dict["command"] as? String) ?? ""
        let args = (dict["args"] as? [String]) ?? []
        let env = (dict["env"] as? [String: String]) ?? [:]
        let url = (dict["url"] as? String) ?? ""
        let headers = (dict["headers"] as? [String: String]) ?? [:]

        var extras: [String: String] = [:]
        for (k, v) in dict where !ownedKeys.contains(k) {
            if let s = v as? String { extras[k] = s }
        }

        return MCPServer(
            name: name,
            transport: transport,
            command: command,
            args: args,
            env: env,
            url: url,
            headers: headers,
            extras: extras
        )
    }

    static func toJSON(_ servers: [MCPServer]) -> [String: Any] {
        var out: [String: Any] = [:]
        for server in servers {
            out[server.name] = serverToJSON(server)
        }
        return out
    }

    private static func serverToJSON(_ server: MCPServer) -> [String: Any] {
        var dict: [String: Any] = ["type": server.transport.rawValue]
        switch server.transport {
        case .stdio:
            dict["command"] = server.command
            if !server.args.isEmpty { dict["args"] = server.args }
            if !server.env.isEmpty { dict["env"] = server.env }
        case .http, .sse:
            dict["url"] = server.url
            if !server.headers.isEmpty { dict["headers"] = server.headers }
        }
        for (k, v) in server.extras { dict[k] = v }
        return dict
    }
}
