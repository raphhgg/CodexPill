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
        appServerClient: CodexAppServerClient,
        remoteHostClient: RemoteHostSwitching = UnavailableRemoteHostClient()
    ) {
        self.controller = AccountsController(
            repository: repository,
            authService: authService,
            appController: appController,
            appServerClient: appServerClient,
            remoteHostClient: remoteHostClient
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
    func load() {
        controller.load()
    }

    func saveCurrentAccountSnapshot(named customName: String?) async {
        await controller.saveCurrentAccountSnapshot(named: customName)
    }

    func switchToAccount(_ account: CodexAccount) async {
        await controller.switchToAccount(account)
    }

    func switchToAccountOnHost(_ account: CodexAccount, on host: RemoteHost) async -> AccountsController.RemoteHostSwitchOutcome {
        await controller.switchToAccountOnHost(account, on: host)
    }

    func testRemoteHostConnection(_ host: RemoteHost) async -> Bool {
        await controller.testRemoteHostConnection(host)
    }

    func removeSavedAccount(_ account: CodexAccount) async {
        await controller.removeSavedAccount(account)
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

    func startAddAccountFlow(
        named accountName: String?,
        presentPrompt: @MainActor (CodexDeviceAuthPrompt) -> Void
    ) async {
        await controller.startAddAccountFlow(
            named: accountName,
            presentPrompt: presentPrompt
        )
    }

    func refreshActiveAccount() {
        controller.refreshActiveAccount()
    }

    func hydrateSavedAccountsMetadataIfNeeded() async {
        await controller.hydrateSavedAccountsMetadataIfNeeded()
    }

    func consumePendingErrorMessage() -> String? {
        controller.consumePendingErrorMessage()
    }
}
