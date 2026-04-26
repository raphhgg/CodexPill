import Foundation
import Testing

@testable import CodexPill

@MainActor
struct AccountsControllerTests {
    @Test
    func startSignInAnotherAccountFlowClearsActiveAccountUntilCodexCompletesSignIn() async {
        let business1 = makeAccount(name: "Business 1", fingerprint: "business-1")
        let business2 = makeAccount(name: "Business 2", fingerprint: "business-2")
        let repository = LoadingPersistingRepositorySpy(accountsToLoad: [business1, business2])
        let liveIdentity = MutableCurrentIdentityStub(fingerprint: "business-2")
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentityReader: liveIdentity,
            storedAccountReconciler: StoredIdentityPassthrough()
        )
        let controller = AccountsController(
            identityResolver: identityResolver,
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: NoopAuthService(),
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            persistSavedAccountMetadataUseCase: PersistSavedAccountMetadataUseCase(repository: repository),
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: NoopAuthService(),
                repository: repository,
                codexAppProcessClient: DisabledCodexAppProcessClient(),
                identityResolver: identityResolver
            ),
            saveCurrentAccountWorkflow: SaveCurrentAccountWorkflow(
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                authService: NoopAuthService(),
                repository: repository,
                identityResolver: identityResolver
            ),
            signInAnotherWorkflow: makeSignInAnotherWorkflow(
                repository: repository,
                identityResolver: identityResolver
            )
        )

        controller.load()
        #expect(controller.activeAccountID == business2.id)

        liveIdentity.fingerprint = "business-1"

        await controller.startSignInAnotherAccountFlow(named: "Business 3")

        #expect(controller.activeAccountID == nil)
        #expect(controller.hasPendingSignedInAccount)
    }

    @Test
    func startSignInAnotherAccountFlowRejectsDuplicateNameBeforeOpeningCodexSignIn() async {
        let business1 = makeAccount(name: "Business 1", fingerprint: "business-1")
        let repository = LoadingPersistingRepositorySpy(accountsToLoad: [business1])
        let liveIdentity = MutableCurrentIdentityStub(fingerprint: "business-1")
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentityReader: liveIdentity,
            storedAccountReconciler: StoredIdentityPassthrough()
        )
        let processClient = RecordingCodexAppProcessClient()
        let authService = NoopAuthService()
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: authService,
            codexAppProcessClient: processClient
        )

        controller.load()
        await controller.startSignInAnotherAccountFlow(named: " business 1 ")

        #expect(controller.activeAccountID == business1.id)
        #expect(!controller.hasPendingSignedInAccount)
        #expect(processClient.availabilityCheckCount == 0)
        #expect(processClient.relaunchCount == 0)
        #expect(authService.prepareForNewSignInCount == 0)
        #expect(controller.consumePendingErrorMessage() == "An account with that name already exists.")
    }

    @Test
    func completePendingSignedInAccountClearsPendingFlowAfterTerminalSaveFailure() async {
        let business1 = makeAccount(name: "Business 1", fingerprint: "business-1")
        let repository = LoadingPersistingRepositorySpy(accountsToLoad: [business1])
        let liveIdentity = MutableCurrentIdentityStub(fingerprint: "business-1")
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentityReader: liveIdentity,
            storedAccountReconciler: StoredIdentityPassthrough()
        )
        let authService = ThrowingSignInAuthService(error: SaveCurrentAccountWorkflowError.duplicateAccountName)
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: authService,
            codexAppProcessClient: RecordingCodexAppProcessClient()
        )

        controller.load()
        await controller.startSignInAnotherAccountFlow(named: "Business 2")
        liveIdentity.fingerprint = nil

        await controller.completePendingSignedInAccountIfNeeded()

        #expect(!controller.hasPendingSignedInAccount)
        #expect(controller.consumePendingErrorMessage() == "An account with that name already exists.")

        await controller.completePendingSignedInAccountIfNeeded()

        #expect(controller.consumePendingErrorMessage() == nil)
    }

    @Test
    func refreshAccountDataFailureDoesNotQueuePendingErrorMessage() async {
        let account = makeAccount(name: "Business 4", fingerprint: "live")
        let repository = LoadingPersistingRepositorySpy(accountsToLoad: [account])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentityReader: CurrentIdentityStub(fingerprint: "live"),
            storedAccountReconciler: StoredIdentityPassthrough()
        )
        let controller = AccountsController(
            identityResolver: identityResolver,
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: NoopAuthService(),
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            persistSavedAccountMetadataUseCase: PersistSavedAccountMetadataUseCase(repository: repository),
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: NoopAuthService(),
                repository: repository,
                codexAppProcessClient: DisabledCodexAppProcessClient(),
                identityResolver: identityResolver
            ),
            saveCurrentAccountWorkflow: SaveCurrentAccountWorkflow(
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                authService: NoopAuthService(),
                repository: repository,
                identityResolver: identityResolver
            ),
            signInAnotherWorkflow: makeSignInAnotherWorkflow(
                repository: repository,
                identityResolver: identityResolver
            )
        )

        controller.load()
        let outcome = await controller.refreshAccountData(for: account)

        #expect(outcome == .failed)
        #expect(controller.activeAccountID == account.id)
        #expect(controller.accounts == [account])
        #expect(controller.pendingErrorMessage == nil)
        #expect(controller.consumePendingErrorMessage() == nil)
    }

    @Test
    func switchToAccountOnHostReportsVerificationMismatchAsPendingError() async {
        let target = CodexAccount(
            id: UUID(),
            name: "Business 4",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-4@example.com",
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: "target",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "business-4@example.com")
            )
        )
        let other = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-2@example.com",
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: "other",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "business-2@example.com")
            )
        )
        let repository = LoadingPersistingRepositorySpy(accountsToLoad: [target, other])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentityReader: CurrentIdentityStub(fingerprint: nil),
            storedAccountReconciler: StoredIdentityPassthrough()
        )
        let controller = AccountsController(
            identityResolver: identityResolver,
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: NoopAuthService(),
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            persistSavedAccountMetadataUseCase: PersistSavedAccountMetadataUseCase(repository: repository),
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: NoopAuthService(),
                repository: repository,
                codexAppProcessClient: DisabledCodexAppProcessClient(),
                identityResolver: identityResolver
            ),
            switchAccountOnHostWorkflow: SwitchAccountOnHostWorkflow(
                remoteHostClient: RemoteHostStatusStub(
                    status: CodexAccountStatus(
                        email: other.email,
                        planType: other.planType,
                        rateLimits: nil
                    )
                )
            ),
            saveCurrentAccountWorkflow: SaveCurrentAccountWorkflow(
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                authService: NoopAuthService(),
                repository: repository,
                identityResolver: identityResolver
            ),
            signInAnotherWorkflow: makeSignInAnotherWorkflow(
                repository: repository,
                identityResolver: identityResolver
            )
        )

        controller.load()
        let result = await controller.switchToAccountOnHost(
            target,
            on: RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        )

        #expect(result == .notVerified("buildbox is using \(other.name), not \(target.name).", detectedAccountID: other.id))
        #expect(controller.pendingErrorMessage == "buildbox is using \(other.name), not \(target.name).")
        #expect(controller.consumePendingErrorMessage() == "buildbox is using \(other.name), not \(target.name).")
    }

    @Test
    func switchToAccountOnHostMarksAuthReadFailureAsReachableFailure() async {
        let account = makeAccount(name: "Business", fingerprint: "fingerprint")
        let repository = LoadingPersistingRepositorySpy(accountsToLoad: [account])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentityReader: CurrentIdentityStub(fingerprint: nil),
            storedAccountReconciler: StoredIdentityPassthrough()
        )
        let controller = AccountsController(
            identityResolver: identityResolver,
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: NoopAuthService(),
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            persistSavedAccountMetadataUseCase: PersistSavedAccountMetadataUseCase(repository: repository),
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: NoopAuthService(),
                repository: repository,
                codexAppProcessClient: DisabledCodexAppProcessClient(),
                identityResolver: identityResolver
            ),
            switchAccountOnHostWorkflow: SwitchAccountOnHostWorkflow(
                remoteHostClient: RemoteHostFailingStub(error: RemoteHostClientError.authReadFailed("cat: .codex/auth.json: Permission denied"))
            ),
            saveCurrentAccountWorkflow: SaveCurrentAccountWorkflow(
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                authService: NoopAuthService(),
                repository: repository,
                identityResolver: identityResolver
            ),
            signInAnotherWorkflow: makeSignInAnotherWorkflow(
                repository: repository,
                identityResolver: identityResolver
            )
        )

        controller.load()
        let result = await controller.switchToAccountOnHost(
            account,
            on: RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        )

        #expect(result == .failed("cat: .codex/auth.json: Permission denied", hostReachable: true))
        #expect(controller.pendingErrorMessage == "cat: .codex/auth.json: Permission denied")
    }

    private func makeSignInAnotherWorkflow(
        repository: AccountCatalogStore,
        identityResolver: SavedAccountIdentityResolver
    ) -> SignInAnotherWorkflow {
        SignInAnotherWorkflow(
            authService: NoopAuthService(),
            codexAppProcessClient: DisabledCodexAppProcessClient(),
            accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
            repository: repository,
            identityResolver: identityResolver
        )
    }

    private func makeController(
        repository: LoadingPersistingRepositorySpy,
        identityResolver: SavedAccountIdentityResolver,
        authService: some CodexAuthDataRestoring & CodexAuthSnapshotSaving & CodexSignInAnotherAuthHandling,
        codexAppProcessClient: CodexAppProcessClient
    ) -> AccountsController {
        AccountsController(
            identityResolver: identityResolver,
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: authService,
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            persistSavedAccountMetadataUseCase: PersistSavedAccountMetadataUseCase(repository: repository),
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: authService,
                repository: repository,
                codexAppProcessClient: codexAppProcessClient,
                identityResolver: identityResolver
            ),
            saveCurrentAccountWorkflow: SaveCurrentAccountWorkflow(
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                authService: authService,
                repository: repository,
                identityResolver: identityResolver
            ),
            signInAnotherWorkflow: SignInAnotherWorkflow(
                authService: authService,
                codexAppProcessClient: codexAppProcessClient,
                accountStatusClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                repository: repository,
                identityResolver: identityResolver
            )
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

private enum TestFailure: LocalizedError {
    case backgroundRefreshFailed

    var errorDescription: String? {
        switch self {
        case .backgroundRefreshFailed:
            "Background refresh failed."
        }
    }
}

private final class FailingAccountStatusReader: CodexAccountStatusClient {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        throw error
    }
}

