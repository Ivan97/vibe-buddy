import Darwin
import Foundation

/// Discovers Claude Code slash commands. Pure function; runs off-main.
struct CommandScanner: Sendable {

    func scan(
        userCommandsDir: URL,
        pluginsDir: URL
    ) -> [CommandHandle] {
        var result: [CommandHandle] = []
        result.append(contentsOf: scanUser(at: userCommandsDir))
        result.append(contentsOf: scanPlugins(at: pluginsDir))
        return result
    }

    // MARK: - user

    private func scanUser(at root: URL) -> [CommandHandle] {
        let files = collectMarkdown(at: root)
        return files.compactMap { url -> CommandHandle? in
            let namespace = namespaceComponents(of: url, relativeTo: root)
            return makeHandle(url: url, namespace: namespace, scope: .user)
        }
        .sorted { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
    }

    // MARK: - plugins

    private func scanPlugins(at root: URL) -> [CommandHandle] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var commandsDirs: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "commands" else { continue }
            // Skip nested / unrelated command dirs (docs, .opencode, etc.)
            let parent = url.deletingLastPathComponent().lastPathComponent
            if parent == "docs" || parent.hasPrefix(".opencode") { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                commandsDirs.append(url)
            }
        }

        var result: [CommandHandle] = []
        for dir in commandsDirs {
            let pluginName = Self.pluginName(for: dir, pluginsRoot: root)
            let files = collectMarkdown(at: dir)
            for url in files {
                let namespace = namespaceComponents(of: url, relativeTo: dir)
                if let handle = makeHandle(url: url, namespace: namespace, scope: .plugin(pluginName: pluginName)) {
                    result.append(handle)
                }
            }
        }
        return result.sorted { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
    }

    // MARK: - helpers

    private func collectMarkdown(at root: URL) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "md" else { continue }
            // Skip docs localization and README-style files inside commands
            let name = url.deletingPathExtension().lastPathComponent.uppercased()
            if name == "README" || name == "LICENSE" { continue }
            let components = url.standardizedFileURL.pathComponents
            if components.contains("docs") || components.contains(".opencode") { continue }
            out.append(url)
        }
        return out
    }

    private func namespaceComponents(of url: URL, relativeTo root: URL) -> [String] {
        // On macOS `/var` and `/private/var` are the same directory via a
        // kernel-level symlink; URL's built-in resolvers don't always
        // collapse them consistently. POSIX realpath always does.
        let fileStem = Self.realpath(url.deletingPathExtension().path)
        var rootPath = Self.realpath(root.path)
        if !rootPath.hasSuffix("/") { rootPath += "/" }

        let relative: String
        if fileStem.hasPrefix(rootPath) {
            relative = String(fileStem.dropFirst(rootPath.count))
        } else {
            relative = fileStem
        }

        let parts = relative
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        // parts.last is the filename stem; everything before is the namespace.
        return parts.count <= 1 ? [] : Array(parts.dropLast())
    }

    private static func realpath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if Darwin.realpath(path, &buffer) != nil {
            return String(cString: buffer)
        }
        return path
    }

    private func makeHandle(
        url: URL,
        namespace: [String],
        scope: CommandHandle.Scope
    ) -> CommandHandle? {
        let stem = url.deletingPathExtension().lastPathComponent
        guard !stem.isEmpty else { return nil }
        let description = readDescription(at: url)
        return CommandHandle(
            id: url.path,
            name: stem,
            namespace: namespace,
            description: description,
            url: url,
            scope: scope
        )
    }

    private func readDescription(at url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        let parsed = FrontmatterCodec.parse(text)
        let schema = CommandFrontmatter(from: parsed.frontmatter)
        if let d = schema.description, !d.isEmpty {
            return String(d.prefix(160))
        }
        // Fall back to the first non-heading body line for commands that
        // ship with no frontmatter (the majority in the wild).
        for line in parsed.body.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            return String(trimmed.prefix(160))
        }
        return ""
    }

    private static func pluginName(for commandsDir: URL, pluginsRoot: URL) -> String {
        let full = commandsDir.standardizedFileURL.pathComponents
        let root = pluginsRoot.standardizedFileURL.pathComponents
        guard full.count > root.count else { return "unknown" }
        let tail = Array(full.dropFirst(root.count))
        if tail.first == "cache", tail.count > 1 { return tail[1] }
        return tail.first ?? "unknown"
    }
}
