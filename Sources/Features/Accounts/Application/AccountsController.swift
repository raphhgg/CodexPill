import Foundation
import Observation
import OSLog

private let accountsControllerLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "AccountsController")

@MainActor
@Observable
final class AccountsController {
    enum BackgroundRefreshOutcome: Equatable {
        case refreshed
        case failed
    }

    enum RemoteHostSwitchOutcome: Equatable {
        case verified(CodexAccountStatus)
        case notVerified(String, detectedAccountID: UUID?)
        case failed(String, hostReachable: Bool)
    }

    private let identityResolver: SavedAccountIdentityResolver
    private let inactiveAccountAvailabilityRanking: InactiveAccountAvailabilityRanking
    private let pendingSignInLifecycle: PendingSignInLifecycle
    private let silentPostActionRefresh: SilentPostActionRefresh
    private let operationState: AccountOperationState
    private let loadAccountsUseCase: LoadAccountsUseCase
    private let refreshActiveAccountUseCase: RefreshActiveAccountUseCase
    private let hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase
    private let deleteSavedAccountUseCase: DeleteSavedAccountUseCase
    private let renameSavedAccountUseCase: RenameSavedAccountUseCase
    private let switchAccountWorkflow: SwitchAccountWorkflow
    private let switchAccountOnHostWorkflow: SwitchAccountOnHostWorkflow
    private let remoteHostAccountVerifier: RemoteHostAccountVerifier
    private let saveCurrentAccountWorkflow: SaveCurrentAccountWorkflow
    private let signInAnotherWorkflow: SignInAnotherWorkflow

    private var catalogState = AccountCatalogState()
    private var isHydratingSavedAccountsMetadata = false

    init(
        repository: AccountRepository,
        authService: CodexAuthSnapshotService,
        appController: CodexAppController,
        appServerClient: CodexAppServerClient,
        remoteHostClient: RemoteHostSwitching = UnavailableRemoteHostClient()
    ) {
        self.identityResolver = SavedAccountIdentityResolver(
            liveIdentityReader: authService,
            storedAccountReconciler: authService
        )
        self.inactiveAccountAvailabilityRanking = InactiveAccountAvailabilityRanking()
        self.pendingSignInLifecycle = PendingSignInLifecycle()
        self.operationState = AccountOperationState()
        let loadAccountsUseCase = LoadAccountsUseCase(
            repository: repository,
            identityResolver: self.identityResolver
        )
        let refreshActiveAccountUseCase = RefreshActiveAccountUseCase(
            appServerClient: appServerClient,
            identityResolver: self.identityResolver,
            repository: repository
        )
        self.loadAccountsUseCase = loadAccountsUseCase
        self.refreshActiveAccountUseCase = refreshActiveAccountUseCase
        self.silentPostActionRefresh = SilentPostActionRefresh(
            refreshActiveAccountUseCase: refreshActiveAccountUseCase
        )
        self.hydrateSavedAccountsMetadataUseCase = HydrateSavedAccountsMetadataUseCase(
            authService: authService,
            appServerClient: appServerClient,
            identityResolver: self.identityResolver,
            repository: repository
        )
        self.deleteSavedAccountUseCase = DeleteSavedAccountUseCase(
            repository: repository,
            identityResolver: self.identityResolver
        )
        self.renameSavedAccountUseCase = RenameSavedAccountUseCase(repository: repository)
        self.switchAccountWorkflow = SwitchAccountWorkflow(
            authService: authService,
            repository: repository,
            appController: appController,
            identityResolver: self.identityResolver
        )
        self.switchAccountOnHostWorkflow = SwitchAccountOnHostWorkflow(
            remoteHostClient: remoteHostClient
        )
        self.remoteHostAccountVerifier = RemoteHostAccountVerifier()
        self.saveCurrentAccountWorkflow = SaveCurrentAccountWorkflow(
            appServerClient: appServerClient,
            authService: authService,
            repository: repository,
            identityResolver: self.identityResolver
        )
        self.signInAnotherWorkflow = SignInAnotherWorkflow(
            authService: authService,
            appController: appController,
            appServerClient: appServerClient,
            repository: repository,
            identityResolver: self.identityResolver
        )
    }

