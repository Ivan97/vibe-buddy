import Foundation

/// Compares a local git checkout against its default-branch remote tip.
/// Shells out to `/usr/bin/git` (Xcode Command Line Tools ship it) rather
/// than pulling in libgit2 — saves a dep and matches what Claude Code
/// itself does under the hood when cloning plugins.
///
/// The caller provides a directory URL; we walk up to find the enclosing
/// `.git` dir (handles the common case where the skill/plugin lives in a
/// subfolder of its repo, e.g. `<repo>/skills/mythril/`).
enum GitUpdateChecker {

    /// Per-entity update state, carried on the Store and rendered by the
    /// list view. `.unchecked` is the default; UI shouldn't surface it as
    /// anything — the user must actively check first so we don't fire
    /// network I/O on every app launch.
    enum Status: Equatable, Sendable {
        case unchecked
        case checking
        case upToDate(localSHA: String, checkedAt: Date)
        case updateAvailable(localSHA: String, remoteSHA: String, checkedAt: Date)
        /// No `.git` dir found walking up from the start — e.g. a plain
        /// copy-pasted skill, no marketplace linkage.
        case notTracked
        case error(String)

        var lastCheckedAt: Date? {
            switch self {
            case .upToDate(_, let at), .updateAvailable(_, _, let at):
                return at
            default:
                return nil
            }
        }

        var hasUpdate: Bool {
            if case .updateAvailable = self { return true }
            return false
        }

        var isInFlight: Bool {
            if case .checking = self { return true }
            return false
        }
    }

    /// Walks up from `start` looking for the nearest directory that
    /// contains `.git` (either a dir or a file — submodules/worktrees
    /// use a `.git` *file* pointing at the real gitdir). Returns the
    /// containing directory (repo root), or nil if none found before
    /// hitting `/`.
    static func findRepoRoot(startingFrom start: URL) -> URL? {
        let fm = FileManager.default
        var current = start.resolvingSymlinksInPath().standardizedFileURL
        // Guard against symlink cycles / pathological inputs.
        var hops = 0
        while hops < 64 {
            hops += 1
            let gitPath = current.appending(path: ".git").path
            if fm.fileExists(atPath: gitPath) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }   // reached "/"
            current = parent
        }
        return nil
    }

    /// Runs git to compare local HEAD with remote origin HEAD.
    /// Returns a `Status` — callers typically replace `.checking` with
    /// this result. Off the main actor; safe to call from a Task.
    static func check(repoRoot: URL, gitPath: String = "/usr/bin/git") async -> Status {
        let now = Date()

        let local: String
        do {
            local = try await run(gitPath, args: ["-C", repoRoot.path, "rev-parse", "HEAD"])
        } catch {
            return .error("rev-parse: \((error as NSError).localizedDescription)")
        }
        guard local.count >= 40 else {
            return .error("rev-parse returned unexpected output")
        }

        let remote: String
        do {
            // ls-remote format: "<sha>\tHEAD\n" (possibly multiple lines;
            // origin HEAD is the one tied to the default branch).
            let raw = try await run(
                gitPath,
                args: ["-C", repoRoot.path, "ls-remote", "origin", "HEAD"]
            )
            guard let first = raw.split(whereSeparator: { $0.isWhitespace }).first else {
                return .error("ls-remote returned empty output")
            }
            remote = String(first)
        } catch {
            return .error("ls-remote: \((error as NSError).localizedDescription)")
        }
        guard remote.count >= 40 else {
            return .error("ls-remote returned unexpected output")
        }

        let localShort = String(local.prefix(40))
        let remoteShort = String(remote.prefix(40))
        if localShort == remoteShort {
            return .upToDate(localSHA: localShort, checkedAt: now)
        }
        return .updateAvailable(
            localSHA: localShort,
            remoteSHA: remoteShort,
            checkedAt: now
        )
    }

    // MARK: - process

    /// Fires off `gitPath args…`, returns trimmed stdout. Non-zero exit
    /// throws an NSError whose `localizedDescription` is the trimmed
    /// stderr so callers can surface it directly.
    private static func run(_ gitPath: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: gitPath)
            p.arguments = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe

            p.terminationHandler = { process in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    let str = String(data: outData, encoding: .utf8) ?? ""
                    cont.resume(returning: str.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let errStr = (String(data: errData, encoding: .utf8) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let desc = errStr.isEmpty ? "exit \(process.terminationStatus)" : errStr
                    cont.resume(throwing: NSError(
                        domain: "GitUpdateChecker",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: desc]
                    ))
                }
            }

            do {
                try p.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
