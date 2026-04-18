import Foundation

/// Pure classifier — given the paths of `~/.claude/skills/` and
/// `~/.claude/plugins/`, produces the list of `SkillHandle` values the UI
/// should show. Does not write to disk; `Sendable` so it can run off-main.
struct SkillClassifier: Sendable {

    func scan(userSkillsDir: URL, pluginsDir: URL) -> [SkillHandle] {
        var handles: [SkillHandle] = []
        handles.append(contentsOf: scanUserDir(userSkillsDir))
        handles.append(contentsOf: scanPluginsDir(pluginsDir))
        return handles
    }

    // MARK: - user skills

    private func scanUserDir(_ dir: URL) -> [SkillHandle] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }

        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var out: [SkillHandle] = []
        for entry in entries {
            // Symbolic link? Resolve and classify.
            if let linkTarget = Self.resolveSymlink(at: entry) {
                if let handle = handleForDirectoryEntry(entry, resolvedDir: linkTarget, scope: .userSymlink(target: linkTarget)) {
                    out.append(handle)
                } else {
                    out.append(
                        malformedHandle(
                            at: entry,
                            reason: "Symbolic link has no SKILL.md at \(linkTarget.path)"
                        )
                    )
                }
                continue
            }

            // Loose file at the root of skills dir — not a valid skill.
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == false {
                if entry.lastPathComponent.hasPrefix(".") { continue }  // skip .DS_Store etc
                out.append(
                    malformedHandle(
                        at: entry,
                        reason: "Loose file — skills must be directories containing SKILL.md"
                    )
                )
                continue
            }

            // Plain directory: expect SKILL.md inside.
            if let handle = handleForDirectoryEntry(entry, resolvedDir: entry, scope: .user) {
                out.append(handle)
            } else {
                out.append(
                    malformedHandle(
                        at: entry,
                        reason: "Directory is missing SKILL.md"
                    )
                )
            }
        }
        return out.sorted { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
    }

    private func handleForDirectoryEntry(
        _ displayURL: URL,
        resolvedDir: URL,
        scope: SkillHandle.Scope
    ) -> SkillHandle? {
        let skillMd = resolvedDir.appending(path: "SKILL.md")
        guard FileManager.default.fileExists(atPath: skillMd.path) else { return nil }

        let (name, description) = readFrontmatter(at: skillMd)
        let displayName = name.isEmpty ? displayURL.lastPathComponent : name

        return SkillHandle(
            id: skillMd.path,
            name: displayName,
            description: description,
            displayURL: displayURL,
            skillMdURL: skillMd,
            scope: scope
        )
    }

    private func malformedHandle(at entry: URL, reason: String) -> SkillHandle {
        SkillHandle(
            id: entry.path,
            name: entry.lastPathComponent,
            description: reason,
            displayURL: entry,
            skillMdURL: entry,
            scope: .malformed(reason: reason)
        )
    }

    // MARK: - plugin skills

    private func scanPluginsDir(_ dir: URL) -> [SkillHandle] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }

        // Enumerate recursively looking for SKILL.md files.
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [SkillHandle] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "SKILL.md" else { continue }
            let pluginName = Self.pluginName(for: url, root: dir)
            let (name, description) = readFrontmatter(at: url)
            let dirName = url.deletingLastPathComponent().lastPathComponent
            let displayName = name.isEmpty ? dirName : name
            out.append(
                SkillHandle(
                    id: url.path,
                    name: displayName,
                    description: description,
                    displayURL: url.deletingLastPathComponent(),
                    skillMdURL: url,
                    scope: .plugin(pluginName: pluginName)
                )
            )
        }
        return out.sorted { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
    }

    /// Infers a plugin name from the first path segment inside
    /// `~/.claude/plugins/`. Not perfect — git-clone caches use
    /// `temp_git_<hash>` — but good enough for grouping and falls back to
    /// the component itself when nothing better is available.
    private static func pluginName(for skillURL: URL, root pluginsDir: URL) -> String {
        let fullPath = skillURL.standardizedFileURL.pathComponents
        let rootPath = pluginsDir.standardizedFileURL.pathComponents
        guard fullPath.count > rootPath.count + 1 else { return "unknown" }
        // pluginsDir typically resolves to .../plugins. The next component is
        // usually "cache", then the actual plugin directory name.
        let afterRoot = Array(fullPath.dropFirst(rootPath.count))
        if afterRoot.first == "cache", afterRoot.count > 1 {
            return afterRoot[1]
        }
        return afterRoot.first ?? "unknown"
    }

    // MARK: - frontmatter peek

    /// Light-weight peek for list rendering: just the name + description.
    /// Avoids running the full FrontmatterCodec for every discovered file
    /// (hundreds of them when plugins are many).
    private func readFrontmatter(at url: URL) -> (name: String, description: String) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ("", "")
        }
        let parsed = FrontmatterCodec.parse(text)
        let schema = SkillFrontmatter(from: parsed.frontmatter)
        return (schema.name, String(schema.description.prefix(160)))
    }

    // MARK: - helpers

    private static func resolveSymlink(at url: URL) -> URL? {
        let path = url.path
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let type = attrs[.type] as? FileAttributeType,
              type == .typeSymbolicLink else {
            return nil
        }
        guard let destination = try? fm.destinationOfSymbolicLink(atPath: path) else {
            return nil
        }
        let resolved: URL
        if destination.hasPrefix("/") {
            resolved = URL(fileURLWithPath: destination)
        } else {
            resolved = url.deletingLastPathComponent()
                .appendingPathComponent(destination)
                .standardizedFileURL
        }
        guard fm.fileExists(atPath: resolved.path) else { return nil }
        return resolved
    }
}

private extension SkillHandle {
    var sortKey: String { name.isEmpty ? displayURL.lastPathComponent : name }
}
