import AppKit
import Foundation
import Testing

@testable import CodexPill

struct MenuBarAccountPresentationTests {
    @Test
    func resetStatusTextKeepsRelativeTextWhenWindowIsFull() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = CodexRateLimitWindow(
            usedPercent: 100,
            resetsAt: now.addingTimeInterval((4 * 60 + 7) * 60),
            windowDurationMinutes: 300
        )

        #expect(resetStatusText(for: window, now: now) == "Resets in 4h07")
    }

    @Test
    func resetStatusTextKeepsRelativeTextWhenWindowIsNotFull() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = CodexRateLimitWindow(
            usedPercent: 42,
            resetsAt: now.addingTimeInterval(4 * 60 * 60),
            windowDurationMinutes: 300
        )

        #expect(resetStatusText(for: window, now: now) == "Resets in 4h")
    }

    @Test
    func resetStatusTextUsesHourMinuteCountdownForSubHourWindows() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = CodexRateLimitWindow(
            usedPercent: 100,
            resetsAt: now.addingTimeInterval(28 * 60),
            windowDurationMinutes: 300
        )

        #expect(resetStatusText(for: window, now: now) == "Resets in 28min")
    }

    @Test
    func resetStatusTextUsesDaysForMultiDayWindows() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = CodexRateLimitWindow(
            usedPercent: 94,
            resetsAt: now.addingTimeInterval((4 * 24 + 8) * 60 * 60),
            windowDurationMinutes: 10_080
        )

        #expect(resetStatusText(for: window, now: now) == "Resets in 4d")
    }

    @Test
    func statusItemTooltipShowsIdentityAndResetCountdownsForFullLimits() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval((3 * 60 + 12) * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval((27 * 60 + 5) * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            )
        )

        let tooltip = try! #require(statusItemTooltipText(for: account, now: now))
        #expect(tooltip.contains("Business 2"))
        #expect(tooltip.contains("raphaelgrau@gmail.com"))
        #expect(tooltip.contains("Team"))
        #expect(tooltip.contains("Session resets"))
        #expect(tooltip.contains("Weekly resets"))
        #expect(tooltip.contains("3h12"))
        #expect(!tooltip.contains("27h05"))
    }

    @Test
    func statusItemTooltipKeepsExactHourPrecisionSeparateFromCardCopy() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval(4 * 60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: nil,
                fetchedAt: now
            )
        )

        let tooltip = try! #require(statusItemTooltipText(for: account, now: now))

        #expect(resetStatusText(for: try! #require(account.rateLimits?.primary), now: now) == "Resets in 4h")
        #expect(tooltip.contains("Session resets in 4h00"))
        #expect(!tooltip.contains("Session resets in 4h\n"))
    }

    @Test
    func statusItemTooltipOmitsNoiseWhenNoAccountIsActive() {
        #expect(statusItemTooltipText(for: nil) == nil)
    }

    @Test
    func statusItemHoverTitleUsesCountdownsOnlyForFullWindows() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "personal.json",
            createdAt: now,
            updatedAt: now,
            email: "raphaelgrau@gmail.com",
            planType: "plus",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "plus",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval((2 * 60 + 5) * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 68,
                    resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            )
        )

        #expect(statusItemHoverTitle(for: account, now: now) == "S 2h05 W 68%")
    }

    @Test
    func statusItemHoverTitleUsesPercentsWhenWindowsAreNotFull() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Business 1",
            snapshotFileName: "business-1.json",
            createdAt: now,
            updatedAt: now,
            email: "admin@raphh.me",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 42,
                    resetsAt: now.addingTimeInterval(2 * 60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 68,
                    resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            )
        )

        #expect(statusItemHoverTitle(for: account, now: now) == "S 42% W 68%")
    }

    @Test
    func compactAccountUsageSummaryUsesOneLineFormat() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval((1 * 60 + 42) * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 94,
                    resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            )
        )

        #expect(compactAccountUsageSummary(for: account, now: now) == "S 100% (1h42) • W 94% (4d)")
    }

    @Test
    func inactiveAccountTitleUsesTabAlignedColumns() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 10,
                    resetsAt: now.addingTimeInterval((1 * 60 + 23) * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 78,
                    resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            )
        )

        let title = inactiveAccountTitle(for: account, placement: .local, menuContentWidth: 423, now: now)
        let paragraphStyle = title.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

        #expect(title.string == "Business 2  S 10% (1h23)  W 78% (3d)\tLocal")
        #expect(paragraphStyle?.tabStops.first?.location == 395)
    }
}
