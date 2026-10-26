import Foundation
import Testing

@testable import RUsage

struct CodexAccountTests {
    @Test
    func effectivePlanTypeUsesFreshRateLimitPlanWhenAccountPlanIsStale() {
        let account = CodexAccount(
            id: UUID(),
            email: "personal@example.com",
            planType: "plus",
            usage: UsageSnapshot.codex(
                planName: "prolite",
                primary: nil,
                secondary: nil,
                fetchedAt: Date(timeIntervalSince1970: 2_000)
            ),
            identity: .empty
        )

        #expect(account.effectivePlanType == "prolite")
    }

    @Test
    func applyRemoteMetadataPersistsEffectivePlanFromRateLimits() {
        var account = CodexAccount(
            id: UUID(),
            email: "personal@example.com",
            planType: "plus",
            usage: nil,
            identity: .empty
        )

        account.applyRemoteMetadata(
            email: "personal@example.com",
            planType: "plus",
            usage: UsageSnapshot.codex(
                planName: "prolite",
                primary: nil,
                secondary: nil,
                fetchedAt: Date(timeIntervalSince1970: 2_000)
            )
        )

        #expect(account.planType == "prolite")
        #expect(account.effectivePlanType == "prolite")
    }
}
