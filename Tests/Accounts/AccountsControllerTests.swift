import Foundation
import Testing

@testable import CodexPill

@MainActor
struct AccountsControllerTests {
    @Test
    func completeIsolatedAddAccountHydratesNewInactiveAccountMetadata() async throws {
        let active = makeAccount(name: "Personal", fingerprint: "live-fingerprint")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [active])
        let liveIdentity = CurrentIdentityHarness(fingerprint: "live-fingerprint")
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: liveIdentity,
            storedAccountReconciler: StoredIdentityAdapter()
        )
        let authService = IsolatedAddAccountAuthProbe(
            currentFingerprint: "live-fingerprint",
            capturedFingerprint: "backup-fingerprint"
        )
        let hydratedRateLimits = makeRateLimitsSnapshot()
        let savedStatusClient = SavedAccountStatusFixture(statusBySnapshot: [
            "backup-fingerprint": CodexAccountStatus(
                email: "backup@example.com",
                planType: "free",
                rateLimits: hydratedRateLimits
            )
        ])
        let loginSession = IsolatedAddAccountLoginSessionProbe(authData: Data("captured-auth".utf8))
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: authService,
            savedAccountStatusClient: savedStatusClient,
            isolatedLoginClient: IsolatedAddAccountLoginClientProbe(session: loginSession)
        )

        controller.load()
        let session = try await controller.startIsolatedAddAccountFlow(named: "Backup")
        let savedAccount = try await controller.completeIsolatedAddAccount(session)

        let hydratedBackup = try #require(controller.accounts.first(where: { $0.id == savedAccount.id }))
        #expect(hydratedBackup.email == "backup@example.com")
        #expect(hydratedBackup.planType == "free")
        #expect(hydratedBackup.rateLimits == hydratedRateLimits)
        #expect(savedStatusClient.readSnapshots == [Data("backup-fingerprint".utf8)])
        #expect(controller.activeAccountID == active.id)
        #expect(controller.isBusy == false)
    }

    @Test
    func startIsolatedAddAccountRejectsOverlapWithoutClearingActiveOperation() async throws {
        let active = makeAccount(name: "Personal", fingerprint: "live-fingerprint")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [active])
        let liveIdentity = CurrentIdentityHarness(fingerprint: "live-fingerprint")
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: liveIdentity,
            storedAccountReconciler: StoredIdentityAdapter()
        )
        let authService = IsolatedAddAccountAuthProbe(
            currentFingerprint: "live-fingerprint",
            capturedFingerprint: "backup-fingerprint"
        )
        let loginSession = IsolatedAddAccountLoginSessionProbe(authData: Data("captured-auth".utf8))
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: authService,
            isolatedLoginClient: IsolatedAddAccountLoginClientProbe(session: loginSession)
        )

        controller.load()
        _ = try await controller.startIsolatedAddAccountFlow(named: "Backup")

        await #expect(throws: AccountsControllerError.operationAlreadyInProgress) {
            _ = try await controller.startIsolatedAddAccountFlow(named: "Backup 2")
        }
        #expect(controller.isBusy)
        #expect(controller.statusMessage == "Adding account...")
    }

    @Test
    func completeIsolatedAddAccountAlreadySavedDoesNotQueueSecondPendingError() async throws {
        let existing = makeAccount(name: "Business 1", fingerprint: "captured-fingerprint")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [existing])
        let liveIdentity = CurrentIdentityHarness(fingerprint: "live-fingerprint")
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: liveIdentity,
            storedAccountReconciler: StoredIdentityAdapter()
        )
        let authService = IsolatedAddAccountAuthProbe(
            currentFingerprint: "live-fingerprint",
            capturedFingerprint: "captured-fingerprint"
        )
        let loginSession = IsolatedAddAccountLoginSessionProbe(authData: Data("captured-auth".utf8))
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: authService,
            isolatedLoginClient: IsolatedAddAccountLoginClientProbe(session: loginSession)
        )

        controller.load()
        let session = try await controller.startIsolatedAddAccountFlow(named: "Business 2")

        await #expect(throws: AddAccountWorkflowError.accountAlreadySaved("Business 1")) {
            _ = try await controller.completeIsolatedAddAccount(session)
        }

        #expect(controller.pendingErrorMessage == nil)
        #expect(controller.consumePendingErrorMessage() == nil)
        #expect(loginSession.cleanupCount == 1)
    }

    @Test
    func refreshAccountDataFailureDoesNotQueuePendingErrorMessage() async {
        let account = makeAccount(name: "Business 4", fingerprint: "live")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [account])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: CurrentIdentityFixture(fingerprint: "live"),
            storedAccountReconciler: StoredIdentityAdapter()
        )
        let controller = AccountsController(
            identityResolver: identityResolver,
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                accountStatusClient: AccountStatusErrorCase(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: NullAuthService(),
                savedAccountStatusClient: DisabledAccountStatusClient(),
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            accountCatalogStore: repository,
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: NullAuthService(),
                repository: repository,
                codexAppProcessClient: NullCodexAppProcessClient(),
                identityResolver: identityResolver
            ),
            addAccountWorkflow: makeAddAccountWorkflow(
                repository: repository,
                identityResolver: identityResolver
            )
        )

        controller.load()
        let outcome = await controller.refreshAccountData(for: account)

        #expect(outcome == .failed("Background refresh failed."))
        #expect(controller.activeAccountID == account.id)
        #expect(controller.accounts == [account])
        #expect(controller.pendingErrorMessage == nil)
        #expect(controller.consumePendingErrorMessage() == nil)
    }

    @Test
    func refreshInactiveSavedAccountsMetadataRefreshesExistingRateLimits() async throws {
        let active = makeAccount(name: "Personal", fingerprint: "live-fingerprint")
        var inactive = makeAccount(name: "Backup", fingerprint: "backup-fingerprint")
        inactive.rateLimits = makeRateLimitsSnapshot()
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [active, inactive])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: CurrentIdentityFixture(fingerprint: "live-fingerprint"),
            storedAccountReconciler: StoredIdentityAdapter()
        )
        let authService = IsolatedAddAccountAuthProbe(
            currentFingerprint: "live-fingerprint",
            capturedFingerprint: "unused"
        )
        let refreshedRateLimits = CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "pro",
            primary: CodexRateLimitWindow(
                usedPercent: 70,
                resetsAt: Date(timeIntervalSince1970: 1_776_256_138),
                windowDurationMinutes: 300
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 30,
                resetsAt: Date(timeIntervalSince1970: 1_776_842_938),
                windowDurationMinutes: 10_080
            ),
            fetchedAt: Date(timeIntervalSince1970: 1_776_300_000)
        )
        let savedStatusClient = SavedAccountStatusFixture(statusBySnapshot: [
            "backup-fingerprint": CodexAccountStatus(
                email: "backup@example.com",
                planType: "pro",
                rateLimits: refreshedRateLimits
            )
        ])
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: authService,
            savedAccountStatusClient: savedStatusClient
        )

        controller.load()
        await controller.refreshInactiveSavedAccountsMetadata()

        let refreshedBackup = try #require(controller.accounts.first(where: { $0.id == inactive.id }))
        #expect(savedStatusClient.readSnapshots == [Data("backup-fingerprint".utf8)])
        #expect(refreshedBackup.rateLimits == refreshedRateLimits)
        #expect(refreshedBackup.email == "backup@example.com")
        #expect(refreshedBackup.planType == "pro")
    }

    @Test
    func refreshInactiveSavedAccountsMetadataRunsAtMostEveryFifteenMinutes() async throws {
        let active = makeAccount(name: "Personal", fingerprint: "live-fingerprint")
        var inactive = makeAccount(name: "Backup", fingerprint: "backup-fingerprint")
        inactive.rateLimits = makeRateLimitsSnapshot()
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [active, inactive])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: CurrentIdentityFixture(fingerprint: "live-fingerprint"),
            storedAccountReconciler: StoredIdentityAdapter()
        )
        let savedStatusClient = SavedAccountStatusFixture(statusBySnapshot: [:])
        var now = Date(timeIntervalSince1970: 1_776_300_000)
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: IsolatedAddAccountAuthProbe(currentFingerprint: "live-fingerprint", capturedFingerprint: "unused"),
            savedAccountStatusClient: savedStatusClient,
            now: { now }
        )
        let backupSnapshot = Data("backup-fingerprint".utf8)

        controller.load()
        await controller.refreshInactiveSavedAccountsMetadata()
        now += 14 * 60
        await controller.refreshInactiveSavedAccountsMetadata()

        #expect(savedStatusClient.readSnapshots == [backupSnapshot])

        now += 60
        await controller.refreshInactiveSavedAccountsMetadata()

        #expect(savedStatusClient.readSnapshots == [backupSnapshot, backupSnapshot])
    }

    @Test
    func switchToAccountSkipsSilentRefreshWhenNoActiveAccountResolves() async {
        let account = makeAccount(name: "Business 4", fingerprint: "live")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [account])
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: CurrentIdentityFixture(fingerprint: "other"),
                storedAccountReconciler: StoredIdentityAdapter()
            ),
            authService: NullAuthService()
        )
        controller.load()

        let didRefresh = await controller.switchToAccount(account)

        #expect(didRefresh == false)
        #expect(controller.activeAccountID == nil)
        #expect(controller.accounts == [account])
    }

    @Test
    func switchToAccountKeepsAccountsWhenSilentRefreshFails() async {
        let account = makeAccount(name: "Business 4", fingerprint: "live")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [account])
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: CurrentIdentityFixture(fingerprint: "live"),
                storedAccountReconciler: StoredIdentityAdapter()
            ),
            authService: NullAuthService()
        )
        controller.load()

        let didRefresh = await controller.switchToAccount(account)

        #expect(didRefresh == false)
        #expect(controller.activeAccountID == account.id)
        #expect(controller.accounts == [account])
        #expect(controller.pendingErrorMessage == nil)
    }

    @Test
    func switchToAccountAppliesSilentRefreshResult() async {
        let account = makeAccount(name: "Business 4", fingerprint: "live")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [account])
        let refreshedRateLimits = makeRateLimitsSnapshot()
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: CurrentIdentityFixture(fingerprint: "live"),
                storedAccountReconciler: StoredIdentityAdapter()
            ),
            authService: NullAuthService(),
            accountStatusClient: AccountStatusSuccessCase(
                status: CodexAccountStatus(
                    email: "business@example.com",
                    planType: "pro",
                    rateLimits: refreshedRateLimits
                )
            )
        )
        controller.load()

        let didRefresh = await controller.switchToAccount(account)

        #expect(didRefresh == true)
        #expect(controller.accounts.count == 1)
        #expect(controller.accounts[0].planType == "pro")
        #expect(controller.accounts[0].rateLimits == refreshedRateLimits)
        #expect(repository.savedAccounts == controller.accounts)
    }

    private func makeAddAccountWorkflow(
        repository: AccountCatalogStore,
        identityResolver: SavedAccountIdentityResolver
    ) -> AddAccountWorkflow {
        AddAccountWorkflow(
            authService: NullAuthService(),
            repository: repository,
            identityResolver: identityResolver
        )
    }

    private func makeController(
        repository: LoadingPersistingAccountCatalogProbe,
        identityResolver: SavedAccountIdentityResolver,
        authService: some CodexAuthSessionStore & CodexSignInAuthStore,
        accountStatusClient: CodexAccountStatusClient = AccountStatusErrorCase(error: TestFailure.backgroundRefreshFailed),
        savedAccountStatusClient: SavedCodexAccountStatusClient = DisabledAccountStatusClient(),
        isolatedLoginClient: IsolatedCodexLoginClient = IsolatedAddAccountLoginClientProbe(
            session: IsolatedAddAccountLoginSessionProbe(authData: Data())
        ),
        now: @escaping () -> Date = Date.init
    ) -> AccountsController {
        AccountsController(
            identityResolver: identityResolver,
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                accountStatusClient: accountStatusClient,
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: authService,
                savedAccountStatusClient: savedAccountStatusClient,
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            accountCatalogStore: repository,
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: authService,
                repository: repository,
                codexAppProcessClient: NullCodexAppProcessClient(),
                identityResolver: identityResolver
            ),
            addAccountWorkflow: AddAccountWorkflow(
                authService: authService,
                repository: repository,
                identityResolver: identityResolver,
                isolatedLoginClient: isolatedLoginClient
            ),
            now: now
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

    private func makeRateLimitsSnapshot() -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "free",
            primary: CodexRateLimitWindow(
                usedPercent: 11,
                resetsAt: Date(timeIntervalSince1970: 1_776_256_138),
                windowDurationMinutes: 300
            ),
            secondary: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_776_200_000)
        )
    }
}