private final class LoadingPersistingRepositorySpy: AccountCatalogLoader, AccountSnapshotRemover {
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

private final class CurrentIdentityStub: LiveCodexAccountIdentityReading {
    let fingerprint: String?

    init(fingerprint: String?) {
        self.fingerprint = fingerprint
    }

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: fingerprint)
    }
}

private final class MutableCurrentIdentityStub: LiveCodexAccountIdentityReading {
    var fingerprint: String?

    init(fingerprint: String?) {
        self.fingerprint = fingerprint
    }

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: fingerprint)
    }
}

private struct StoredIdentityPassthrough: StoredAccountIdentityReconciling {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}

private struct DisabledCodexAppProcessClient: CodexAppProcessClient {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}

private final class RecordingCodexAppProcessClient: CodexAppProcessClient {
    private(set) var availabilityCheckCount = 0
    private(set) var relaunchCount = 0

    func assertCodexAvailable() throws {
        availabilityCheckCount += 1
    }

    func relaunchCodex() async throws {
        relaunchCount += 1
    }
}

private final class NoopAuthService: CodexAuthDataRestoring, CodexAuthSnapshotSaving, CodexSignInAnotherAuthHandling {
    private(set) var prepareForNewSignInCount = 0

    func activate(_ account: CodexAccount) throws {}

