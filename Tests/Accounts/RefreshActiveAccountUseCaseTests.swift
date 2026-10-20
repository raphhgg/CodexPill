import Foundation
import Testing

@testable import rusage

struct RefreshActiveAccountUseCaseTests {
    @Test
    func runRefreshesMatchedAccountWithoutSavingTheCatalog() async throws {
        let refreshedRateLimits = UsageSnapshot.codex(
            planName: "prolite",
            primary: (usedPercent: 40, resetsAt: .now.addingTimeInterval(5400), durationMinutes: 300),
            secondary: (usedPercent: 6, resetsAt: .now.addingTimeInterval(86_400), durationMinutes: 10_080),
            fetchedAt: .now
        )
        let existingRateLimits = UsageSnapshot.codex(
            planName: "plus",
            primary: (usedPercent: 25, resetsAt: .now.addingTimeInterval(3600), durationMinutes: 300),
            secondary: nil,
            fetchedAt: .distantPast
        )
        let account = makeAccount(email: "old@example.com", fingerprint: "live")
        var accountWithRateLimits = account
        accountWithRateLimits.usage = existingRateLimits
        let repository = PersistingAccountCatalogProbe()
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: StubAccountStatusClient(
                status: CodexAccountStatus(
                    email: "new@example.com",
                    planType: "plus",
                    usage: refreshedRateLimits
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: repository
        )

        let result = try await useCase.run(accounts: [accountWithRateLimits])

        #expect(result.update.accountID == account.id)
        #expect(result.update.email == "new@example.com")
        #expect(result.update.planType == "prolite")
        #expect(result.update.usage == refreshedRateLimits)
        #expect(repository.savedAccounts == nil)
        #expect(result.update.updatedAt != .distantPast)
    }

    @Test
    func saveRelinksSavedSnapshotWhenLiveAuthFingerprintChangedForSameAccount() async throws {
        var account = makeAccount(email: "personal@example.com", fingerprint: "stale-fingerprint")
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
                    usage: nil,
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
        #expect(relinker.savedAuthData == nil)

        let savedAccounts = try #require(try useCase.save(result, into: [account]))

        #expect(savedAccounts.map(\.identity.snapshotFingerprint) == ["fresh-fingerprint"])
        #expect(savedAccounts.map(\.updatedAt) == [account.updatedAt])
        #expect(relinker.savedAuthData == Data("fresh-auth".utf8))
        #expect(relinker.savedExistingAccount?.id == account.id)
        #expect(repository.savedAccounts?.map(\.identity.snapshotFingerprint) == ["fresh-fingerprint"])
    }

    @Test
    func runDoesNotMarkPreservedRateLimitsFreshWhenAppServerReturnsNoRateLimits() async throws {
        let existingUpdatedAt = Date(timeIntervalSince1970: 1_744_195_200)
        let existingRateLimits = UsageSnapshot.codex(
            planName: "plus",
            primary: (usedPercent: 25, resetsAt: .now.addingTimeInterval(3600), durationMinutes: 300),
            secondary: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_744_195_100)
        )
        var account = makeAccount(email: "old@example.com", fingerprint: "live")
        account.updatedAt = existingUpdatedAt
        account.usage = existingRateLimits
        let repository = PersistingAccountCatalogProbe()
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: StubAccountStatusClient(
                status: CodexAccountStatus(
                    email: "new@example.com",
                    planType: "pro",
                    usage: nil
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: repository
        )

        let result = try await useCase.run(accounts: [account])

        #expect(result.update.email == "new@example.com")
        #expect(result.update.planType == "pro")
        #expect(result.update.usage == existingRateLimits)
        #expect(result.update.updatedAt == existingUpdatedAt)
        #expect(repository.savedAccounts == nil)
    }

    @Test
    func runFailsWhenLiveAccountDoesNotMatchAnySavedAccount() async {
        let account = makeAccount(email: "saved@example.com", fingerprint: "saved")
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: StubAccountStatusClient(
                status: CodexAccountStatus(
                    email: "other@example.com",
                    planType: nil,
                    usage: nil
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

    func saveAuthSnapshot(_ authData: Data, existing: CodexAccount?) throws -> CodexAccount {
        savedAuthData = authData
        savedExistingAccount = existing
        return relinkedAccount
    }
}
