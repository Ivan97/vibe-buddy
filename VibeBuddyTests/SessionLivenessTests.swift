import Foundation
import Testing
@testable import VibeBuddy

@Suite("SessionSummary.isLive")
struct SessionLivenessTests {

    private func summary(lastActivity: Date) -> SessionSummary {
        SessionSummary(
            id: "session-id",
            path: URL(fileURLWithPath: "/tmp/s.jsonl"),
            projectPath: "/tmp",
            projectSlug: "-tmp",
            firstPrompt: nil,
            messageCount: 1,
            lastActivity: lastActivity,
            claudeVersion: nil,
            gitBranch: nil
        )
    }

    @Test("session modified seconds ago is live")
    func freshIsLive() {
        let now = Date()
        let s = summary(lastActivity: now.addingTimeInterval(-10))
        #expect(s.isLive(now: now) == true)
    }

    @Test("session at the threshold boundary is not live")
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
}
