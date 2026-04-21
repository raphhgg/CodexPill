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
            switchAccountOnHostWorkflow: SwitchAccountOnHostWorkflow(
                remoteHostClient: RemoteHostFailingStub(error: RemoteHostClientError.authReadFailed("cat: .codex/auth.json: Permission denied"))
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
        let result = await controller.switchToAccountOnHost(
            account,
            on: RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        )

        #expect(result == .failed("cat: .codex/auth.json: Permission denied", hostReachable: true))
        #expect(controller.pendingErrorMessage == "cat: .codex/auth.json: Permission denied")
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

private struct RemoteHostStatusStub: RemoteHostSwitching {
    let status: CodexAccountStatus

    func testConnection(to host: RemoteHost) async throws {}
    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState { .installed }
    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus { status }
}

private struct RemoteHostFailingStub: RemoteHostSwitching {
    let error: Error

    func testConnection(to host: RemoteHost) async throws {}
    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState { .installed }
    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus { throw error }
}