private enum TestFailure: LocalizedError {
    case backgroundRefreshFailed

    var errorDescription: String? {
        switch self {
        case .backgroundRefreshFailed:
            "Background refresh failed."
        }
    }
}

private final class AccountStatusErrorCase: CodexAccountStatusClient {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        throw error
    }
}

private final class AccountStatusSuccessCase: CodexAccountStatusClient {
    let status: CodexAccountStatus

    init(status: CodexAccountStatus) {
        self.status = status
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        status
    }
}

private final class LoadingPersistingAccountCatalogProbe: AccountCatalogLoader, AccountSnapshotRemover, @unchecked Sendable {
    let accountsToLoad: [CodexAccount]
    private(set) var savedAccounts: [CodexAccount]?
    private(set) var bootstrapCount = 0

    init(accountsToLoad: [CodexAccount]) {
        self.accountsToLoad = accountsToLoad
    }

    func bootstrapStorage() throws {
        bootstrapCount += 1
    }

    func loadAccounts() throws -> [CodexAccount] {
        accountsToLoad
    }

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }

    func deleteSnapshot(for account: CodexAccount) throws {}
}

private final class CurrentIdentityFixture: LiveCodexAccountIdentitySource {
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

private final class ActiveSnapshotRelinkerProbe: ActiveAuthSnapshotRelinking {
    let currentFingerprint: String?
    let relinkedFingerprint: String

