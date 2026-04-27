import Foundation
import Testing

@testable import CodexPill

struct RefreshActiveAccountUseCaseTests {
    @Test
    func runRefreshesMatchedAccountAndPersistsUpdatedState() async throws {
        let refreshedRateLimits = CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "prolite",
            primary: CodexRateLimitWindow(
                usedPercent: 40,
                resetsAt: .now.addingTimeInterval(5400),
                windowDurationMinutes: 300
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 6,
                resetsAt: .now.addingTimeInterval(86_400),
                windowDurationMinutes: 10_080
            ),
            fetchedAt: .now
        )
        let existingRateLimits = CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "plus",
            primary: CodexRateLimitWindow(
                usedPercent: 25,
                resetsAt: .now.addingTimeInterval(3600),
                windowDurationMinutes: 300
            ),
            secondary: nil,
            fetchedAt: .distantPast
        )
        let account = makeAccount(name: "Work", fingerprint: "live", email: "old@example.com")
        var accountWithRateLimits = account
        accountWithRateLimits.rateLimits = existingRateLimits
        let repository = PersistingRepositorySpy()
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: RefreshAppServerSpy(
                status: CodexAccountStatus(
                    email: "new@example.com",
                    planType: "plus",
                    rateLimits: refreshedRateLimits
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentityReader: CurrentFingerprintStub(fingerprint: "live"),
                storedAccountReconciler: ReconcilePassthrough()
            ),
            repository: repository
        )

        let result = try await useCase.run(accounts: [accountWithRateLimits])

        #expect(result.refreshedAccountID == account.id)
        #expect(result.accounts.first?.email == "new@example.com")
        #expect(result.accounts.first?.planType == "pro")
        #expect(result.accounts.first?.rateLimits == refreshedRateLimits)
        #expect(repository.savedAccounts == result.accounts)
        #expect(result.accounts.first?.updatedAt != .distantPast)
    }

    @Test
    func runDoesNotMarkPreservedRateLimitsFreshWhenAppServerReturnsNoRateLimits() async throws {
        let existingUpdatedAt = Date(timeIntervalSince1970: 1_744_195_200)
        let existingRateLimits = CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "plus",
            primary: CodexRateLimitWindow(
                usedPercent: 25,
                resetsAt: .now.addingTimeInterval(3600),
                windowDurationMinutes: 300
            ),
            secondary: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_744_195_100)
        )
        var account = makeAccount(name: "Work", fingerprint: "live", email: "old@example.com")
        account.updatedAt = existingUpdatedAt
        account.rateLimits = existingRateLimits
        let repository = PersistingRepositorySpy()
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: RefreshAppServerSpy(
                status: CodexAccountStatus(
                    email: "new@example.com",
                    planType: "pro",
                    rateLimits: nil
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentityReader: CurrentFingerprintStub(fingerprint: "live"),
                storedAccountReconciler: ReconcilePassthrough()
            ),
            repository: repository
        )

        let result = try await useCase.run(accounts: [account])

        #expect(result.accounts.first?.email == "new@example.com")
        #expect(result.accounts.first?.planType == "pro")
        #expect(result.accounts.first?.rateLimits == existingRateLimits)
        #expect(result.accounts.first?.updatedAt == existingUpdatedAt)
        #expect(repository.savedAccounts == result.accounts)
    }

    @Test
    func runFailsWhenLiveAccountDoesNotMatchAnySavedAccount() async {
        let account = makeAccount(name: "Work", fingerprint: "saved", email: "saved@example.com")
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: RefreshAppServerSpy(
                status: CodexAccountStatus(
                    email: "other@example.com",
                    planType: nil,
                    rateLimits: nil
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentityReader: CurrentFingerprintStub(fingerprint: "live"),
                storedAccountReconciler: ReconcilePassthrough()
            ),
            repository: PersistingRepositorySpy()
        )

        await #expect(throws: RefreshActiveAccountUseCaseError.targetResolutionFailed(.noMatch)) {
            try await useCase.run(accounts: [account])
        }
    }

    private func makeAccount(name: String, fingerprint: String, email: String?) -> CodexAccount {
        let id = UUID()
        return CodexAccount(
            id: id,
            name: name,
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: email,
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: fingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}

private final class RefreshAppServerSpy: CodexAccountStatusClient {
    let status: CodexAccountStatus

    init(status: CodexAccountStatus) {
        self.status = status
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        status
    }
}

private final class PersistingRepositorySpy: AccountCatalogStore {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}

private struct CurrentFingerprintStub: LiveCodexAccountIdentityReading {
    let fingerprint: String?

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: fingerprint)
    }
}

private struct ReconcilePassthrough: StoredAccountIdentityReconciling {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
