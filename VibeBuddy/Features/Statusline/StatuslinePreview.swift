import Foundation

/// Runs a statusline command the way Claude Code does: stdin is a JSON
/// object carrying session context, stdout becomes the rendered line.
/// Used only for the Preview button — never touches disk.
enum StatuslinePreview {

    struct Result: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        let durationMs: Int
    }

    enum PreviewError: Error {
        case emptyCommand
        case launchFailed(String)
    }

    static let contextTemplate: String = """
    {
      "hook_event_name": "Status",
      "session_id": "preview-session",
      "transcript_path": "",
      "cwd": "\(FileManager.default.currentDirectoryPath)",
      "model": {
        "id": "claude-opus-4-7",
        "display_name": "Claude Opus 4.7"
      },
      "workspace": {
        "current_dir": "\(FileManager.default.currentDirectoryPath)",
        "project_dir": "\(FileManager.default.currentDirectoryPath)"
      },
      "version": "vibe-buddy-preview"
    }
    """

    /// Runs the command through `/bin/sh -c` with the context JSON on stdin
    /// and returns captured output. Never throws for non-zero exit; the
    /// caller inspects `exitCode` in the result.
    static func run(
        command: String,
        context: String = contextTemplate,
        timeout: TimeInterval = 5
    ) async throws -> Result {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PreviewError.emptyCommand }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let start = Date()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", trimmed]

                let stdin = Pipe()
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardInput = stdin
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: PreviewError.launchFailed(error.localizedDescription))
                    return
                }

                // Feed context JSON on stdin then close.
                stdin.fileHandleForWriting.write(Data(context.utf8))
                try? stdin.fileHandleForWriting.close()

                // Enforce timeout.
                let deadline = DispatchTime.now() + .milliseconds(Int(timeout * 1000))
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) { [weak process] in
                    if let process, process.isRunning {
                        process.terminate()
                    }
                }

                process.waitUntilExit()

                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)

                continuation.resume(returning: Result(
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus,
                    durationMs: durationMs
                ))
            }
        }
    }
}
