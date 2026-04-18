import Foundation
import Testing
@testable import VibeBuddy

@Suite("GitUpdateChecker.findRepoRoot")
struct GitUpdateCheckerTests {

    @Test("returns the directory itself when it contains .git/")
    func rootWithGit() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(
            at: dir.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        #expect(GitUpdateChecker.findRepoRoot(startingFrom: dir) == dir.resolvingSymlinksInPath().standardizedFileURL)
    }

    @Test("walks up from a nested subdirectory to find the repo root")
    func nestedWalkUp() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        let nested = root.appending(path: "skills/mythril", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        #expect(
            GitUpdateChecker.findRepoRoot(startingFrom: nested)
                == root.resolvingSymlinksInPath().standardizedFileURL
        )
    }

    @Test("returns nil when no .git ancestor exists")
    func noGitAnywhere() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(GitUpdateChecker.findRepoRoot(startingFrom: dir) == nil)
    }

    @Test("accepts .git as a file (submodule/worktree case)")
    func gitAsFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gitFile = dir.appending(path: ".git")
        try "gitdir: /elsewhere\n".write(to: gitFile, atomically: true, encoding: .utf8)

        #expect(GitUpdateChecker.findRepoRoot(startingFrom: dir) == dir.resolvingSymlinksInPath().standardizedFileURL)
    }

    // MARK: - helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "gitroot-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
