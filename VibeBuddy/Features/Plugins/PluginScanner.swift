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
            let contributions = scanContributions(in: bundleRoot)

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

    /// Collapse duplicate `<marketplace>/<plugin>` bundles to the single
    /// most recently modified version. Claude Code's cache keeps stale
    /// versions around (e.g. `feature-dev/` has four commit-hash siblings);
    /// surfacing all of them just clutters the list without adding value.
    /// Using bundle-root mtime as the "latest" proxy works across semver
    /// strings and git-hash versions alike.
    private func dedupByLatestVersion(_ plugins: [InstalledPlugin]) -> [InstalledPlugin] {
        let fm = FileManager.default
        var picked: [String: InstalledPlugin] = [:]  // key = id, value = winner so far
        var pickedMtime: [String: Date] = [:]

        for plugin in plugins {
            let mtime = (try? fm.attributesOfItem(atPath: plugin.bundleRoot.path)[.modificationDate]) as? Date ?? .distantPast
            if let existing = pickedMtime[plugin.id], existing >= mtime {
                continue  // keep the earlier (more recent) winner
            }
            picked[plugin.id] = plugin
            pickedMtime[plugin.id] = mtime
        }
        return Array(picked.values)
    }

    // MARK: - helpers

    private static func marketplaceName(for bundleRoot: URL, root: URL) -> String {
        let components = bundleRoot.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        let tail = Array(components.dropFirst(rootComponents.count))
        // Expect tail ≈ [<marketplace>, <plugin>, <version>]
        return tail.first ?? "unknown"
    }

    private func scanContributions(in bundleRoot: URL) -> PluginContributions {
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
            )
        )
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
