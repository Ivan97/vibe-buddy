import Foundation
import Testing
@testable import VibeBuddy

@Suite("SkillClassifier")
struct SkillClassifierTests {

    @Test("classifies a plain user skill directory")
    func plainDirectory() throws {
        let env = try TempFS()
        let skillsDir = env.skillsDir
        try env.write(
            path: skillsDir.appending(path: "my-skill/SKILL.md"),
            text: """
            ---
            name: my-skill
            description: A local skill.
            ---
            body
            """
        )

        let handles = SkillClassifier().scan(userSkillsDir: skillsDir, pluginsDir: env.pluginsDir)
        #expect(handles.count == 1)
        let h = try #require(handles.first)
        #expect(h.name == "my-skill")
        #expect(h.description == "A local skill.")
        if case .user = h.scope { } else { Issue.record("expected .user scope, got \(h.scope)") }
    }

    @Test("classifies a symlinked skill and points skillMdURL at resolved target")
    func symlinkedSkill() throws {
        let env = try TempFS()
        // Target lives outside the skills dir
        let target = env.root.appending(path: "external/foo")
        try env.write(
            path: target.appending(path: "SKILL.md"),
            text: """
            ---
            name: foo
            description: External skill.
            ---
            """
        )
        try FileManager.default.createSymbolicLink(
            at: env.skillsDir.appending(path: "foo"),
            withDestinationURL: target
        )

        let handles = SkillClassifier().scan(userSkillsDir: env.skillsDir, pluginsDir: env.pluginsDir)
        #expect(handles.count == 1)
        let h = try #require(handles.first)
        if case .userSymlink(let linkTarget) = h.scope {
            #expect(linkTarget.standardizedFileURL == target.standardizedFileURL)
        } else {
            Issue.record("expected .userSymlink, got \(h.scope)")
        }
        #expect(h.skillMdURL.path == target.appending(path: "SKILL.md").path)
    }

    @Test("marks directories without SKILL.md as malformed")
    func missingSkillMdMalformed() throws {
        let env = try TempFS()
        try FileManager.default.createDirectory(
            at: env.skillsDir.appending(path: "empty-skill"),
            withIntermediateDirectories: true
        )
        let handles = SkillClassifier().scan(userSkillsDir: env.skillsDir, pluginsDir: env.pluginsDir)
        #expect(handles.count == 1)
        if case .malformed(let reason) = handles.first?.scope {
            #expect(reason.contains("SKILL.md"))
        } else {
            Issue.record("expected .malformed")
        }
    }

    @Test("marks loose .md files in the skills root as malformed")
    func looseFileMalformed() throws {
        let env = try TempFS()
        try env.write(
            path: env.skillsDir.appending(path: "loose.md"),
            text: "not a real skill"
        )
        let handles = SkillClassifier().scan(userSkillsDir: env.skillsDir, pluginsDir: env.pluginsDir)
        #expect(handles.count == 1)
        if case .malformed = handles.first?.scope { } else { Issue.record("expected .malformed") }
    }

    @Test("skips hidden files in the skills root")
    func skipsDotFiles() throws {
        let env = try TempFS()
        try env.write(path: env.skillsDir.appending(path: ".DS_Store"), text: "")
        let handles = SkillClassifier().scan(userSkillsDir: env.skillsDir, pluginsDir: env.pluginsDir)
        #expect(handles.isEmpty)
    }

    @Test("discovers plugin-provided skills and infers plugin name")
    func pluginSkills() throws {
        let env = try TempFS()
        try env.write(
            path: env.pluginsDir.appending(path: "cache/my-plugin/skills/a/SKILL.md"),
            text: """
            ---
            name: a
            description: Plugin skill A.
            ---
            """
        )
        try env.write(
            path: env.pluginsDir.appending(path: "cache/my-plugin/skills/b/SKILL.md"),
            text: """
            ---
            name: b
            description: Plugin skill B.
            ---
            """
        )

        let handles = SkillClassifier().scan(userSkillsDir: env.skillsDir, pluginsDir: env.pluginsDir)
        #expect(handles.count == 2)
        for h in handles {
            if case .plugin(let plugin) = h.scope {
                #expect(plugin == "my-plugin")
            } else {
                Issue.record("expected .plugin")
            }
        }
    }
}

// MARK: - helpers

private struct TempFS {
    let root: URL
    let skillsDir: URL
    let pluginsDir: URL

    init() throws {
        let id = UUID().uuidString
        root = FileManager.default.temporaryDirectory
            .appending(path: "VibeBuddy-SkillClassifier-\(id)", directoryHint: .isDirectory)
        skillsDir = root.appending(path: "skills", directoryHint: .isDirectory)
        pluginsDir = root.appending(path: "plugins", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
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
