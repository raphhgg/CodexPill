import Foundation

@MainActor
struct AccountsFeatureFactory {
    private let repository: AccountRepository
    private let authService: CodexAuthSnapshotService
    private let codexAppProcessClient: CodexAppProcessClient
    private let accountStatusClient: CodexAccountStatusClient & SavedCodexAccountStatusClient
    private let remoteHostSwitchOperations: RemoteHostSwitchWorkflowOperations

    init(
        repository: AccountRepository,
        authService: CodexAuthSnapshotService,
        codexAppProcessClient: CodexAppProcessClient,
        accountStatusClient: CodexAccountStatusClient & SavedCodexAccountStatusClient,
        remoteHostSwitchOperations: RemoteHostSwitchWorkflowOperations = UnavailableRemoteHostClient()
    ) {
        self.repository = repository
        self.authService = authService
        self.codexAppProcessClient = codexAppProcessClient
        self.accountStatusClient = accountStatusClient
        self.remoteHostSwitchOperations = remoteHostSwitchOperations
    }

    func makeMenuBarAccountsStore() -> MenuBarAccountsStore {
        MenuBarAccountsStore(controller: makeController())
    }

    func makeController() -> AccountsController {
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: authService,
            storedAccountReconciler: authService
        )
        let refreshActiveAccountUseCase = RefreshActiveAccountUseCase(
            accountStatusClient: accountStatusClient,
            identityResolver: identityResolver,
            repository: repository,
            activeAuthSnapshotRelinker: authService
        )

        return AccountsController(
            identityResolver: identityResolver,
            inactiveAccountAvailabilityRanking: InactiveAccountAvailabilityRanking(),
            operationState: AccountOperationState(),
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: refreshActiveAccountUseCase,
            silentPostActionRefresh: SilentPostActionRefresh(
                refreshActiveAccountUseCase: refreshActiveAccountUseCase
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: authService,
                savedAccountStatusClient: accountStatusClient,
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver,
                authSignerOut: CodexLocalAuthSignOut(
                    authService: authService,
                    codexAppProcessClient: codexAppProcessClient
                )
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            persistSavedAccountMetadataUseCase: PersistSavedAccountMetadataUseCase(repository: repository),
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: authService,
                repository: repository,
                codexAppProcessClient: codexAppProcessClient,
                identityResolver: identityResolver
            ),
            switchAccountOnHostWorkflow: SwitchAccountOnHostWorkflow(
                remoteHostSwitchOperations: remoteHostSwitchOperations
            ),
            remoteHostAccountVerifier: RemoteHostAccountVerifier(),
            addAccountWorkflow: AddAccountWorkflow(
                authService: authService,
                repository: repository,
                identityResolver: identityResolver
            )
        )
    }
}
