import Foundation
import Testing

@testable import CodexPill

struct CodexAccountTests {
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
