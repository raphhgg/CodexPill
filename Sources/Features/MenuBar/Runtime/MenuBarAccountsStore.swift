import Foundation
import Observation

@MainActor
@Observable
final class MenuBarAccountsStore {
    private let controller: AccountsController

    init(
        repository: AccountRepository,
        authService: CodexAuthSnapshotService,
        appController: CodexAppController,
        appServerClient: CodexAppServerClient
    ) {
        self.controller = AccountsController(
            repository: repository,
            authService: authService,
            appController: appController,
            appServerClient: appServerClient
        )
    }

    var accounts: [CodexAccount] { controller.accounts }
    var activeAccountID: UUID? { controller.activeAccountID }
    var pendingErrorMessage: String? { controller.pendingErrorMessage }
    var statusMessage: String { controller.statusMessage }
    var isBusy: Bool { controller.isBusy }
    var activeAccount: CodexAccount? { controller.activeAccount }
    var inactiveAccounts: [CodexAccount] { controller.inactiveAccounts }
    var sortedInactiveAccounts: [CodexAccount] { controller.sortedInactiveAccounts }
    var hasPendingSignedInAccount: Bool { controller.hasPendingSignedInAccount }

    func load() {
        controller.load()
    }

    func saveCurrentAccountSnapshot(named customName: String?) async {
        await controller.saveCurrentAccountSnapshot(named: customName)
    }

    func completePendingSignedInAccountIfNeeded() async {
        await controller.completePendingSignedInAccountIfNeeded()
    }

    func switchToAccount(_ account: CodexAccount) async {
        await controller.switchToAccount(account)
    }

    func removeSavedAccount(_ account: CodexAccount) async {
        await controller.removeSavedAccount(account)
    }

    func renameSavedAccount(_ account: CodexAccount, to newName: String) async {
        await controller.renameSavedAccount(account, to: newName)
    }

    func refreshAccountData(for account: CodexAccount) async {
        await controller.refreshAccountData(for: account)
    }

    func startSignInAnotherAccountFlow(named pendingAccountName: String?) async {
        await controller.startSignInAnotherAccountFlow(named: pendingAccountName)
    }

    func refreshActiveAccount() {
        controller.refreshActiveAccount()
    }

    func consumePendingErrorMessage() -> String? {
        controller.consumePendingErrorMessage()
    }
}
