import Foundation

/// Walks `~/.claude/plugins/cache/` to find installed plugin bundles. Layout
/// observed: `cache/<marketplace>/<plugin>/<version>/.claude-plugin/plugin.json`.
/// Temporary git-clone caches (`cache/temp_git_*`) are treated like any other
/// marketplace source so unversioned manifests still surface — the user can
/// decide whether to keep them.
struct PluginScanner: Sendable {

    func scan(pluginsDir: URL, enabledPlugins: Set<String>) -> [InstalledPlugin] {
        let fm = FileManager.default
        let cacheDir = pluginsDir.appending(path: "cache", directoryHint: .isDirectory)
        guard fm.fileExists(atPath: cacheDir.path) else { return [] }

        // Do NOT pass `.skipsHiddenFiles` — plugin manifests live at
        // `<bundle>/.claude-plugin/plugin.json`, and the leading dot in
        // `.claude-plugin` would otherwise make the enumerator refuse to
        // descend into the dir and report zero installed plugins.
        guard let enumerator = fm.enumerator(
            at: cacheDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }

        var out: [InstalledPlugin] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "plugin.json",
                  url.deletingLastPathComponent().lastPathComponent == ".claude-plugin"
            else { continue }

            guard let manifest = try? PluginManifestParser.parse(url: url) else { continue }

            let bundleRoot = url
                .deletingLastPathComponent()  // .claude-plugin
                .deletingLastPathComponent()  // <version>
            let marketplaceName = Self.marketplaceName(for: bundleRoot, root: cacheDir)
            let effectiveName = manifest.name.isEmpty
                ? bundleRoot.deletingLastPathComponent().lastPathComponent
                : manifest.name
            let identifier = "\(effectiveName)@\(marketplaceName)"

            // Pull mcpServers out of the raw manifest JSON — plugins can
            // inline these under plugin.json's `mcpServers` key.
            let mcpServerNames = Self.mcpServerNames(fromManifestURL: url)
            let contributions = scanContributions(
                in: bundleRoot,
                manifestURL: url,
                mcpServerNames: mcpServerNames
            )

            out.append(
                InstalledPlugin(
                    id: identifier,
                    marketplaceName: marketplaceName,
                    pluginName: effectiveName,
                    bundleRoot: bundleRoot,
                    manifestURL: url,
                    manifest: manifest,
                    contributions: contributions,
                    isEnabled: enabledPlugins.contains(identifier)
                )
            )
        }

        return dedupByLatestVersion(out).sorted {
            $0.marketplaceName.localizedCaseInsensitiveCompare($1.marketplaceName) == .orderedAscending
                || ($0.marketplaceName == $1.marketplaceName
                    && $0.pluginName.localizedCaseInsensitiveCompare($1.pluginName) == .orderedAscending)
        }
    }

    /// Collapse duplicate `<marketplace>/<plugin>` bundles. Claude Code's
    /// cache keeps stale versions around (e.g. `feature-dev/` has four
    /// commit-hash siblings); surfacing all of them just clutters the list.
    ///
    /// Picking strategy, in order:
    ///   1. Prefer the bundle whose `manifest.version` compares highest
    ///      under numeric-aware string compare ("12.1.10" > "12.1.9").
    ///      This fixes `claude plugin update` racing with mtime — the new
    ///      bundle dir sometimes carries a git-commit mtime that's older
    ///      than the existing cache entry.
    ///   2. If neither side has a parseable version, fall back to
    ///      bundle-root mtime (works for commit-hash-named bundles where
    ///      no semver exists).
    private struct Candidate {
        let plugin: InstalledPlugin
        let mtime: Date
        var version: String? { plugin.manifest.version }
    }

    private func dedupByLatestVersion(_ plugins: [InstalledPlugin]) -> [InstalledPlugin] {
        let fm = FileManager.default
        var picked: [String: Candidate] = [:]

        for plugin in plugins {
            let mtime = (try? fm.attributesOfItem(atPath: plugin.bundleRoot.path)[.modificationDate]) as? Date ?? .distantPast
            let next = Candidate(plugin: plugin, mtime: mtime)
            if let current = picked[plugin.id], !Self.shouldReplace(current: current, with: next) {
                continue
            }
            picked[plugin.id] = next
        }
        return picked.values.map(\.plugin)
    }

    /// `true` when `new` is a better choice than `current` — newer version
    /// first, then newer mtime as a tiebreak.
    private static func shouldReplace(current: Candidate, with new: Candidate) -> Bool {
        if let cv = current.version, !cv.isEmpty,
           let nv = new.version, !nv.isEmpty {
            switch cv.compare(nv, options: .numeric) {
            case .orderedAscending:  return true     // new is higher → replace
            case .orderedDescending: return false    // current stays
            case .orderedSame:       break           // fall through to mtime
            }
        }
        return new.mtime > current.mtime
    }

    // MARK: - helpers

    private static func marketplaceName(for bundleRoot: URL, root: URL) -> String {
        let components = bundleRoot.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        let tail = Array(components.dropFirst(rootComponents.count))
        // Expect tail ≈ [<marketplace>, <plugin>, <version>]
        return tail.first ?? "unknown"
    }

    private func scanContributions(
        in bundleRoot: URL,
        manifestURL: URL,
        mcpServerNames: [String]
    ) -> PluginContributions {
        PluginContributions(
            skills: collect(
                in: bundleRoot.appending(path: "skills", directoryHint: .isDirectory),
                matching: { $0.lastPathComponent == "SKILL.md" },
                name: { $0.deletingLastPathComponent().lastPathComponent }
            ),
            commands: collect(
                in: bundleRoot.appending(path: "commands", directoryHint: .isDirectory),
                matching: { $0.pathExtension == "md" },
                name: { $0.deletingPathExtension().lastPathComponent }
            ),
            agents: collect(
                in: bundleRoot.appending(path: "agents", directoryHint: .isDirectory),
                matching: { $0.pathExtension == "md" },
                name: { $0.deletingPathExtension().lastPathComponent }
            ),
            mcpServers: mcpServerNames
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .map { name in
                    PluginContributions.Resource(
                        // Server names are the keys the user sees in MCP
                        // mcpServers{}. Prefixed with manifest path to keep
                        // ids globally unique across plugins that happen to
                        // ship a server with the same name.
                        id: "mcp:\(manifestURL.path)#\(name)",
                        name: name,
                        url: manifestURL
                    )
                }
        )
    }

    private static func mcpServerNames(fromManifestURL url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any],
              let servers = dict["mcpServers"] as? [String: Any] else {
            return []
        }
        return Array(servers.keys)
    }

    private func collect(
        in dir: URL,
        matching predicate: (URL) -> Bool,
        name: (URL) -> String
    ) -> [PluginContributions.Resource] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [PluginContributions.Resource] = []
        for case let url as URL in enumerator where predicate(url) {
            out.append(PluginContributions.Resource(
                id: url.path,
                name: name(url),
                url: url
            ))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
