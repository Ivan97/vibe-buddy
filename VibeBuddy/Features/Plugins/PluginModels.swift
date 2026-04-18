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

/// Count of things a plugin contributes, inferred by scanning its bundle.
struct PluginContributions: Equatable, Sendable {
    let skillCount: Int
    let commandCount: Int
    let agentCount: Int

    static let zero = PluginContributions(skillCount: 0, commandCount: 0, agentCount: 0)

    var total: Int { skillCount + commandCount + agentCount }
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
