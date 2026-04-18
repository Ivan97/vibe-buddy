import Foundation
import Testing
@testable import VibeBuddy

@Suite("SafeTextWriter")
struct SafeTextWriterTests {

    @Test("writes a new file atomically")
    func writesNewFile() throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "agent.md")
        try SafeTextWriter.write("hello", to: url)
        let read = try String(contentsOf: url, encoding: .utf8)
        #expect(read == "hello")
    }

    @Test("creates a .bak on overwrite")
    func backsUpOnOverwrite() throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "agent.md")
        try SafeTextWriter.write("first", to: url)
        try SafeTextWriter.write("second", to: url)

        let bak = url.appendingPathExtension("bak")
        let bakContents = try String(contentsOf: bak, encoding: .utf8)
        let curContents = try String(contentsOf: url, encoding: .utf8)
        #expect(bakContents == "first")
        #expect(curContents == "second")
    }

    @Test("skipping backup does not create .bak")
    func skipsBackupWhenRequested() throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "agent.md")
        try SafeTextWriter.write("first", to: url, makeBackup: false)
        try SafeTextWriter.write("second", to: url, makeBackup: false)

        let bak = url.appendingPathExtension("bak")
        #expect(FileManager.default.fileExists(atPath: bak.path) == false)
    }

    @Test("creates missing parent directories")
    func createsIntermediates() throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "nested/dir/agent.md")
        try SafeTextWriter.write("hello", to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("describeSymlink returns nil for regular file")
    func describeSymlinkNilForRegular() throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "regular.md")
        try SafeTextWriter.write("x", to: url)
        #expect(SafeTextWriter.describeSymlink(at: url) == nil)
    }

    @Test("describeSymlink resolves absolute link target")
    func describeSymlinkResolvesAbsolute() throws {
        let dir = try makeTempDir()
        let target = dir.appending(path: "target.md")
        try SafeTextWriter.write("t", to: target)
        let link = dir.appending(path: "link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let resolved = SafeTextWriter.describeSymlink(at: link)
        #expect(resolved?.standardizedFileURL == target.standardizedFileURL)
    }

    // MARK: - helper

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "VibeBuddyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