    func prepareForNewSignIn() throws {
        prepareForNewSignInCount += 1
    }

    func readCurrentAuthData() throws -> Data { Data() }
    func restoreCurrentAuthData(_ data: Data) throws {}
    func saveCurrentAuthSnapshot(named name: String, existing: CodexAccount?) throws -> CodexAccount {
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
}

private final class ThrowingSignInAuthService: CodexAuthDataRestoring, CodexAuthSnapshotSaving, CodexSignInAnotherAuthHandling {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func activate(_ account: CodexAccount) throws {}
    func prepareForNewSignIn() throws {}
    func readCurrentAuthData() throws -> Data { Data() }
    func restoreCurrentAuthData(_ data: Data) throws {}
    func saveCurrentAuthSnapshot(named name: String, existing: CodexAccount?) throws -> CodexAccount {
        throw error
    }
}

private struct RemoteHostStatusStub: RemoteHostSwitching {
    let status: CodexAccountStatus

    func testConnection(to host: RemoteHost) async throws {}
    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState { .installed }
    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func refreshCodexAppServer(on host: RemoteHost) async throws {}
    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus { status }
}

private struct RemoteHostFailingStub: RemoteHostSwitching {
    let error: Error

    func testConnection(to host: RemoteHost) async throws {}
    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState { .installed }
    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func refreshCodexAppServer(on host: RemoteHost) async throws {}
    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus { throw error }
}
