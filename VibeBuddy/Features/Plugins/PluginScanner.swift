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

        guard let enumerator = fm.enumerator(
            at: cacheDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
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

        return out.sorted {
            $0.marketplaceName.localizedCaseInsensitiveCompare($1.marketplaceName) == .orderedAscending
                || ($0.marketplaceName == $1.marketplaceName
                    && $0.pluginName.localizedCaseInsensitiveCompare($1.pluginName) == .orderedAscending)
        }
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
            skillCount: count(
                in: bundleRoot.appending(path: "skills", directoryHint: .isDirectory),
                matching: { $0.lastPathComponent == "SKILL.md" }
            ),
            commandCount: count(
                in: bundleRoot.appending(path: "commands", directoryHint: .isDirectory),
                matching: { $0.pathExtension == "md" }
            ),
            agentCount: count(
                in: bundleRoot.appending(path: "agents", directoryHint: .isDirectory),
                matching: { $0.pathExtension == "md" }
            )
        )
    }

    private func count(
        in dir: URL,
        matching predicate: (URL) -> Bool
    ) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return 0 }
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let url as URL in enumerator where predicate(url) {
            count += 1
        }
        return count
    }
}
