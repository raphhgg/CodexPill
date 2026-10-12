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
        let window = UsageWindow(
            kind: .session,
            usedPercent: 100,
            resetsAt: now.addingTimeInterval((4 * 60 + 7) * 60),
            durationMinutes: 300
        )

        #expect(resetStatusText(for: window, now: now) == "Resets in 4h07")
    }

    @Test
    func resetStatusTextKeepsRelativeTextWhenWindowIsNotFull() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = UsageWindow(
            kind: .session,
            usedPercent: 42,
            resetsAt: now.addingTimeInterval(4 * 60 * 60),
            durationMinutes: 300
        )

        #expect(resetStatusText(for: window, now: now) == "Resets in 4h")
    }

    @Test
    func resetStatusTextUsesHourMinuteCountdownForSubHourWindows() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = UsageWindow(
            kind: .session,
            usedPercent: 100,
            resetsAt: now.addingTimeInterval(28 * 60),
            durationMinutes: 300
        )

        #expect(resetStatusText(for: window, now: now) == "Resets in 28min")
    }

    @Test
    func resetStatusTextUsesDaysForMultiDayWindows() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = UsageWindow(
            kind: .session,
            usedPercent: 94,
            resetsAt: now.addingTimeInterval((4 * 24 + 8) * 60 * 60),
            durationMinutes: 10_080
        )

        #expect(resetStatusText(for: window, now: now) == "Resets in 4d")
    }

    @Test
    func expectedRateLimitUsagePercentUsesElapsedWindowShare() throws {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = UsageWindow(
            kind: .session,
            usedPercent: 70,
            resetsAt: now.addingTimeInterval(150 * 60),
            durationMinutes: 300
        )

        #expect(expectedRateLimitUsagePercent(for: window, now: now) == 50)
    }

    @Test
    func expectedRateLimitUsagePercentRequiresFutureResetAndDuration() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let missingReset = UsageWindow(
            kind: .session,
            usedPercent: 40,
            resetsAt: nil,
            durationMinutes: 300
        )
        let missingDuration = UsageWindow(
            kind: .session,
            usedPercent: 40,
            resetsAt: now.addingTimeInterval(150 * 60),
            durationMinutes: nil
        )
        let expired = UsageWindow(
            kind: .session,
            usedPercent: 40,
            resetsAt: now.addingTimeInterval(-60),
            durationMinutes: 300
        )

        #expect(expectedRateLimitUsagePercent(for: missingReset, now: now) == nil)
        #expect(expectedRateLimitUsagePercent(for: missingDuration, now: now) == nil)
        #expect(expectedRateLimitUsagePercent(for: expired, now: now) == nil)
    }

    @Test
    func expectedPaceMarkerPercentRequiresEnabledPreferenceAndWindowData() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let window = UsageWindow(
            kind: .session,
            usedPercent: 70,
            resetsAt: now.addingTimeInterval(150 * 60),
            durationMinutes: 300
        )

        #expect(expectedPaceMarkerPercent(for: window, showsPacingMarkers: true, now: now) == 50)
        #expect(expectedPaceMarkerPercent(for: window, showsPacingMarkers: false, now: now) == nil)
        #expect(expectedPaceMarkerPercent(for: nil, showsPacingMarkers: true, now: now) == nil)
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
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 100, resetsAt: now.addingTimeInterval((3 * 60 + 12) * 60), durationMinutes: 300),
                secondary: (usedPercent: 100, resetsAt: now.addingTimeInterval((27 * 60 + 5) * 60), durationMinutes: 10_080),
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
            usage: UsageSnapshot.codex(
                planName: "free",
                primary: (usedPercent: 0, resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60), durationMinutes: 10_080),
                secondary: nil,
                fetchedAt: now
            )
        )

        #expect(compactMenuRowUsageSummary(for: account, now: now) == "W 0%")
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
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 100, resetsAt: now.addingTimeInterval(4 * 60 * 60), durationMinutes: 300),
                secondary: nil,
                fetchedAt: now
            )
        )

        let tooltip = try! #require(statusItemTooltipText(for: account, now: now))

        #expect(resetStatusText(for: try! #require(account.usage?.window(.session)), now: now) == "Resets in 4h")
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
            usage: UsageSnapshot.codex(
                planName: "plus",
                primary: (usedPercent: 100, resetsAt: now.addingTimeInterval((2 * 60 + 5) * 60), durationMinutes: 300),
                secondary: (usedPercent: 68, resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60), durationMinutes: 10_080),
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
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 42, resetsAt: now.addingTimeInterval(2 * 60 * 60), durationMinutes: 300),
                secondary: (usedPercent: 68, resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60), durationMinutes: 10_080),
                fetchedAt: now
            )
        )

        #expect(statusItemHoverTitle(for: account, now: now) == "S 42% W 68%")
    }

    @Test
    func percentLeftModeInvertsTextBarsAndPaceMarkers() throws {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = makeAccount(
            name: "Business 1",
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 42, resetsAt: now.addingTimeInterval(4 * 60 * 60), durationMinutes: 300),
                secondary: (usedPercent: 100, resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60), durationMinutes: 10_080),
                fetchedAt: now
            )
        )
        let session = try #require(account.usage?.window(.session))

        #expect(usageMeterPercentText(for: session, mode: .used, now: now) == "42% used")
        #expect(usageMeterPercentText(for: session, mode: .left, now: now) == "58% left")
        #expect(statusItemHoverTitle(for: account, percentMode: .left, now: now) == "S 58% W 2d")
        #expect(compactMenuRowUsageSummary(for: account, percentMode: .left, now: now) == "S 58% (4h00)  W 0% (2d)")
        #expect(expectedPaceMarkerPercent(for: session, showsPacingMarkers: true, percentMode: .used, now: now) == 20)
        #expect(expectedPaceMarkerPercent(for: session, showsPacingMarkers: true, percentMode: .left, now: now) == 80)

        let usedBars = statusItemBarPercents(for: account, mode: .used, now: now)
        let leftBars = statusItemBarPercents(for: account, mode: .left, now: now)
        #expect(usedBars.session == 42)
        #expect(usedBars.weekly == 100)
        #expect(leftBars.session == 58)
        #expect(leftBars.weekly == 0)
        #expect(statusItemBarPercents(for: nil, mode: .left, now: now).session == nil)
    }

    @Test
    func compactMenuRowUsageSummaryShowsResetCountdownsForUsedLimits() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: "user@example.com",
            planType: "team",
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 100, resetsAt: now.addingTimeInterval((1 * 60 + 42) * 60), durationMinutes: 300),
                secondary: (usedPercent: 94, resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60), durationMinutes: 10_080),
                fetchedAt: now
            )
        )

        #expect(compactMenuRowUsageSummary(for: account, now: now) == "S 100% (1h42)  W 94% (4d)")
    }

    @Test
    func compactMenuRowUsageSummaryIsEmptyWhenUsageIsMissing() {
        #expect(compactMenuRowUsageSummary(for: makeAccount(name: "Research", usage: nil)) == "")
    }

    @Test
    func activeAccountMetersSkipAWindowCodexDidNotReport() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let weeklyOnly = UsageSnapshot.codex(
            planName: "free",
            primary: (usedPercent: 30, resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60), durationMinutes: 10_080),
            secondary: nil,
            fetchedAt: now
        )

        let meters = UsageMeter.codexMeters(for: weeklyOnly, sessionTint: .green, weeklyTint: .blue)

        #expect(meters.map(\.title) == ["Weekly"])
        #expect(meters.map(\.window.usedPercent) == [30])
        #expect(UsageMeter.codexMeters(for: nil, sessionTint: .green, weeklyTint: .blue).isEmpty)
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
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 0, resetsAt: now.addingTimeInterval((4 * 60 + 59) * 60), durationMinutes: 300),
                secondary: (usedPercent: 91, resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60), durationMinutes: 10_080),
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
    func inactiveAccountTitleShowsNameThenUsage() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: "user@example.com",
            planType: "team",
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 10, resetsAt: now.addingTimeInterval((1 * 60 + 23) * 60), durationMinutes: 300),
                secondary: (usedPercent: 78, resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60), durationMinutes: 10_080),
                fetchedAt: now
            )
        )

        let title = inactiveAccountTitle(for: account, now: now)

        #expect(title.string == "Business 2  S 10% (1h23)  W 78% (3d)")
    }
}
