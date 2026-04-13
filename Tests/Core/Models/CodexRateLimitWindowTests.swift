import Foundation
import Testing

@testable import CodexPill

struct CodexRateLimitWindowTests {
    @Test
    func displayedUsedPercentFallsBackToZeroOnceWindowHasExpired() {
        let window = CodexRateLimitWindow(
            usedPercent: 100,
            resetsAt: Date(timeIntervalSince1970: 1_000),
            windowDurationMinutes: 300
        )

        #expect(window.displayedUsedPercent(at: Date(timeIntervalSince1970: 2_000)) == 0)
    }

    @Test
    func displayedUsedPercentKeepsLiveUsageBeforeResetTime() {
        let window = CodexRateLimitWindow(
            usedPercent: 34,
            resetsAt: Date(timeIntervalSince1970: 2_000),
            windowDurationMinutes: 300
        )

        #expect(window.displayedUsedPercent(at: Date(timeIntervalSince1970: 1_000)) == 34)
    }
}
