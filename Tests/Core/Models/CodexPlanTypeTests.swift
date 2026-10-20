import Foundation
import Testing

@testable import rusage

struct UsageWindowTests {
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
}
