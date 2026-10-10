import Foundation
import Observation
import OSLog

private let accountsControllerLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "AccountsController")

@MainActor
@Observable
final class AccountsController {
    enum BackgroundRefreshOutcome: Equatable {
        case refreshed
        case failed(String)
    }

    private static let inactiveSavedAccountsRefreshInterval: TimeInterval = 15 * 60

    private let identityResolver: SavedAccountIdentityResolver
    private let inactiveAccountAvailabilityRanking: InactiveAccountAvailabilityRanking
    private let operationState: AccountOperationState
    private let loadAccountsUseCase: LoadAccountsUseCase
    private let refreshActiveAccountUseCase: RefreshActiveAccountUseCase
    private let hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase
    private let deleteSavedAccountUseCase: DeleteSavedAccountUseCase
    private let renameSavedAccountUseCase: RenameSavedAccountUseCase
    private let accountCatalogStore: AccountCatalogStore
    private let switchAccountWorkflow: SwitchAccountWorkflow
    private let addAccountWorkflow: AddAccountWorkflow
    private let now: () -> Date
    private let postSwitchRefreshDelay: Duration

    private var catalogState = AccountCatalogState()
    private var isHydratingSavedAccountsMetadata = false
    private var lastInactiveSavedAccountsRefreshAt: Date?

