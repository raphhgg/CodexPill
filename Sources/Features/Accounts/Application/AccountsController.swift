import Foundation
import Observation
import OSLog

private let accountsControllerLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "AccountsController")

struct PersistSavedAccountMetadataUseCase: Sendable {
    private let repository: AccountCatalogStore

    init(repository: AccountCatalogStore) {
        self.repository = repository
    }

    func run(account: CodexAccount, accounts: [CodexAccount]) throws -> [CodexAccount] {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return accounts
        }

        var updatedAccounts = accounts
        updatedAccounts[index] = account
        try repository.saveAccounts(updatedAccounts)
        return updatedAccounts
    }
}

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
    private let silentPostActionRefresh: SilentPostActionRefresh
    private let operationState: AccountOperationState
    private let loadAccountsUseCase: LoadAccountsUseCase
    private let refreshActiveAccountUseCase: RefreshActiveAccountUseCase
    private let hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase
    private let deleteSavedAccountUseCase: DeleteSavedAccountUseCase
    private let renameSavedAccountUseCase: RenameSavedAccountUseCase
    private let persistSavedAccountMetadataUseCase: PersistSavedAccountMetadataUseCase
    private let switchAccountWorkflow: SwitchAccountWorkflow
    private let addAccountWorkflow: AddAccountWorkflow
    private let now: () -> Date

    private var catalogState = AccountCatalogState()
    private var savedAccountsRefresh: Task<Void, Never>?
    private var isStoppingSavedAccountsRefresh = false
    private var lastInactiveSavedAccountsRefreshAt: Date?

    init(
        identityResolver: SavedAccountIdentityResolver,
        inactiveAccountAvailabilityRanking: InactiveAccountAvailabilityRanking = InactiveAccountAvailabilityRanking(),
        operationState: AccountOperationState = AccountOperationState(),
        loadAccountsUseCase: LoadAccountsUseCase,
        refreshActiveAccountUseCase: RefreshActiveAccountUseCase,
        silentPostActionRefresh: SilentPostActionRefresh? = nil,
        hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase,
        deleteSavedAccountUseCase: DeleteSavedAccountUseCase,
        renameSavedAccountUseCase: RenameSavedAccountUseCase,
        persistSavedAccountMetadataUseCase: PersistSavedAccountMetadataUseCase,
        switchAccountWorkflow: SwitchAccountWorkflow,
        addAccountWorkflow: AddAccountWorkflow,
        now: @escaping () -> Date = Date.init
    ) {
        self.identityResolver = identityResolver
        self.inactiveAccountAvailabilityRanking = inactiveAccountAvailabilityRanking
        self.operationState = operationState
        self.loadAccountsUseCase = loadAccountsUseCase
        self.refreshActiveAccountUseCase = refreshActiveAccountUseCase
        self.silentPostActionRefresh = silentPostActionRefresh ?? SilentPostActionRefresh(
            refreshActiveAccountUseCase: refreshActiveAccountUseCase
        )
        self.hydrateSavedAccountsMetadataUseCase = hydrateSavedAccountsMetadataUseCase
        self.deleteSavedAccountUseCase = deleteSavedAccountUseCase
        self.renameSavedAccountUseCase = renameSavedAccountUseCase
        self.persistSavedAccountMetadataUseCase = persistSavedAccountMetadataUseCase
        self.switchAccountWorkflow = switchAccountWorkflow
        self.addAccountWorkflow = addAccountWorkflow
        self.now = now
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
            try saveRotatedLiveAuth(switchingTo: account)
            catalogState.setActiveAccountID(
                try await switchAccountWorkflow.run(
                    account: account,
                    accounts: accounts
                )
            )
            didRefreshAfterSwitch = await applySilentPostActionRefresh()
        }
        return didRefreshAfterSwitch
    }

    private func saveRotatedLiveAuth(switchingTo account: CodexAccount) throws {
        guard let outgoingAccountID = activeAccountID, outgoingAccountID != account.id else { return }
        if let result = try refreshActiveAccountUseCase.relinkCurrentAuthSnapshotIfNeeded(
            accounts: accounts,
            targetAccountID: outgoingAccountID
        ) {
            try applyRefreshed(result, activeAccountIDBeforeRefresh: activeAccountID)
        }
    }

    // A switch can land while a refresh awaits, so the refresh moves the active ID only if nothing else did.
    private func applyRefreshed(_ result: RefreshActiveAccountResult, activeAccountIDBeforeRefresh: UUID?) throws {
        guard let updatedAccounts = try refreshActiveAccountUseCase.save(result, into: accounts) else { return }
        catalogState.applyPersistedMetadata(updatedAccounts)
        if activeAccountID == activeAccountIDBeforeRefresh {
            catalogState.setActiveAccountID(result.update.accountID)
        }
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
        let activeAccountIDBeforeRefresh = activeAccountID
        do {
            let result = try await refreshActiveAccountUseCase.run(accounts: accounts)
            try applyRefreshed(result, activeAccountIDBeforeRefresh: activeAccountIDBeforeRefresh)
            accountsControllerLogger.log("Background refresh completed for \(account.name, privacy: .public)")
            return .refreshed
        } catch {
            accountsControllerLogger.log("Background refresh skipped for \(account.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    func persistAccountMetadata(_ account: CodexAccount) {
        do {
            let result = try persistSavedAccountMetadataUseCase.run(
                account: account,
                accounts: accounts
            )
            catalogState.applyPersistedMetadata(result)
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
        await finishSavedAccountsRefresh()
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
            await refreshSavedAccountsMetadata(refreshExistingMetadata: false)
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
        guard accounts.contains(where: { $0.id != activeAccountID && $0.rateLimits == nil }) else { return }
        await runSavedAccountsRefresh(refreshExistingMetadata: false)
    }

    func refreshInactiveSavedAccountsMetadata() async {
        guard canStartSavedAccountsRefresh else { return }
        let startedAt = now()
        if let lastInactiveSavedAccountsRefreshAt,
           startedAt.timeIntervalSince(lastInactiveSavedAccountsRefreshAt) < Self.inactiveSavedAccountsRefreshInterval {
            return
        }

        lastInactiveSavedAccountsRefreshAt = startedAt
        await runSavedAccountsRefresh(refreshExistingMetadata: true)
    }

    private var canStartSavedAccountsRefresh: Bool {
        !isBusy && savedAccountsRefresh == nil
    }

    private func runSavedAccountsRefresh(refreshExistingMetadata: Bool) async {
        guard canStartSavedAccountsRefresh else { return }
        let refresh = Task {
            await refreshSavedAccountsMetadata(refreshExistingMetadata: refreshExistingMetadata)
        }
        savedAccountsRefresh = refresh
        await refresh.value
        savedAccountsRefresh = nil
    }

    // Lets the account being read finish, so a rotated token is saved before the operation touches auth.
    private func finishSavedAccountsRefresh() async {
        guard let savedAccountsRefresh else { return }
        isStoppingSavedAccountsRefresh = true
        await savedAccountsRefresh.value
        isStoppingSavedAccountsRefresh = false
    }

    private func refreshSavedAccountsMetadata(refreshExistingMetadata: Bool) async {
        let accountIDs = hydrateSavedAccountsMetadataUseCase.accountIDsToRefresh(
            in: accounts,
            activeAccountID: activeAccountID,
            refreshExistingMetadata: refreshExistingMetadata
        )
        for accountID in accountIDs {
            guard !isStoppingSavedAccountsRefresh else { return }
            guard accountID != activeAccountID,
                  let account = accounts.first(where: { $0.id == accountID }),
                  let update = await hydrateSavedAccountsMetadataUseCase.refresh(account, among: accounts)
            else { continue }

            do {
                if let updatedAccounts = try hydrateSavedAccountsMetadataUseCase.save(update, into: accounts) {
                    catalogState.applyPersistedMetadata(updatedAccounts)
                }
            } catch {
                accountsControllerLogger.log("Saved account metadata refresh skipped: \(error.localizedDescription, privacy: .public)")
            }
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
        await finishSavedAccountsRefresh()
        do {
            try await operation()
            operationState.succeed()
            accountsControllerLogger.log("Operation completed successfully for status: \(status, privacy: .public)")
        } catch {
            operationState.fail(error)
            accountsControllerLogger.error("Operation failed for status \(status, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applySilentPostActionRefresh() async -> Bool {
        let activeAccountIDBeforeRefresh = activeAccountID
        if let result = await silentPostActionRefresh.run(
            activeAccountID: activeAccountIDBeforeRefresh,
            accounts: accounts
        ) {
            do {
                try applyRefreshed(result, activeAccountIDBeforeRefresh: activeAccountIDBeforeRefresh)
                return true
            } catch {
                accountsControllerLogger.log("Silent post-action refresh save skipped: \(error.localizedDescription, privacy: .public)")
            }
        }
        return false
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
