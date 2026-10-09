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
        let account = makeAccount(name: "Work", email: "old@example.com", fingerprint: "live")
        var accountWithRateLimits = account
        accountWithRateLimits.rateLimits = existingRateLimits
        let repository = PersistingAccountCatalogProbe()
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: StubAccountStatusClient(
                status: CodexAccountStatus(
                    email: "new@example.com",
                    planType: "plus",
                    rateLimits: refreshedRateLimits
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: repository
        )

        let result = try await useCase.run(accounts: [accountWithRateLimits])

        #expect(result.refreshedAccountID == account.id)
        #expect(result.accounts.first?.email == "new@example.com")
        #expect(result.accounts.first?.planType == "prolite")
        #expect(result.accounts.first?.rateLimits == refreshedRateLimits)
        #expect(repository.savedAccounts == result.accounts)
        #expect(result.accounts.first?.updatedAt != .distantPast)
    }

    @Test
    func runRelinksSavedSnapshotWhenLiveAuthFingerprintChangedForSameAccount() async throws {
        var account = makeAccount(name: "Personal", email: "personal@example.com", fingerprint: "stale-fingerprint")
        account.identity.stableAccountID = "acct_personal"
        account.updatedAt = Date(timeIntervalSince1970: 1_744_195_200)
        let relinker = ActiveAuthSnapshotRelinkerProbe(
            currentFingerprint: "fresh-fingerprint",
            currentAuthData: Data("fresh-auth".utf8),
            relinkedAccount: {
                var relinked = account
                relinked.identity.snapshotFingerprint = "fresh-fingerprint"
                return relinked
            }()
        )
        let repository = PersistingAccountCatalogProbe()
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: StubAccountStatusClient(
                status: CodexAccountStatus(
                    email: "personal@example.com",
                    planType: "prolite",
                    rateLimits: nil,
                    stableAccountID: "acct_personal",
                    snapshotFingerprint: "fresh-fingerprint"
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(
                    fingerprint: "fresh-fingerprint",
                    stableAccountID: "acct_personal"
                ),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: repository,
            activeAuthSnapshotRelinker: relinker
        )

        let result = try await useCase.run(accounts: [account])

        #expect(result.refreshedAccountID == account.id)
        #expect(result.accounts.first?.identity.snapshotFingerprint == "fresh-fingerprint")
        #expect(relinker.savedAuthData == Data("fresh-auth".utf8))
        #expect(relinker.savedExistingAccount?.id == account.id)
        #expect(result.accounts.first?.updatedAt == account.updatedAt)
        #expect(repository.savedAccounts == result.accounts)
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
        var account = makeAccount(name: "Work", email: "old@example.com", fingerprint: "live")
        account.updatedAt = existingUpdatedAt
        account.rateLimits = existingRateLimits
        let repository = PersistingAccountCatalogProbe()
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: StubAccountStatusClient(
                status: CodexAccountStatus(
                    email: "new@example.com",
                    planType: "pro",
                    rateLimits: nil
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
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
        let account = makeAccount(name: "Work", email: "saved@example.com", fingerprint: "saved")
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: StubAccountStatusClient(
                status: CodexAccountStatus(
                    email: "other@example.com",
                    planType: nil,
                    rateLimits: nil
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: PersistingAccountCatalogProbe()
        )

        await #expect(throws: RefreshActiveAccountUseCaseError.targetResolutionFailed(.noMatch)) {
            try await useCase.run(accounts: [account])
        }
    }
}

private final class PersistingAccountCatalogProbe: AccountCatalogStore, @unchecked Sendable {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}

private final class ActiveAuthSnapshotRelinkerProbe: ActiveAuthSnapshotRelinking, @unchecked Sendable {
    let currentFingerprint: String?
    let currentAuthData: Data
    let relinkedAccount: CodexAccount
    private(set) var savedAuthData: Data?
    private(set) var savedExistingAccount: CodexAccount?

    init(currentFingerprint: String?, currentAuthData: Data, relinkedAccount: CodexAccount) {
        self.currentFingerprint = currentFingerprint
        self.currentAuthData = currentAuthData
        self.relinkedAccount = relinkedAccount
    }

    func currentAuthFingerprint() -> String? {
        currentFingerprint
    }

    func readCurrentAuthData() throws -> Data {
        currentAuthData
    }

    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
        savedAuthData = authData
        savedExistingAccount = existing
        return relinkedAccount
    }
}