    init(
        identityResolver: SavedAccountIdentityResolver,
        inactiveAccountAvailabilityRanking: InactiveAccountAvailabilityRanking = InactiveAccountAvailabilityRanking(),
        operationState: AccountOperationState = AccountOperationState(),
        loadAccountsUseCase: LoadAccountsUseCase,
        refreshActiveAccountUseCase: RefreshActiveAccountUseCase,
        hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase,
        deleteSavedAccountUseCase: DeleteSavedAccountUseCase,
        renameSavedAccountUseCase: RenameSavedAccountUseCase,
        accountCatalogStore: AccountCatalogStore,
        switchAccountWorkflow: SwitchAccountWorkflow,
        addAccountWorkflow: AddAccountWorkflow,
        now: @escaping () -> Date = Date.init,
        postSwitchRefreshDelay: Duration = .seconds(2)
    ) {
        self.identityResolver = identityResolver
        self.inactiveAccountAvailabilityRanking = inactiveAccountAvailabilityRanking
        self.operationState = operationState
        self.loadAccountsUseCase = loadAccountsUseCase
        self.refreshActiveAccountUseCase = refreshActiveAccountUseCase
        self.hydrateSavedAccountsMetadataUseCase = hydrateSavedAccountsMetadataUseCase
        self.deleteSavedAccountUseCase = deleteSavedAccountUseCase
        self.renameSavedAccountUseCase = renameSavedAccountUseCase
        self.accountCatalogStore = accountCatalogStore
        self.switchAccountWorkflow = switchAccountWorkflow
        self.addAccountWorkflow = addAccountWorkflow
        self.now = now
        self.postSwitchRefreshDelay = postSwitchRefreshDelay
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

    func switchToAccount(_ account: CodexAccount) async -> Bool {
        var didRefreshAfterSwitch = false
        await perform("Switching to \(account.name)...") {
            catalogState.setActiveAccountID(
                try await switchAccountWorkflow.run(
                    account: account,
                    accounts: accounts
                )
            )
            didRefreshAfterSwitch = await applySilentPostActionRefresh(after: postSwitchRefreshDelay)
        }
        return didRefreshAfterSwitch
    }

    func removeSavedAccount(_ account: CodexAccount, signOutLocalAccount: Bool = false) async {
        await perform("Removing \(account.name)...") {
            let result = try await deleteSavedAccountUseCase.run(
                account: account,
                accounts: accounts,
                signOutLocalAccount: signOutLocalAccount
            )
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
            return .failed(error.localizedDescription)
        }
    }

    func persistAccountMetadata(_ account: CodexAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }

        var updatedAccounts = accounts
        updatedAccounts[index] = account
        do {
            try accountCatalogStore.saveAccounts(updatedAccounts)
            catalogState.applyPersistedMetadata(updatedAccounts)
        } catch {
            accountsControllerLogger.log("Persisted metadata update skipped for \(account.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func startIsolatedAddAccountFlow(named pendingAccountName: String?) async throws -> IsolatedAddAccountSignInSession {
        guard !isBusy else {
            throw AccountsControllerError.operationAlreadyInProgress
        }
        accountsControllerLogger.log("Starting isolated add-account flow")
        operationState.begin(status: "Adding account...")
        do {
            let session = try await addAccountWorkflow.startIsolatedAddAccount(
                named: pendingAccountName,
                existingAccounts: accounts
            )
            return session
        } catch {
            operationState.fail(error)
            throw error
        }
    }

    func completeIsolatedAddAccount(_ session: IsolatedAddAccountSignInSession) async throws -> CodexAccount {
        do {
            let result = try await addAccountWorkflow.completeIsolatedAddAccount(
                session,
                existingAccounts: accounts,
                activeAccountID: activeAccountID
            )
            catalogState.applySavedAccount(
                result.savedAccount,
                activeAccountID: result.activeAccountID
            )
            await hydrateSavedAccountsMetadataAfterAddingAccount()
            operationState.succeed()
            return result.savedAccount
        } catch {
            if let workflowError = error as? AddAccountWorkflowError,
               case .accountAlreadySaved = workflowError {
                operationState.succeed()
            } else {
                operationState.fail(error)
            }
            throw error
        }
    }

    func cancelIsolatedAddAccount(_ session: IsolatedAddAccountSignInSession) {
        addAccountWorkflow.cancelIsolatedAddAccount(session)
        operationState.succeed()
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
        guard !isBusy, !isHydratingSavedAccountsMetadata else { return }
        guard accounts.contains(where: { $0.id != activeAccountID && $0.usage == nil }) else { return }

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

    func refreshInactiveSavedAccountsMetadata() async {
        guard !isBusy, !isHydratingSavedAccountsMetadata else { return }
        let startedAt = now()
        if let lastInactiveSavedAccountsRefreshAt,
           startedAt.timeIntervalSince(lastInactiveSavedAccountsRefreshAt) < Self.inactiveSavedAccountsRefreshInterval {
            return
        }

        lastInactiveSavedAccountsRefreshAt = startedAt
        isHydratingSavedAccountsMetadata = true
        defer { isHydratingSavedAccountsMetadata = false }

        do {
            let result = try await hydrateSavedAccountsMetadataUseCase.run(
                accounts: accounts,
                activeAccountID: activeAccountID,
                refreshExistingMetadata: true
            )
            catalogState.applyHydrated(result)
        } catch {
            accountsControllerLogger.log("Saved account metadata refresh skipped: \(error.localizedDescription, privacy: .public)")
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

    private func applySilentPostActionRefresh(after delay: Duration) async -> Bool {
        guard activeAccountID != nil else { return false }
        let accountsBeforeDelay = accounts

        if delay > .zero {
            try? await Task.sleep(for: delay)
        }

        do {
            catalogState.applyRefreshed(try await refreshActiveAccountUseCase.run(accounts: accountsBeforeDelay))
            return true
        } catch {
            accountsControllerLogger.log("Silent post-action refresh skipped: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func hydrateSavedAccountsMetadataAfterAddingAccount() async {
        guard !isHydratingSavedAccountsMetadata else { return }
        guard accounts.contains(where: { $0.id != activeAccountID && $0.usage == nil }) else { return }

        isHydratingSavedAccountsMetadata = true
        defer { isHydratingSavedAccountsMetadata = false }

        do {
            let result = try await hydrateSavedAccountsMetadataUseCase.run(
                accounts: accounts,
                activeAccountID: activeAccountID
            )
            catalogState.applyHydrated(result)
        } catch {
            accountsControllerLogger.log("Post-add saved account metadata hydration skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

}

enum AccountsControllerError: LocalizedError, Equatable {
    case operationAlreadyInProgress

    var errorDescription: String? {
        switch self {
        case .operationAlreadyInProgress:
            "Another account operation is already in progress."
        }
    }
}