    init(currentFingerprint: String?, relinkedFingerprint: String) {
        self.currentFingerprint = currentFingerprint
        self.relinkedFingerprint = relinkedFingerprint
    }

    func currentAuthFingerprint() -> String? {
        currentFingerprint
    }

    func readCurrentAuthData() throws -> Data {
        Data("fresh-auth".utf8)
    }

    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
        var account = existing ?? CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: .empty
        )
        account.identity.snapshotFingerprint = relinkedFingerprint
        return account
    }
}

private final class CurrentIdentityHarness: LiveCodexAccountIdentitySource, @unchecked Sendable {
    var fingerprint: String?

    init(fingerprint: String?) {
        self.fingerprint = fingerprint
    }

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: fingerprint)
    }
}

private struct StoredIdentityAdapter: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}

private struct NullCodexAppProcessClient: CodexAppProcessClient {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}

private final class CodexAppProcessProbe: CodexAppProcessClient, @unchecked Sendable {
    private(set) var availabilityCheckCount = 0
    private(set) var relaunchCount = 0

    func assertCodexAvailable() throws {
        availabilityCheckCount += 1
    }

    func relaunchCodex() async throws {
        relaunchCount += 1
    }
}

private final class NullAuthService: CodexAuthSessionStore, CodexSignInAuthStore {

