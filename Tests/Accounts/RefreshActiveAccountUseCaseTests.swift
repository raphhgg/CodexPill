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
        let repository = PersistingAccountCatalogProbe()
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: AccountStatusProbe(
                status: CodexAccountStatus(
                    email: "new@example.com",
                    planType: "plus",
                    rateLimits: refreshedRateLimits
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: CurrentIdentityFixture(fingerprint: "live"),
                storedAccountReconciler: IdentityReconcilerAdapter()
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
        var account = makeAccount(name: "Personal", fingerprint: "stale-fingerprint", email: "personal@example.com")
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
            accountStatusClient: AccountStatusProbe(
                status: CodexAccountStatus(
                    email: "personal@example.com",
                    planType: "prolite",
                    rateLimits: nil,
                    stableAccountID: "acct_personal",
                    snapshotFingerprint: "fresh-fingerprint"
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: CurrentIdentityFixture(
                    stableAccountID: "acct_personal",
                    fingerprint: "fresh-fingerprint"
                ),
                storedAccountReconciler: IdentityReconcilerAdapter()
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
        var account = makeAccount(name: "Work", fingerprint: "live", email: "old@example.com")
        account.updatedAt = existingUpdatedAt
        account.rateLimits = existingRateLimits
        let repository = PersistingAccountCatalogProbe()
        let useCase = RefreshActiveAccountUseCase(
            accountStatusClient: AccountStatusProbe(
                status: CodexAccountStatus(
                    email: "new@example.com",
                    planType: "pro",
                    rateLimits: nil
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: CurrentIdentityFixture(fingerprint: "live"),
                storedAccountReconciler: IdentityReconcilerAdapter()
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
            accountStatusClient: AccountStatusProbe(
                status: CodexAccountStatus(
                    email: "other@example.com",
                    planType: nil,
                    rateLimits: nil
                )
            ),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: CurrentIdentityFixture(fingerprint: "live"),
                storedAccountReconciler: IdentityReconcilerAdapter()
            ),
            repository: PersistingAccountCatalogProbe()
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

private final class AccountStatusProbe: CodexAccountStatusClient {
    let status: CodexAccountStatus

    init(status: CodexAccountStatus) {
        self.status = status
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        status
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

private struct CurrentIdentityFixture: LiveCodexAccountIdentitySource {
    let stableAccountID: String?
    let fingerprint: String?

    init(stableAccountID: String? = nil, fingerprint: String?) {
        self.stableAccountID = stableAccountID
        self.fingerprint = fingerprint
    }

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(
            stableAccountID: stableAccountID,
            snapshotFingerprint: fingerprint
        )
    }
}

private struct IdentityReconcilerAdapter: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