    init(
        identityResolver: SavedAccountIdentityResolver,
        inactiveAccountAvailabilityRanking: InactiveAccountAvailabilityRanking = InactiveAccountAvailabilityRanking(),
        pendingSignInLifecycle: PendingSignInLifecycle = PendingSignInLifecycle(),
        operationState: AccountOperationState = AccountOperationState(),
        loadAccountsUseCase: LoadAccountsUseCase,
        refreshActiveAccountUseCase: RefreshActiveAccountUseCase,
        silentPostActionRefresh: SilentPostActionRefresh? = nil,
        hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase,
        deleteSavedAccountUseCase: DeleteSavedAccountUseCase,
        renameSavedAccountUseCase: RenameSavedAccountUseCase,
        switchAccountWorkflow: SwitchAccountWorkflow,
        switchAccountOnHostWorkflow: SwitchAccountOnHostWorkflow = SwitchAccountOnHostWorkflow(
            remoteHostClient: UnavailableRemoteHostClient()
        ),
        remoteHostAccountVerifier: RemoteHostAccountVerifier = RemoteHostAccountVerifier(),
        saveCurrentAccountWorkflow: SaveCurrentAccountWorkflow,
        signInAnotherWorkflow: SignInAnotherWorkflow
    ) {
        self.identityResolver = identityResolver
        self.inactiveAccountAvailabilityRanking = inactiveAccountAvailabilityRanking
        self.pendingSignInLifecycle = pendingSignInLifecycle
        self.operationState = operationState
        self.loadAccountsUseCase = loadAccountsUseCase
        self.refreshActiveAccountUseCase = refreshActiveAccountUseCase
        self.silentPostActionRefresh = silentPostActionRefresh ?? SilentPostActionRefresh(
            refreshActiveAccountUseCase: refreshActiveAccountUseCase
        )
        self.hydrateSavedAccountsMetadataUseCase = hydrateSavedAccountsMetadataUseCase
        self.deleteSavedAccountUseCase = deleteSavedAccountUseCase
        self.renameSavedAccountUseCase = renameSavedAccountUseCase
        self.switchAccountWorkflow = switchAccountWorkflow
        self.switchAccountOnHostWorkflow = switchAccountOnHostWorkflow
        self.remoteHostAccountVerifier = remoteHostAccountVerifier
        self.saveCurrentAccountWorkflow = saveCurrentAccountWorkflow
        self.signInAnotherWorkflow = signInAnotherWorkflow
    }

    func load() {
        do {
            let result = try loadAccountsUseCase.run()
            catalogState.applyLoad(result)
            operationState.setIdleStatus("Loaded \(accounts.count) account(s)")
            accountsControllerLogger.log("Loaded \(self.accounts.count, privacy: .public) saved account(s)")
        } catch {
            operationState.fail(error)
            accountsControllerLogger.error("Failed to load store: \(error.localizedDescription, privacy: .public)")
        }
    }

    func saveCurrentAccountSnapshot(named customName: String?) async {
        await perform("Saving current Codex auth...") {
            let result = try await saveCurrentAccountWorkflow.run(
                customName: customName,
                existingAccounts: accounts
            )
            catalogState.applySavedAccount(
                result.savedAccount,
                activeAccountID: result.activeAccountID
            )
            await applySilentPostActionRefresh(after: .zero)
        }
    }

    func completePendingSignedInAccountIfNeeded() async {
        switch pendingSignInLifecycle.beginCompletion(activeAccountID: activeAccountID) {
        case .skip, .clearPending:
            return
        case .complete(let pendingAccountName):
            await perform("Saving signed-in account...") {
                guard let result = try await signInAnotherWorkflow.completePendingSignIn(
                    pendingAccountName: pendingAccountName,
                    existingAccounts: accounts
                ) else {
                    pendingSignInLifecycle.finishCompletion(consumedPendingSignIn: false)
                    return
                }

                catalogState.applySavedAccount(
                    result.savedAccount,
                    activeAccountID: result.activeAccountID
                )
                pendingSignInLifecycle.finishCompletion(consumedPendingSignIn: true)
                await applySilentPostActionRefresh(after: .seconds(2))
            }
            if pendingSignInLifecycle.isCompleting {
                pendingSignInLifecycle.finishCompletion(consumedPendingSignIn: false)
            }
        }
    }

    func switchToAccount(_ account: CodexAccount) async {
        await perform("Switching to \(account.name)...") {
            catalogState.setActiveAccountID(
                try await switchAccountWorkflow.run(
                    account: account,
                    accounts: accounts
                )
            )
            await applySilentPostActionRefresh(after: .seconds(2))
        }
    }

    func switchToAccountOnHost(_ account: CodexAccount, on host: RemoteHost) async -> RemoteHostSwitchOutcome {
        operationState.begin(status: "Switching \(account.name) on \(host.displayName)...")
        do {
            let result = try await switchAccountOnHostWorkflow.run(
                account: account,
                on: host,
                among: accounts
            )
            switch result {
            case .verified(let status):
                operationState.succeed()
                return .verified(status)
            case .notVerified(let matchOutcome):
                let error = RemoteHostSwitchVerificationError(
                    message: remoteHostAccountVerifier.failureMessage(
                        for: account,
                        on: host,
                        among: accounts,
                        matchOutcome: matchOutcome
                    )
                )
                operationState.fail(error)
                return .notVerified(
                    error.localizedDescription,
                    detectedAccountID: matchOutcome.matchedAccountID
                )
            }
        } catch {
            operationState.fail(error)
            return .failed(
                error.localizedDescription,
                hostReachable: isReachableRemoteVerificationFailure(error)
            )
        }
    }

