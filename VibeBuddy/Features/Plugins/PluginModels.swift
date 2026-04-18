import Foundation

/// Minimal typed view of a `plugin.json` file. Only the keys relevant for
/// listing are claimed; anything else is kept in `extras` so a display can
/// surface it without losing fidelity.
struct PluginManifest: Equatable, Sendable {
    let name: String
    let version: String?
    let description: String?
    let author: String?
    let homepage: String?
    let repository: String?
    let license: String?
    let keywords: [String]
    let extras: [String: String]
}

/// What a plugin contributes, inferred by scanning its bundle. Stores the
/// resolved paths so the detail view can render clickable item lists
/// (and set `Navigator.pendingSkillID` / `pendingCommandID` on click).
struct PluginContributions: Equatable, Sendable {
    /// One discovered contribution. `id` matches the corresponding handle
    /// id in the target module (SkillHandle / CommandHandle), so setting
    /// `Navigator.pendingXxxID = resource.id` selects it on jump.
    struct Resource: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let url: URL
    }

    let skills: [Resource]
    let commands: [Resource]
    let agents: [Resource]
    /// MCP servers declared inline in the plugin's `plugin.json` under the
    /// `mcpServers` field. `Resource.url` is the manifest file itself;
    /// `name` is the server key.
    let mcpServers: [Resource]

    static let zero = PluginContributions(skills: [], commands: [], agents: [], mcpServers: [])

    var skillCount: Int { skills.count }
    var commandCount: Int { commands.count }
    var agentCount: Int { agents.count }
    var mcpServerCount: Int { mcpServers.count }
    var total: Int { skillCount + commandCount + agentCount + mcpServerCount }
}

/// A discovered plugin on disk. Identity = `<pluginName>@<marketplace>` which
/// matches the key Claude Code uses in `settings.json`'s `enabledPlugins`.
struct InstalledPlugin: Identifiable, Equatable, Sendable {
    let id: String              // <pluginName>@<marketplaceName>
    let marketplaceName: String
    let pluginName: String
    let bundleRoot: URL         // e.g. plugins/cache/<marketplace>/<plugin>/<version>/
    let manifestURL: URL        // <bundleRoot>/.claude-plugin/plugin.json
    let manifest: PluginManifest
    let contributions: PluginContributions
    var isEnabled: Bool
}
