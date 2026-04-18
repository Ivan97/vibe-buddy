import Foundation

/// Writes text files with an optional `.bak` sibling kept from the previous
/// revision. Atomic write is handled by `Data.write(options: .atomic)` —
/// Foundation writes to a temp file and renames, so partial writes aren't
/// observable by readers.
///
/// Symlink handling: by default the writer writes through symlinks so the
/// file at the resolved target is updated. Callers that want to warn the
/// user before following a link can inspect `describeSymlink(at:)` first.
enum SafeTextWriter {

    enum WriteError: Error, Equatable {
        case encodingFailed
    }

    /// Writes `text` to `url` atomically. When `makeBackup` is true and the
    /// target already exists, a sibling `.bak` copy is refreshed with the
    /// previous contents before the new version is written.
    static func write(
        _ text: String,
        to url: URL,
        makeBackup: Bool = true
    ) throws {
        guard let data = text.data(using: .utf8) else {
            throw WriteError.encodingFailed
        }

        let fm = FileManager.default
        if makeBackup, fm.fileExists(atPath: url.path) {
            let bak = url.appendingPathExtension("bak")
            // Best-effort: refresh backup; don't fail the write if we can't.
            try? fm.removeItem(at: bak)
            do {
                try fm.copyItem(at: url, to: bak)
            } catch {
                // ignore — backup is an extra safety net, not a hard
                // pre-condition of the write
            }
        }

        try ensureParentDirectoryExists(for: url)
        try data.write(to: url, options: .atomic)
    }

    /// Returns the final destination of `url` if it's a symlink, or `nil`
    /// if it's a regular file / doesn't exist. Useful for a pre-save prompt
    /// ("this edits the file at …, continue?").
    static func describeSymlink(at url: URL) -> URL? {
        let path = url.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let type = attrs[.type] as? FileAttributeType,
              type == .typeSymbolicLink else {
            return nil
        }
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
            return nil
        }
        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination)
        }
        return url.deletingLastPathComponent().appendingPathComponent(destination).standardized
    }

    private static func ensureParentDirectoryExists(for url: URL) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: parent.path, isDirectory: &isDir), isDir.boolValue {
            return
        }
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
    }
}