    func activate(_ account: CodexAccount) throws {}

    func readCurrentAuthData() throws -> Data { Data() }
    func readAuthSnapshot(for account: CodexAccount) throws -> Data { Data() }
    func currentAuthFingerprint() -> String? { nil }
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity { .empty }
    func restoreCurrentAuthData(_ data: Data) throws {}

    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
        if let existing {
            return existing
        }

        let id = UUID()
        return CodexAccount(
            id: id,
            name: name,
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: .empty
        )
    }

    func replaceAuthSnapshot(_ authData: Data, ifUnchangedFrom expected: Data, for account: CodexAccount) throws -> CodexAccount? { nil }
    func deleteAuthSnapshot(for account: CodexAccount) throws {}
}

private final class SignInAuthErrorCase: CodexAuthSessionStore, CodexSignInAuthStore {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func activate(_ account: CodexAccount) throws {}
    func readCurrentAuthData() throws -> Data { Data() }
    func readAuthSnapshot(for account: CodexAccount) throws -> Data { Data() }
    func currentAuthFingerprint() -> String? { nil }
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity { .empty }
    func restoreCurrentAuthData(_ data: Data) throws {}

    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
        throw error
    }

    func replaceAuthSnapshot(_ authData: Data, ifUnchangedFrom expected: Data, for account: CodexAccount) throws -> CodexAccount? {
        throw error
    }
    func deleteAuthSnapshot(for account: CodexAccount) throws {}
}

