import Foundation
import Testing

@testable import CodexPill

struct CodexAccountTests {
    @Test
    func effectivePlanTypeUsesFreshRateLimitPlanWhenAccountPlanIsStale() {
        let account = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            email: "personal@example.com",
            planType: "plus",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "prolite",
                primary: nil,
                secondary: nil,
                fetchedAt: Date(timeIntervalSince1970: 2_000)
            ),
            identity: .empty
        )

        #expect(account.effectivePlanType == "pro")
    }

    @Test
    func applyRemoteMetadataPersistsEffectivePlanFromRateLimits() {
        var account = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            email: "personal@example.com",
            planType: "plus",
            rateLimits: nil,
            identity: .empty
        )

        account.applyRemoteMetadata(
            email: "personal@example.com",
            planType: "plus",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "prolite",
                primary: nil,
                secondary: nil,
                fetchedAt: Date(timeIntervalSince1970: 2_000)
            )
        )

        #expect(account.planType == "pro")
        #expect(account.effectivePlanType == "pro")
    }

    @Test
    func lastRemoteRefreshAtPrefersNewerUpdatedAtWhenRateLimitsAreStale() {
        let account = CodexAccount(
            id: UUID(),
            name: "Work",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            email: "work@example.com",
            planType: "plus",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "plus",
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
            name: "Work",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            email: "work@example.com",
            planType: "plus",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "plus",
                primary: nil,
                secondary: nil,
                fetchedAt: Date(timeIntervalSince1970: 2_000)
            ),
            identity: .empty
        )

        #expect(account.lastRemoteRefreshAt == Date(timeIntervalSince1970: 2_000))
    }
}
