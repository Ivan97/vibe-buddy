import Foundation
import Testing
@testable import VibeBuddy

@Suite("CommandScanner")
struct CommandScannerTests {

    @Test("scans a flat user command file")
    func flatUserCommand() throws {
        let fs = try TempFS()
        try fs.write(
            path: fs.commandsDir.appending(path: "review.md"),
            text: """
            ---
            description: Do a review
            ---
            body
            """
        )
        let handles = CommandScanner().scan(
            userCommandsDir: fs.commandsDir,
            pluginsDir: fs.pluginsDir
        )
        #expect(handles.count == 1)
        let h = try #require(handles.first)
        #expect(h.name == "review")
        #expect(h.namespace.isEmpty)
        #expect(h.invocationSlug == "review")
        #expect(h.description == "Do a review")
        if case .user = h.scope {} else { Issue.record("expected .user") }
    }

    @Test("captures subdir namespace like frontend/lint")
    func subdirNamespace() throws {
        let fs = try TempFS()
        try fs.write(
            path: fs.commandsDir.appending(path: "frontend/lint.md"),
            text: "Run the frontend linter."
        )
        let handles = CommandScanner().scan(
            userCommandsDir: fs.commandsDir,
            pluginsDir: fs.pluginsDir
        )
        #expect(handles.count == 1)
        let h = try #require(handles.first)
        #expect(h.name == "lint")
        #expect(h.namespace == ["frontend"])
        #expect(h.invocationSlug == "frontend:lint")
    }

    @Test("falls back to first non-heading line when no frontmatter")
    func bodyFallbackDescription() throws {
        let fs = try TempFS()
        try fs.write(
            path: fs.commandsDir.appending(path: "noop.md"),
            text: """
            # Noop

            Runs absolutely nothing.
            """
        )
        let handles = CommandScanner().scan(
            userCommandsDir: fs.commandsDir,
            pluginsDir: fs.pluginsDir
        )
        let h = try #require(handles.first)
        #expect(h.description == "Runs absolutely nothing.")
    }

    @Test("discovers plugin commands and skips docs / opencode variants")
    func pluginDiscovery() throws {
        let fs = try TempFS()
        // Real plugin command
        try fs.write(
            path: fs.pluginsDir.appending(path: "cache/official/my-plugin/1.0.0/commands/build.md"),
            text: """
            ---
            description: Build it
            ---
            """
        )
        // Docs-localized variant that should be skipped
        try fs.write(
            path: fs.pluginsDir.appending(path: "cache/official/my-plugin/1.0.0/docs/ja-JP/commands/build.md"),
            text: "スキップ"
        )
        // OpenCode variant that should be skipped
        try fs.write(
            path: fs.pluginsDir.appending(path: "cache/official/my-plugin/1.0.0/.opencode/commands/build.md"),
            text: "skip"
        )

        let handles = CommandScanner().scan(
            userCommandsDir: fs.commandsDir,
            pluginsDir: fs.pluginsDir
        )
        #expect(handles.count == 1)
        let h = try #require(handles.first)
        if case .plugin(let marketplace, let plugin) = h.scope {
            #expect(marketplace == "official")
            #expect(plugin == "my-plugin")
        } else {
            Issue.record("expected .plugin")
        }
    }

    @Test("skips README and LICENSE files")
    func skipsReadme() throws {
        let fs = try TempFS()
        try fs.write(path: fs.commandsDir.appending(path: "README.md"), text: "readme")
        try fs.write(path: fs.commandsDir.appending(path: "LICENSE.md"), text: "license")
        try fs.write(path: fs.commandsDir.appending(path: "real.md"), text: "real body")
        let handles = CommandScanner().scan(
            userCommandsDir: fs.commandsDir,
            pluginsDir: fs.pluginsDir
        )
        #expect(handles.map(\.name) == ["real"])
    }
}

private struct TempFS {
    let root: URL
    let commandsDir: URL
    let pluginsDir: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "VibeBuddy-Commands-\(UUID().uuidString)", directoryHint: .isDirectory)
        commandsDir = root.appending(path: "commands", directoryHint: .isDirectory)
        pluginsDir = root.appending(path: "plugins", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
    }

    func write(path: URL, text: String) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: path, atomically: true, encoding: .utf8)
    }
}