private final class IsolatedAddAccountAuthProbe: CodexAuthSessionStore, CodexSignInAuthStore, @unchecked Sendable {
    var currentFingerprint: String?
    let capturedFingerprint: String?

    init(currentFingerprint: String?, capturedFingerprint: String?) {
        self.currentFingerprint = currentFingerprint
        self.capturedFingerprint = capturedFingerprint
    }

    func activate(_ account: CodexAccount) throws {}
    func readCurrentAuthData() throws -> Data { Data() }
    func readAuthSnapshot(for account: CodexAccount) throws -> Data {
        Data((account.identity.snapshotFingerprint ?? "").utf8)
    }
    func currentAuthFingerprint() -> String? { currentFingerprint }
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: capturedFingerprint)
    }
    func restoreCurrentAuthData(_ data: Data) throws {}
    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
        let id = UUID()
        return CodexAccount(
            id: id,
            name: name,
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(snapshotFingerprint: capturedFingerprint)
        )
    }
    func replaceAuthSnapshot(_ authData: Data, ifUnchangedFrom expected: Data, for account: CodexAccount) throws -> CodexAccount? { nil }
    func deleteAuthSnapshot(for account: CodexAccount) throws {}
}

private final class SavedAccountStatusFixture: SavedCodexAccountStatusClient, @unchecked Sendable {
    let statusBySnapshot: [String: CodexAccountStatus]
    private(set) var readSnapshots: [Data] = []

    init(statusBySnapshot: [String: CodexAccountStatus]) {
        self.statusBySnapshot = statusBySnapshot
    }

    func readSavedAccountStatus(authData: Data) async -> SavedCodexAccountStatusRead {
        readSnapshots.append(authData)
        let snapshot = String(decoding: authData, as: UTF8.self)
        guard let status = statusBySnapshot[snapshot] else {
            return SavedCodexAccountStatusRead(status: .failure(NSError(domain: "SavedAccountStatusFixture", code: 1)), rotatedAuthData: nil)
        }
        return SavedCodexAccountStatusRead(status: .success(status), rotatedAuthData: nil)
    }
}

private struct IsolatedAddAccountLoginClientProbe: IsolatedCodexLoginClient {
    let session: IsolatedCodexLoginSession

    func startLogin() async throws -> IsolatedCodexLoginSession {
        session
    }
}

private final class IsolatedAddAccountLoginSessionProbe: IsolatedCodexLoginSession, @unchecked Sendable {
    let prompt = IsolatedCodexLoginPrompt(
        url: URL(string: "https://auth.openai.com/codex/device")!,
        userCode: "ABCD-EFGH"
    )
    let codexHome = URL(fileURLWithPath: "/tmp/codexpill-test-codex-home")
    let authData: Data
    private(set) var cleanupCount = 0

    init(authData: Data) {
        self.authData = authData
    }

    func waitForAuthData() async throws -> Data { authData }
    func verifyLoginStatus() async -> Bool { true }
    func cancel() {}
    func cleanup() {
        cleanupCount += 1
    }
}
