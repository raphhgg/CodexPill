import Foundation
import Observation

@MainActor
@Observable
final class MenuBarAccountsStore {
    private let controller: AccountsController

    init(controller: AccountsController) {
        self.controller = controller
    }

    var accounts: [CodexAccount] { controller.accounts }
    var activeAccountID: UUID? { controller.activeAccountID }
    var pendingErrorMessage: String? { controller.pendingErrorMessage }
    var statusMessage: String { controller.statusMessage }
    var isBusy: Bool { controller.isBusy }
    var activeAccount: CodexAccount? { controller.activeAccount }
    var inactiveAccounts: [CodexAccount] { controller.inactiveAccounts }
    var sortedInactiveAccounts: [CodexAccount] { controller.sortedInactiveAccounts }
    func load() {
        controller.load()
    }

    func switchToAccount(_ account: CodexAccount) async -> Bool {
        await controller.switchToAccount(account)
    }

    func switchToAccountOnHost(_ account: CodexAccount, on host: RemoteHost) async -> AccountsController.RemoteHostSwitchOutcome {
        await controller.switchToAccountOnHost(account, on: host)
    }

    func testRemoteHostConnection(_ host: RemoteHost) async -> Bool {
        await controller.testRemoteHostConnection(host)
    }

    func removeSavedAccount(_ account: CodexAccount, signOutLocalAccount: Bool = false) async {
        await controller.removeSavedAccount(account, signOutLocalAccount: signOutLocalAccount)
    }

    func renameSavedAccount(_ account: CodexAccount, to newName: String) async {
        await controller.renameSavedAccount(account, to: newName)
    }

    func refreshAccountData(for account: CodexAccount) async -> AccountsController.BackgroundRefreshOutcome {
        await controller.refreshAccountData(for: account)
    }

    func persistAccountMetadata(_ account: CodexAccount) {
        controller.persistAccountMetadata(account)
    }

    func startIsolatedAddAccountFlow(named pendingAccountName: String?) async throws -> IsolatedAddAccountSignInSession {
        try await controller.startIsolatedAddAccountFlow(named: pendingAccountName)
    }

    func completeIsolatedAddAccount(_ session: IsolatedAddAccountSignInSession) async throws -> CodexAccount {
        try await controller.completeIsolatedAddAccount(session)
    }

    func cancelIsolatedAddAccount(_ session: IsolatedAddAccountSignInSession) {
        controller.cancelIsolatedAddAccount(session)
    }

    func refreshActiveAccount() {
        controller.refreshActiveAccount()
    }

    func hydrateSavedAccountsMetadataIfNeeded() async {
        await controller.hydrateSavedAccountsMetadataIfNeeded()
    }

    func refreshInactiveSavedAccountsMetadata() async {
        await controller.refreshInactiveSavedAccountsMetadata()
    }

    func consumePendingErrorMessage() -> String? {
        controller.consumePendingErrorMessage()
    }
}
