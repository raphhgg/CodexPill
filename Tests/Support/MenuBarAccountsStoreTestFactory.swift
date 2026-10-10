import Foundation

@testable import CodexPill

@MainActor
extension MenuBarAccountsStore {
    convenience init(
        repository: AccountRepository,
        authService: CodexAuthSnapshotService,
        codexAppProcessClient: CodexAppProcessClient,
        accountStatusClient: CodexAccountStatusClient & SavedCodexAccountStatusClient,
        remoteHostSwitchOperations: RemoteHostSwitchWorkflowOperations = UnavailableRemoteHostClient()
    ) {
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: authService,
            storedAccountReconciler: authService
        )
        let refreshActiveAccountUseCase = RefreshActiveAccountUseCase(
            accountStatusClient: accountStatusClient,
            identityResolver: identityResolver,
            repository: repository
        )
        self.init(
            controller: AccountsController(
                identityResolver: identityResolver,
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
        )
    }
}
