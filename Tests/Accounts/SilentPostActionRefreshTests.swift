import Foundation
import Testing

@testable import CodexPill

struct SilentPostActionRefreshTests {
    @Test
    func skipsRefreshWhenNoActiveAccountExists() async {
        let repository = SilentRefreshCatalogProbe()
        let useCase = makeUseCase(
            accountStatusClient: SilentRefreshStatusErrorCase(error: SilentRefreshTestFailure.refreshFailed),
            repository: repository
        )
        let refresh = SilentPostActionRefresh(refreshActiveAccountUseCase: useCase)

        let result = await refresh.run(
            after: Duration.zero,
            activeAccountID: nil,
            accounts: [makeAccount(name: "Business 4", fingerprint: "live")]
        )

        #expect(result == nil)
        #expect(repository.savedAccounts == nil)
    }

    @Test
    func returnsNilWhenRefreshFails() async {
        let repository = SilentRefreshCatalogProbe()
        let useCase = makeUseCase(
            accountStatusClient: SilentRefreshStatusErrorCase(error: SilentRefreshTestFailure.refreshFailed),
            repository: repository
        )
        let refresh = SilentPostActionRefresh(refreshActiveAccountUseCase: useCase)
        let account = makeAccount(name: "Business 4", fingerprint: "live")

        let result = await refresh.run(
            after: Duration.zero,
            activeAccountID: account.id,
            accounts: [account]
        )

        #expect(result == nil)
        #expect(repository.savedAccounts == nil)
    }

    @Test
    func returnsUpdatedAccountsWhenRefreshSucceeds() async throws {
        let repository = SilentRefreshCatalogProbe()
        let account = makeAccount(name: "Business 4", fingerprint: "live")
        let refreshedRateLimits = CodexRateLimitSnapshot(
            limitID: nil,
            limitName: nil,
            planType: "pro",
            primary: .init(usedPercent: 42, resetsAt: nil, windowDurationMinutes: 300),
            secondary: .init(usedPercent: 68, resetsAt: nil, windowDurationMinutes: 10_080),
            fetchedAt: .now
        )
        let useCase = makeUseCase(
            accountStatusClient: SilentRefreshStatusFixture(
                status: CodexAccountStatus(
                    email: "business@example.com",
                    planType: "pro",
                    rateLimits: refreshedRateLimits
                )
            ),
            repository: repository
        )
        let refresh = SilentPostActionRefresh(refreshActiveAccountUseCase: useCase)

        let result = try #require(
            await refresh.run(
                after: Duration.zero,
                activeAccountID: account.id,
                accounts: [account]
            )
        )

        #expect(result.refreshedAccountID == account.id)
        #expect(result.accounts.count == 1)
        #expect(result.accounts[0].email == "business@example.com")
        #expect(result.accounts[0].planType == "pro")
        #expect(result.accounts[0].rateLimits == refreshedRateLimits)
        #expect(repository.savedAccounts == result.accounts)
    }

    private func makeUseCase(
        accountStatusClient: CodexAccountStatusClient,
        repository: SilentRefreshCatalogProbe
    ) -> RefreshActiveAccountUseCase {
        RefreshActiveAccountUseCase(
            accountStatusClient: accountStatusClient,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: SilentRefreshIdentityFixture(fingerprint: "live"),
                storedAccountReconciler: SilentRefreshStoredIdentityAdapter()
            ),
            repository: repository
        )
    }

    private func makeAccount(name: String, fingerprint: String) -> CodexAccount {
        let id = UUID()
        return CodexAccount(
            id: id,
            name: name,
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business@example.com",
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: fingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "business@example.com")
            )
        )
    }
}

private enum SilentRefreshTestFailure: LocalizedError {
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .refreshFailed:
            "Silent refresh failed."
        }
    }
}

private final class SilentRefreshStatusErrorCase: CodexAccountStatusClient {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        throw error
    }
}

private final class SilentRefreshStatusFixture: CodexAccountStatusClient {
    let status: CodexAccountStatus

    init(status: CodexAccountStatus) {
        self.status = status
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        status
    }
}

private final class SilentRefreshCatalogProbe: AccountCatalogStore {
    private(set) var savedAccounts: [CodexAccount]?

    func bootstrapStorage() throws {}
    func loadAccounts() throws -> [CodexAccount] { [] }
    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}

private struct SilentRefreshIdentityFixture: LiveCodexAccountIdentitySource {
    let fingerprint: String?

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: fingerprint)
    }
}

private struct SilentRefreshStoredIdentityAdapter: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