    func testRemoteHostConnection(_ host: RemoteHost) async -> Bool {
        operationState.begin(status: "Testing \(host.displayName)...")
        do {
            try await switchAccountOnHostWorkflow.testConnection(to: host)
            operationState.succeed()
            return true
        } catch {
            operationState.fail(error)
            return false
        }
    }

    func removeSavedAccount(_ account: CodexAccount) async {
        await perform("Removing \(account.name)...") {
            let result = try deleteSavedAccountUseCase.run(account: account, accounts: accounts)
            catalogState.applyDeleted(result)
        }
    }

    func renameSavedAccount(_ account: CodexAccount, to newName: String) async {
        await perform("Renaming \(account.name)...") {
            let result = try renameSavedAccountUseCase.run(
                account: account,
                newName: newName,
                accounts: accounts
            )
            catalogState.applyRenamed(result)
        }
    }

    func refreshAccountData(for account: CodexAccount) async -> BackgroundRefreshOutcome {
        do {
            let result = try await refreshActiveAccountUseCase.run(accounts: accounts)
            catalogState.applyRefreshed(result)
            accountsControllerLogger.log("Background refresh completed for \(account.name, privacy: .public)")
            return .refreshed
        } catch {
            accountsControllerLogger.log("Background refresh skipped for \(account.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    func startSignInAnotherAccountFlow(named pendingAccountName: String?) async {
        accountsControllerLogger.log("Starting sign-in-another flow")
        await perform("Preparing Codex sign-in...") {
            let result = try signInAnotherWorkflow.prepare(named: pendingAccountName)
            pendingSignInLifecycle.recordPreparedSignIn(named: result.pendingAccountName)
            catalogState.setActiveAccountID(nil)
            try await signInAnotherWorkflow.relaunchCodex()
            accountsControllerLogger.log("Sign-in-another relaunch finished")
        }
    }

    var accounts: [CodexAccount] {
        catalogState.accounts
    }

    var activeAccountID: UUID? {
        catalogState.activeAccountID
    }

    var pendingErrorMessage: String? {
        operationState.pendingErrorMessage
    }

    var statusMessage: String {
        operationState.statusMessage
    }

    var isBusy: Bool {
        operationState.isBusy
    }

    func refreshActiveAccount() {
        catalogState.resolveActiveAccountID(using: identityResolver)
    }

    func hydrateSavedAccountsMetadataIfNeeded() async {
        guard pendingSignInLifecycle.canHydrateSavedAccountsMetadata(
            isBusy: isBusy,
            isHydratingSavedAccountsMetadata: isHydratingSavedAccountsMetadata
        ) else { return }
        guard accounts.contains(where: { $0.id != activeAccountID && $0.rateLimits == nil }) else { return }

        isHydratingSavedAccountsMetadata = true
        defer { isHydratingSavedAccountsMetadata = false }

        do {
            let result = try await hydrateSavedAccountsMetadataUseCase.run(
                accounts: accounts,
                activeAccountID: activeAccountID
            )
            catalogState.applyHydrated(result)
        } catch {
            accountsControllerLogger.log("Saved account metadata hydration skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    func isActive(_ account: CodexAccount) -> Bool {
        activeAccountID == account.id
    }

    var activeAccount: CodexAccount? {
        catalogState.activeAccount
    }

    var inactiveAccounts: [CodexAccount] {
        catalogState.inactiveAccounts
    }

    var sortedInactiveAccounts: [CodexAccount] {
        inactiveAccountAvailabilityRanking.sort(inactiveAccounts)
    }

    func compareForMenu(_ lhs: CodexAccount, _ rhs: CodexAccount) -> Bool {
        if lhs.id == activeAccountID, rhs.id != activeAccountID {
            return true
        }

        if rhs.id == activeAccountID, lhs.id != activeAccountID {
            return false
        }

        return inactiveAccountAvailabilityRanking.compare(lhs, rhs)
    }

    var hasPendingSignedInAccount: Bool {
        pendingSignInLifecycle.hasPendingSignIn
    }

    func consumePendingErrorMessage() -> String? {
        operationState.consumePendingErrorMessage()
    }

    private func perform(_ status: String, operation: () async throws -> Void) async {
        accountsControllerLogger.log("Beginning operation with status: \(status, privacy: .public)")
        operationState.begin(status: status)
        do {
            try await operation()
            operationState.succeed()
            accountsControllerLogger.log("Operation completed successfully for status: \(status, privacy: .public)")
        } catch {
            operationState.fail(error)
            accountsControllerLogger.error("Operation failed for status \(status, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applySilentPostActionRefresh(after delay: Duration) async {
        if let result = await silentPostActionRefresh.run(
            after: delay,
            activeAccountID: activeAccountID,
            accounts: accounts
        ) {
            catalogState.applyRefreshed(result)
        }
    }

}

private struct RemoteHostSwitchVerificationError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

private func isReachableRemoteVerificationFailure(_ error: Error) -> Bool {
    guard let clientError = error as? RemoteHostClientError else { return false }
    if case .authReadFailed = clientError {
        return true
    }
    return false
}
