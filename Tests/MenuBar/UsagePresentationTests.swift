import AppKit
import Foundation
import Testing

@testable import CodexPill

struct UsagePresentationTests {
    @Test
    func codexPlanDisplayNameDisplaysProliteAsProX5() {
        #expect(displayNameForCodexPlanType("prolite") == "Pro x5")
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
    func codexPlanDisplayNameMapsKnownAppServerPlanTypes(planType: String, displayName: String) {
        #expect(displayNameForCodexPlanType(planType) == displayName)
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
    func statusItemTitleUsesCountdownsOnlyForFullWindows() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let windows = [
            UsageWindow(kind: .session, usedPercent: 100, resetsAt: now.addingTimeInterval(125 * 60), durationMinutes: 300),
            UsageWindow(kind: .weekly, usedPercent: 68, resetsAt: now.addingTimeInterval(3 * 86_400), durationMinutes: 10_080),
        ]

        #expect(statusItemTitle(for: windows, now: now) == "S 2h05 W 68%")
        #expect(statusItemTitle(for: windows, percentMode: .left, now: now) == "S 2h05 W 32%")
    }

    @Test
    func statusItemTitleNamesOnlyTheWindowsTheToolReported() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let weekly = UsageWindow(kind: .weekly, usedPercent: 17, resetsAt: now.addingTimeInterval(3 * 86_400), durationMinutes: 10_080)
        let billingCycle = UsageWindow(kind: .billingCycle, usedPercent: 82, resetsAt: now.addingTimeInterval(20 * 86_400), durationMinutes: nil)

        #expect(statusItemTitle(for: [weekly], now: now) == "W 17%")
        #expect(statusItemTitle(for: [billingCycle], now: now) == "82%")
        #expect(statusItemTitle(for: [], now: now) == "--")
    }

    @Test
    func aSingleWindowFillsTheLowerMeterAndLeavesTheUpperOneMissing() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let session = UsageWindow(kind: .session, usedPercent: 42, resetsAt: now.addingTimeInterval(3_600), durationMinutes: 300)
        let weekly = UsageWindow(kind: .weekly, usedPercent: 100, resetsAt: now.addingTimeInterval(86_400), durationMinutes: 10_080)

        #expect(statusItemBarPercents(for: [session, weekly], mode: .used, now: now) == (42, 100))
        #expect(statusItemBarPercents(for: [session, weekly], mode: .left, now: now) == (58, 0))
        #expect(statusItemBarPercents(for: [weekly], mode: .used, now: now) == (nil, 100))
        #expect(statusItemBarPercents(for: [], mode: .used, now: now) == (nil, nil))
    }

    @Test
    func percentLeftModeInvertsMeterTextAndPaceMarkers() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let session = UsageWindow(kind: .session, usedPercent: 42, resetsAt: now.addingTimeInterval(4 * 60 * 60), durationMinutes: 300)

        #expect(usageMeterPercentText(for: session, mode: .used, now: now) == "42% used")
        #expect(usageMeterPercentText(for: session, mode: .left, now: now) == "58% left")
        #expect(expectedPaceMarkerPercent(for: session, showsPacingMarkers: true, percentMode: .used, now: now) == 20)
        #expect(expectedPaceMarkerPercent(for: session, showsPacingMarkers: true, percentMode: .left, now: now) == 80)
    }

    @Test
    func statusItemTooltipNamesTheFirstToolItsAccountAndFullLimits() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = makeAccount(
            name: "Business",
            planType: "team",
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 100, resetsAt: now.addingTimeInterval(4 * 60 * 60), durationMinutes: 300),
                secondary: (usedPercent: 40, resetsAt: now.addingTimeInterval(27 * 60 * 60), durationMinutes: 10_080),
                fetchedAt: now
            )
        )
        let state = MenuBarMenuState(activeAccount: account, inactiveAccounts: [], now: now)
        let masked = MenuBarMenuState(activeAccount: account, inactiveAccounts: [], masksEmails: true, now: now)

        #expect(statusItemTooltipText(for: state.statusItemSource, now: now) == "Codex · Team\nbusiness@example.com\nSession resets in 4h00")
        #expect(statusItemTooltipText(for: masked.statusItemSource, now: now) == "Codex · Team\nbu•••s@example.com\nSession resets in 4h00")
        #expect(statusItemTooltipText(for: .nothingConnected, now: now) == "CodexPill")
    }
}
