import Foundation
import Observation
import OSLog

private let accountsControllerLogger = Logger(subsystem: "com.raphhgg.codex-switchboard", category: "AccountsController")

@MainActor
@Observable
final class AccountsController {
    private let identityResolver: SavedAccountIdentityResolver
    private let loadAccountsUseCase: LoadAccountsUseCase
    private let refreshActiveAccountUseCase: RefreshActiveAccountUseCase
    private let deleteSavedAccountUseCase: DeleteSavedAccountUseCase
    private let renameSavedAccountUseCase: RenameSavedAccountUseCase
    private let switchAccountWorkflow: SwitchAccountWorkflow
    private let saveCurrentAccountWorkflow: SaveCurrentAccountWorkflow
    private let signInAnotherWorkflow: SignInAnotherWorkflow

    private(set) var accounts: [CodexAccount] = []
    private(set) var activeAccountID: UUID?
    private var pendingSignedInAccountName: String?
    private var isCompletingPendingSignedInAccount = false
    private(set) var pendingErrorMessage: String?
    private(set) var statusMessage = "Ready"
    private(set) var isBusy = false
    init(
        repository: AccountRepository,
        authService: CodexAuthSnapshotService,
        appController: CodexAppController,
        appServerClient: CodexAppServerClient
    ) {
        self.identityResolver = SavedAccountIdentityResolver(
            liveIdentityReader: authService,
            storedAccountReconciler: authService
        )
        self.loadAccountsUseCase = LoadAccountsUseCase(
            repository: repository,
            identityResolver: self.identityResolver
        )
        self.refreshActiveAccountUseCase = RefreshActiveAccountUseCase(
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

    func load() {
        do {
            let result = try loadAccountsUseCase.run()
            accounts = result.accounts
            activeAccountID = result.activeAccountID
            statusMessage = "Loaded \(accounts.count) account(s)"
            accountsControllerLogger.log("Loaded \(self.accounts.count, privacy: .public) saved account(s)")
        } catch {
            statusMessage = "Ready"
            pendingErrorMessage = error.localizedDescription
            accountsControllerLogger.error("Failed to load store: \(error.localizedDescription, privacy: .public)")
        }
    }

    func saveCurrentAccountSnapshot(named customName: String?) async {
        await perform("Saving current Codex auth...") {
            let result = try await saveCurrentAccountWorkflow.run(
                customName: customName,
                existingAccounts: accounts
            )
            applySavedAccount(result.savedAccount)
            activeAccountID = result.activeAccountID
            await silentlyRefreshActiveAccountData(after: .zero)
        }
    }

    func completePendingSignedInAccountIfNeeded() async {
        guard let pendingSignedInAccountName else { return }
        guard !isCompletingPendingSignedInAccount else { return }
        guard activeAccountID == nil else {
            self.pendingSignedInAccountName = nil
            return
        }

        isCompletingPendingSignedInAccount = true
        defer { isCompletingPendingSignedInAccount = false }

        await perform("Saving signed-in account...") {
            guard let result = try await signInAnotherWorkflow.completePendingSignIn(
                pendingAccountName: pendingSignedInAccountName,
                existingAccounts: accounts
            ) else {
                return
            }
            applySavedAccount(result.savedAccount)
            activeAccountID = result.activeAccountID
            self.pendingSignedInAccountName = nil
            await silentlyRefreshActiveAccountData(after: .seconds(2))
        }
    }

    func switchToAccount(_ account: CodexAccount) async {
        await perform("Switching to \(account.name)...") {
            activeAccountID = try await switchAccountWorkflow.run(
                account: account,
                accounts: accounts
            )
            await silentlyRefreshActiveAccountData(after: .seconds(2))
        }
    }

    func removeSavedAccount(_ account: CodexAccount) async {
        await perform("Removing \(account.name)...") {
            let result = try deleteSavedAccountUseCase.run(account: account, accounts: accounts)
            accounts = result.accounts
            activeAccountID = result.activeAccountID
        }
    }

    func renameSavedAccount(_ account: CodexAccount, to newName: String) async {
        await perform("Renaming \(account.name)...") {
            let result = try renameSavedAccountUseCase.run(
                account: account,
                newName: newName,
                accounts: accounts
            )
            accounts = result.accounts
        }
    }

    func refreshAccountData(for account: CodexAccount) async {
        await perform("Refreshing account data for \(account.name)...") {
            let result = try await refreshActiveAccountUseCase.run(accounts: accounts)
            accounts = result.accounts
            activeAccountID = result.refreshedAccountID
        }
    }

    func startSignInAnotherAccountFlow(named pendingAccountName: String?) async {
        accountsControllerLogger.log("Starting sign-in-another flow")
        await perform("Preparing Codex sign-in...") {
            let result = try signInAnotherWorkflow.prepare(named: pendingAccountName)
            pendingSignedInAccountName = result.pendingAccountName
            activeAccountID = nil
            try await signInAnotherWorkflow.relaunchCodex()
            accountsControllerLogger.log("Sign-in-another relaunch finished")
        }
    }

    func refreshActiveAccount() {
        activeAccountID = identityResolver.resolveCurrentAccountID(accounts: accounts)
    }

    func isActive(_ account: CodexAccount) -> Bool {
        activeAccountID == account.id
    }

    var activeAccount: CodexAccount? {
        accounts.first(where: { $0.id == activeAccountID })
    }

    var inactiveAccounts: [CodexAccount] {
        accounts.filter { $0.id != activeAccountID }
    }

    var sortedInactiveAccounts: [CodexAccount] {
        inactiveAccounts.sorted(by: compareInactiveAccounts)
    }

    func compareForMenu(_ lhs: CodexAccount, _ rhs: CodexAccount) -> Bool {
        if lhs.id == activeAccountID, rhs.id != activeAccountID {
            return true
        }

        if rhs.id == activeAccountID, lhs.id != activeAccountID {
            return false
        }

        return compareInactiveAccounts(lhs, rhs)
    }

    var hasPendingSignedInAccount: Bool {
        pendingSignedInAccountName != nil
    }

    func consumePendingErrorMessage() -> String? {
        let message = pendingErrorMessage
        pendingErrorMessage = nil
        return message
    }

    private func applySavedAccount(_ account: CodexAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        accounts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func perform(_ status: String, operation: () async throws -> Void) async {
        accountsControllerLogger.log("Beginning operation with status: \(status, privacy: .public)")
        isBusy = true
        statusMessage = status
        do {
            try await operation()
            statusMessage = "Done"
            accountsControllerLogger.log("Operation completed successfully for status: \(status, privacy: .public)")
        } catch {
            statusMessage = "Ready"
            pendingErrorMessage = error.localizedDescription
            accountsControllerLogger.error("Operation failed for status \(status, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        isBusy = false
    }

    private func silentlyRefreshActiveAccountData(after delay: Duration) async {
        guard activeAccountID != nil else { return }

        if delay > .zero {
            try? await Task.sleep(for: delay)
        }

        do {
            let result = try await refreshActiveAccountUseCase.run(accounts: accounts)
            accounts = result.accounts
            activeAccountID = result.refreshedAccountID
        } catch {
            accountsControllerLogger.log("Silent post-activation refresh skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func compareInactiveAccounts(_ lhs: CodexAccount, _ rhs: CodexAccount) -> Bool {
        let leftKey = availabilitySortKey(for: lhs)
        let rightKey = availabilitySortKey(for: rhs)

        if leftKey.weeklyConstraintRank != rightKey.weeklyConstraintRank {
            return leftKey.weeklyConstraintRank < rightKey.weeklyConstraintRank
        }

        if leftKey.sessionReadyRank != rightKey.sessionReadyRank {
            return leftKey.sessionReadyRank < rightKey.sessionReadyRank
        }

        if leftKey.effectiveAvailableAt != rightKey.effectiveAvailableAt {
            return leftKey.effectiveAvailableAt < rightKey.effectiveAvailableAt
        }

        if leftKey.weeklyUsedPercent != rightKey.weeklyUsedPercent {
            return leftKey.weeklyUsedPercent < rightKey.weeklyUsedPercent
        }

        if leftKey.sessionUsedPercent != rightKey.sessionUsedPercent {
            return leftKey.sessionUsedPercent < rightKey.sessionUsedPercent
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func availabilitySortKey(for account: CodexAccount) -> AvailabilitySortKey {
        let now = Date()
        let sessionWindow = account.rateLimits?.primary
        let weeklyWindow = account.rateLimits?.secondary
        let sessionUsedPercent = sessionWindow?.displayedUsedPercent(at: now) ?? 100
        let weeklyUsedPercent = weeklyWindow?.displayedUsedPercent(at: now) ?? 100

        let weeklyConstraintRank: Int
        switch weeklyUsedPercent {
        case ..<85:
            weeklyConstraintRank = 0
        case 85..<95:
            weeklyConstraintRank = 1
        default:
            weeklyConstraintRank = 2
        }

        let sessionReadyRank: Int
        switch sessionUsedPercent {
        case ..<10:
            sessionReadyRank = 0
        case 10..<40:
            sessionReadyRank = 1
        default:
            sessionReadyRank = 2
        }

        let sessionAvailableAt: Date = sessionReadyRank == 0 ? now : (sessionWindow?.resetsAt ?? .distantFuture)
        let weeklyAvailableAt: Date = weeklyConstraintRank < 2 ? now : (weeklyWindow?.resetsAt ?? .distantFuture)

        return AvailabilitySortKey(
            weeklyConstraintRank: weeklyConstraintRank,
            sessionReadyRank: sessionReadyRank,
            effectiveAvailableAt: max(sessionAvailableAt, weeklyAvailableAt),
            weeklyUsedPercent: weeklyUsedPercent,
            sessionUsedPercent: sessionUsedPercent
        )
    }
}

private struct AvailabilitySortKey {
    let weeklyConstraintRank: Int
    let sessionReadyRank: Int
    let effectiveAvailableAt: Date
    let weeklyUsedPercent: Int
    let sessionUsedPercent: Int
}
