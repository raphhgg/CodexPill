import Foundation
import Testing

@testable import CodexPill

struct CodexAccountTests {
    @Test
    func effectivePlanTypeUsesFreshRateLimitPlanWhenAccountPlanIsStale() {
        let account = CodexAccount(
            id: UUID(),
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: 1_000),
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
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: 1_000),
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

    @Test
    func lastRemoteRefreshAtPrefersNewerUpdatedAtWhenRateLimitsAreStale() {
        let account = CodexAccount(
            id: UUID(),
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            email: "work@example.com",
            planType: "plus",
            usage: UsageSnapshot.codex(
                planName: "plus",
                primary: nil,
                secondary: nil,
                fetchedAt: Date(timeIntervalSince1970: 1_000)
            ),
            identity: .empty
        )

        #expect(account.lastRemoteRefreshAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test
    func lastRemoteRefreshAtUsesRateLimitFetchTimeWhenItIsNewest() {
        let account = CodexAccount(
            id: UUID(),
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            email: "work@example.com",
            planType: "plus",
            usage: UsageSnapshot.codex(
                planName: "plus",
                primary: nil,
                secondary: nil,
                fetchedAt: Date(timeIntervalSince1970: 2_000)
            ),
            identity: .empty
        )

        #expect(account.lastRemoteRefreshAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test
    func savedAccountKeepsResetCredits() throws {
        var usage = makeUsage(fetchedAt: Date(timeIntervalSince1970: 1_776_200_000))
        usage.resetCredits = UsageResetCredits(
            availableCount: 2,
            credits: [UsageResetCredit(expiresAt: Date(timeIntervalSince1970: 1_778_000_000)), UsageResetCredit(expiresAt: nil)]
        )
        let account = makeAccount(name: "Personal", usage: usage)

        let decoded = try JSONDecoder().decode(CodexAccount.self, from: JSONEncoder().encode(account))

        #expect(decoded.usage?.resetCredits == usage.resetCredits)
    }
}
