import Foundation
import Testing

@testable import CodexPill

struct CodexRateLimitWindowTests {
    @Test
    func effectiveCodexPlanTypeUsesRateLimitPlanOnlyForObservedPlusToProUpgrade() {
        #expect(effectiveCodexPlanType(accountPlanType: "plus", rateLimitPlanType: "prolite") == "pro")
    }

    @Test
    func effectiveCodexPlanTypeNormalizesProliteToPro() {
        #expect(normalizedCodexPlanType(" ProLite ") == "pro")
    }

    @Test
    func normalizedCodexPlanTypeMapsAppServerBusinessAndEnterpriseAliases() {
        #expect(normalizedCodexPlanType("self_serve_business_usage_based") == "business")
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
