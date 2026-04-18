import Foundation
import Testing
@testable import VibeBuddy

@Suite("SessionSummary liveness & working")
struct SessionLivenessTests {

    private func summary(
        lastActivity: Date,
        inProgress: Bool = false
    ) -> SessionSummary {
        SessionSummary(
            id: "session-id",
            path: URL(fileURLWithPath: "/tmp/s.jsonl"),
            projectPath: "/tmp",
            projectSlug: "-tmp",
            firstPrompt: nil,
            messageCount: 1,
            lastActivity: lastActivity,
            claudeVersion: nil,
            gitBranch: nil,
            inProgress: inProgress
        )
    }

    // MARK: - isLive (window alive, mtime-based)

    @Test("session modified seconds ago is live regardless of in-progress state")
    func freshIsLive() {
        let now = Date()
        // Claude Code writes something on every turn and hook fire, so
        // recent mtime means the window is still open even when the AI is
        // idle between user questions.
        let idle = summary(lastActivity: now.addingTimeInterval(-10), inProgress: false)
        let working = summary(lastActivity: now.addingTimeInterval(-10), inProgress: true)
        #expect(idle.isLive(now: now) == true)
        #expect(working.isLive(now: now) == true)
    }

    @Test("session at the mtime threshold boundary is not live")
    func thresholdBoundary() {
        let now = Date()
        let threshold: TimeInterval = 300
        let s = summary(lastActivity: now.addingTimeInterval(-threshold))
        // Exactly at threshold → not live (strict <)
        #expect(s.isLive(now: now, threshold: threshold) == false)
    }

    @Test("session older than threshold is not live")
    func oldIsNotLive() {
        let now = Date()
        let s = summary(lastActivity: now.addingTimeInterval(-600))
        #expect(s.isLive(now: now) == false)
    }

    @Test("custom threshold shortens the window")
    func customThreshold() {
        let now = Date()
        let s = summary(lastActivity: now.addingTimeInterval(-120)) // 2 min ago
        #expect(s.isLive(now: now, threshold: 60) == false)  // 1 min window
        #expect(s.isLive(now: now, threshold: 300) == true)  // 5 min window
    }

    @Test("future timestamp is still treated as live")
    func futureIsLive() {
        // Unlikely in practice (clock skew) — we should not hide such sessions.
        let now = Date()
        let s = summary(lastActivity: now.addingTimeInterval(60))
        #expect(s.isLive(now: now) == true)
    }

    // MARK: - isWorking (AI actively generating)

    @Test("alive session with inProgress tail is working")
    func aliveAndInProgressIsWorking() {
        let now = Date()
        let s = summary(lastActivity: now.addingTimeInterval(-10), inProgress: true)
        #expect(s.isWorking(now: now) == true)
    }

    @Test("alive but finished session is NOT working")
    func aliveButFinishedIsNotWorking() {
        let now = Date()
        let s = summary(lastActivity: now.addingTimeInterval(-10), inProgress: false)
        #expect(s.isWorking(now: now) == false)
        #expect(s.isLive(now: now) == true)  // still alive though
    }

    @Test("stale in-progress session is NOT working (crashed mid-turn)")
    func staleInProgressIsNotWorking() {
        // This covers the "Claude Code crashed mid-turn" case: the file's
        // last line is a user question, but it's been hours. We don't want
        // to pulse the dot forever.
        let now = Date()
        let s = summary(lastActivity: now.addingTimeInterval(-3600), inProgress: true)
        #expect(s.isWorking(now: now) == false)
        #expect(s.isLive(now: now) == false)
    }
}
