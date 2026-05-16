import AppKit
import Foundation
import Testing

@testable import CodexPill

struct MenuBarAccountPresentationTests {
    @Test
    func menuPlanDisplayNameDisplaysProliteAsProX5() {
        #expect(menuPlanDisplayName("prolite") == "Pro x5")
    }

    @Test(arguments: [
        ("free", "Free"),
        ("go", "Go"),
        ("plus", "Plus"),
        ("pro", "Pro x20"),
        ("prolite", "Pro x5"),
        ("team", "Team"),
        ("self_serve_business_usage_based", "Business"),
        ("business", "Business"),
        ("enterprise_cbp_usage_based", "Enterprise"),
        ("enterprise", "Enterprise"),
        ("edu", "Edu"),
        ("unknown", "Unknown")
    ])
    func menuPlanDisplayNameMapsKnownAppServerPlanTypes(planType: String, displayName: String) {
        #expect(menuPlanDisplayName(planType) == displayName)
    }

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
    func expectedRateLimitUsagePercentUsesElapsedWindowShare() throws {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = CodexRateLimitWindow(
            usedPercent: 70,
            resetsAt: now.addingTimeInterval(150 * 60),
            windowDurationMinutes: 300
        )

        #expect(expectedRateLimitUsagePercent(for: window, now: now) == 50)
    }

    @Test
    func expectedRateLimitUsagePercentRequiresFutureResetAndDuration() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let missingReset = CodexRateLimitWindow(
            usedPercent: 40,
            resetsAt: nil,
            windowDurationMinutes: 300
        )
        let missingDuration = CodexRateLimitWindow(
            usedPercent: 40,
            resetsAt: now.addingTimeInterval(150 * 60),
            windowDurationMinutes: nil
        )
        let expired = CodexRateLimitWindow(
            usedPercent: 40,
            resetsAt: now.addingTimeInterval(-60),
            windowDurationMinutes: 300
        )

        #expect(expectedRateLimitUsagePercent(for: missingReset, now: now) == nil)
        #expect(expectedRateLimitUsagePercent(for: missingDuration, now: now) == nil)
        #expect(expectedRateLimitUsagePercent(for: expired, now: now) == nil)
    }

    @Test
    func expectedPaceMarkerPercentRequiresEnabledPreferenceAndWindowData() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = CodexRateLimitWindow(
            usedPercent: 70,
            resetsAt: now.addingTimeInterval(150 * 60),
            windowDurationMinutes: 300
        )

        #expect(expectedPaceMarkerPercent(for: window, showsPacingMarkers: true, now: now) == 50)
        #expect(expectedPaceMarkerPercent(for: window, showsPacingMarkers: false, now: now) == nil)
        #expect(expectedPaceMarkerPercent(for: nil, showsPacingMarkers: true, now: now) == nil)
    }

    @Test
    func usageBarPercentTextCanDisplayUsedOrLeft() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = CodexRateLimitWindow(
            usedPercent: 42,
            resetsAt: now.addingTimeInterval(2 * 60 * 60),
            windowDurationMinutes: 300
        )

        #expect(usageBarPercentText(for: window, mode: .used, now: now) == "42% used")
        #expect(usageBarPercentText(for: window, mode: .left, now: now) == "58% left")
        #expect(usageBarPercent(forUsedPercent: 42, mode: .left) == 58)
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
            email: "user@example.com",
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
        #expect(tooltip.contains("user@example.com"))
        #expect(tooltip.contains("Team"))
        #expect(tooltip.contains("Session resets"))
        #expect(tooltip.contains("Weekly resets"))
        #expect(tooltip.contains("3h12"))
        #expect(!tooltip.contains("27h05"))
    }

    @Test
    func compactUsageSummaryMapsWeeklyDurationPrimaryWindowToWeeklyLabel() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Backup",
            snapshotFileName: "backup.json",
            createdAt: now,
            updatedAt: now,
            email: "backup@example.com",
            planType: "free",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "free",
                primary: CodexRateLimitWindow(
                    usedPercent: 0,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                secondary: nil,
                fetchedAt: now
            )
        )

        #expect(compactMenuRowUsageSummary(for: account, now: now) == "S --  W 0%")
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
            email: "user@example.com",
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
            email: "user@example.com",
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
            email: "admin@example.com",
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
    func statusItemHoverTitleCanDisplayPercentLeft() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: nil,
            planType: "pro",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "pro",
                primary: CodexRateLimitWindow(
                    usedPercent: 42,
                    resetsAt: nil,
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 68,
                    resetsAt: nil,
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ),
            identity: .empty
        )

        #expect(
            statusItemHoverTitle(for: account, usageBarDisplayMode: .left, now: now) == "S 58% W 32%"
        )
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
            email: "user@example.com",
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
    func compactMenuRowUsageSummaryOmitsResetCountdownsForUnusedLimits() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: "user@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 0,
                    resetsAt: now.addingTimeInterval((4 * 60 + 59) * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 91,
                    resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            )
        )

        #expect(compactMenuRowUsageSummary(for: account, now: now) == "S 0%  W 91% (4d)")
    }

    @Test
    func compactElapsedTimeUsesShortUnits() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)

        #expect(compactElapsedTime(since: now.addingTimeInterval(-30), now: now) == "30sec")
        #expect(compactElapsedTime(since: now.addingTimeInterval(-60), now: now) == "1min")
        #expect(compactElapsedTime(since: now.addingTimeInterval(-3_600), now: now) == "1h")
        #expect(compactElapsedTime(since: now.addingTimeInterval(-86_400), now: now) == "1d")
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
            email: "user@example.com",
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
