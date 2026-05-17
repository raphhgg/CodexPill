import Foundation
import Testing

@testable import CodexPill

struct CodexRateLimitWindowTests {
    @Test
    func effectiveCodexPlanTypeUsesRateLimitPlanOnlyForObservedPlusUpgrade() {
        #expect(effectiveCodexPlanType(accountPlanType: "plus", rateLimitPlanType: "prolite") == "prolite")
        #expect(effectiveCodexPlanType(accountPlanType: "plus", rateLimitPlanType: "pro") == "pro")
    }

    @Test
    func effectiveCodexPlanTypePreservesProLite() {
        #expect(normalizedCodexPlanType(" ProLite ") == "prolite")
    }

    @Test
    func normalizedCodexPlanTypeMapsAppServerBusinessAndEnterpriseAliases() {
        #expect(normalizedCodexPlanType("self_serve_business_usage_based") == "business")
        #expect(normalizedCodexPlanType("business") == "business")
        #expect(normalizedCodexPlanType("team") == "team")
        #expect(normalizedCodexPlanType("enterprise_cbp_usage_based") == "enterprise")
    }

    @Test
    func effectiveCodexPlanTypeDoesNotDowngradeHigherAccountPlan() {
        #expect(effectiveCodexPlanType(accountPlanType: "team", rateLimitPlanType: "prolite") == "team")
    }

    @Test
    func effectiveCodexPlanTypeTreatsUnknownAsMissing() {
        #expect(effectiveCodexPlanType(accountPlanType: "unknown", rateLimitPlanType: "business") == "business")
        #expect(effectiveCodexPlanType(accountPlanType: "plus", rateLimitPlanType: "unknown") == "plus")
        #expect(effectiveCodexPlanType(accountPlanType: "unknown", rateLimitPlanType: nil) == nil)
    }

    @Test
    func rateLimitSnapshotClassifiesWindowsByDurationInsteadOfPosition() {
        let weeklyOnly = CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "free",
            primary: CodexRateLimitWindow(
                usedPercent: 7,
                resetsAt: Date(timeIntervalSince1970: 2_000),
                windowDurationMinutes: 10_080
            ),
            secondary: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(weeklyOnly.sessionWindow == nil)
        #expect(weeklyOnly.weeklyWindow?.usedPercent == 7)
    }

    @Test
    func rateLimitSnapshotClassifiesNearWeeklyWindowAfterRecentReset() {
        let recentlyResetWeekly = CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "prolite",
            primary: CodexRateLimitWindow(
                usedPercent: 7,
                resetsAt: Date(timeIntervalSince1970: 2_000),
                windowDurationMinutes: 299
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 1,
                resetsAt: Date(timeIntervalSince1970: 604_740),
                windowDurationMinutes: 10_079
            ),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(recentlyResetWeekly.sessionWindow?.usedPercent == 7)
        #expect(recentlyResetWeekly.weeklyWindow?.usedPercent == 1)
    }

    @Test
    func rateLimitSnapshotKeepsLegacyPositionalFallbackWhenDurationsAreMissing() {
        let legacy = CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "plus",
            primary: CodexRateLimitWindow(usedPercent: 12, resetsAt: nil, windowDurationMinutes: nil),
            secondary: CodexRateLimitWindow(usedPercent: 34, resetsAt: nil, windowDurationMinutes: nil),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(legacy.sessionWindow?.usedPercent == 12)
        #expect(legacy.weeklyWindow?.usedPercent == 34)
    }

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
