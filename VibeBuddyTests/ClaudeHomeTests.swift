import Foundation
import Testing
@testable import VibeBuddy

@Suite("ClaudeHome")
struct ClaudeHomeTests {
    @Test("defaults to ~/.claude when CLAUDE_CONFIG_DIR is unset")
    func usesHomeDirectoryDefault() {
        let home = URL(fileURLWithPath: "/Users/alice", isDirectory: true)
        let sut = ClaudeHome.discover(environment: [:], homeDirectory: home)
        #expect(sut.url.path == "/Users/alice/.claude")
    }

    @Test("respects CLAUDE_CONFIG_DIR when set")
    func honorsEnvOverride() {
        let sut = ClaudeHome.discover(
            environment: ["CLAUDE_CONFIG_DIR": "/tmp/my-claude"],
            homeDirectory: URL(fileURLWithPath: "/Users/alice", isDirectory: true)
        )
        #expect(sut.url.path == "/tmp/my-claude")
    }

    @Test("treats empty CLAUDE_CONFIG_DIR as unset")
    func ignoresEmptyEnvOverride() {
        let home = URL(fileURLWithPath: "/Users/alice", isDirectory: true)
        let sut = ClaudeHome.discover(
            environment: ["CLAUDE_CONFIG_DIR": ""],
            homeDirectory: home
        )
        #expect(sut.url.path == "/Users/alice/.claude")
    }

    @Test("exposes expected subpaths")
    func subpaths() {
        let sut = ClaudeHome(url: URL(fileURLWithPath: "/tmp/x", isDirectory: true))
        #expect(sut.projectsDir.lastPathComponent == "projects")
        #expect(sut.settingsFile.lastPathComponent == "settings.json")
        #expect(sut.commandsDir.lastPathComponent == "commands")
        #expect(sut.agentsDir.lastPathComponent == "agents")
        #expect(sut.skillsDir.lastPathComponent == "skills")
        #expect(sut.pluginsDir.lastPathComponent == "plugins")
    }
}
