import Foundation
import Testing

@testable import CodexPill

@MainActor
struct AccountsControllerTests {
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
                appServerClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: NoopAuthService(),
                appServerClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: NoopAuthService(),
                repository: repository,
                appController: NoopAppController(),
                identityResolver: identityResolver
            ),
            saveCurrentAccountWorkflow: SaveCurrentAccountWorkflow(
                appServerClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                authService: NoopAuthService(),
                repository: repository,
                identityResolver: identityResolver
            ),
            signInAnotherWorkflow: SignInAnotherWorkflow(
                authService: NoopAuthService(),
                appController: NoopAppController(),
                appServerClient: FailingAccountStatusReader(error: TestFailure.backgroundRefreshFailed),
                repository: repository,
                identityResolver: identityResolver
            )
        )

        controller.load()
        await controller.refreshAccountData(for: account)

        #expect(controller.activeAccountID == account.id)
        #expect(controller.accounts == [account])
        #expect(controller.pendingErrorMessage == nil)
        #expect(controller.consumePendingErrorMessage() == nil)
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

private final class FailingAccountStatusReader: CodexAccountStatusReading {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        throw error
    }
}

private final class LoadingPersistingRepositorySpy: AccountCatalogLoading, AccountSnapshotDeleting {
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

private struct CurrentIdentityStub: LiveCodexAccountIdentityReading {
    let fingerprint: String?

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: fingerprint)
    }
}

private struct StoredIdentityPassthrough: StoredAccountIdentityReconciling {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}

private struct NoopAppController: CodexAppRelaunching {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}

private struct NoopAuthService: CodexAuthDataRestoring, CodexAuthSnapshotSaving, CodexSignInAnotherAuthHandling {
    func activate(_ account: CodexAccount) throws {}
    func readCurrentAuthData() throws -> Data { Data() }
    func restoreCurrentAuthData(_ data: Data) throws {}
    func prepareForNewSignIn() throws {}
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
