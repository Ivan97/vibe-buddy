import Foundation

/// Thin wrapper around the `claude` CLI that lives on $PATH. Used by the
/// Plugins module to invoke non-interactive subcommands like
/// `plugin update <id>`. Resolution is lazy — we don't probe until the
/// user actually clicks an action that needs the binary.
enum ClaudeCLI {

    enum InvocationError: Error, LocalizedError {
        case notFound
        case failed(exitCode: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Couldn't find the `claude` CLI on PATH. Install Claude Code and try again."
            case .failed(let code, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty
                    ? "claude CLI exited with status \(code)."
                    : trimmed
            }
        }
    }

    /// Common locations macOS installs might drop `claude` at. Tried in
    /// order; first executable wins. Falls back to a login-shell PATH
    /// lookup so users with bespoke installs (asdf, nvm, ~/.local/bin)
    /// still work.
    private static let fallbackPaths: [String] = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "\(NSHomeDirectory())/.local/bin/claude",
        "/usr/bin/claude"
    ]

    /// Resolve the absolute path of `claude`. `nil` if we can't find it.
    static func resolve() -> URL? {
        let fm = FileManager.default
        for path in fallbackPaths where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return resolveViaLoginShell()
    }

    /// Runs `claude <args>` with no stdin. Returns trimmed stdout on
    /// success, throws `InvocationError.failed` with stderr on non-zero
    /// exit. Off the main actor — safe to `await` from SwiftUI actions.
    static func run(_ args: [String], timeout: TimeInterval = 180) async throws -> String {
        guard let exe = resolve() else { throw InvocationError.notFound }
        return try await runProcess(exe: exe, args: args, timeout: timeout)
    }

    // MARK: - internals

    /// Ask the user's login shell where `claude` lives — handles the
    /// asdf / nvm / bespoke PATH cases that the hardcoded list misses.
    /// `zsh -l -c "command -v claude"` reads the login profile (~/.zprofile
    /// / ~/.zshrc) so PATH reflects what the user actually sees in Terminal.
    private static func resolveViaLoginShell() -> URL? {
        let shell = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        let p = Process()
        p.executableURL = shell
        p.arguments = ["-l", "-c", "command -v claude"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return nil
        }
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, FileManager.default.isExecutableFile(atPath: raw) else {
            return nil
        }
        return URL(fileURLWithPath: raw)
    }

    private static func runProcess(
        exe: URL,
        args: [String],
        timeout: TimeInterval
    ) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe

            // Kill the process if it runs past `timeout` — `claude plugin
            // update` over a slow network is normally fast, but we don't
            // want a hung process to wedge the UI forever.
            let killer = DispatchWorkItem { [weak p] in
                p?.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

            p.terminationHandler = { process in
                killer.cancel()
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    cont.resume(returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    cont.resume(throwing: InvocationError.failed(
                        exitCode: process.terminationStatus,
                        stderr: stderr.isEmpty ? stdout : stderr
                    ))
                }
            }

            do {
                try p.run()
            } catch {
                killer.cancel()
                cont.resume(throwing: error)
            }
        }
    }
}
