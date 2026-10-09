import AppKit
import Foundation

@MainActor
protocol MenuBarHostActionAccountsStore: AnyObject {
    var accounts: [CodexAccount] { get }
    var activeAccount: CodexAccount? { get }

    func switchToAccountOnHost(_ account: CodexAccount, on host: RemoteHost) async -> AccountsController.RemoteHostSwitchOutcome
}

@MainActor
final class MenuBarHostActionCoordinator {
    private let store: MenuBarHostActionAccountsStore
    private let settings: RemoteHostSettingsStore
    private let connectionChecker: RemoteHostConnectionChecking
    private let remoteHostRuntime: RemoteHostRuntime
    private let alertPresenter: AlertPresenter
    private let panelPresenter: PanelPresenter
    private let alertFactory: MenuBarAlertFactory
    private let recordMenuAction: (String) -> Void
    private let rebuildMenu: () -> Void
    private let cancelMenuTracking: () -> Void

    init(
        store: MenuBarHostActionAccountsStore,
        settings: RemoteHostSettingsStore,
        connectionChecker: RemoteHostConnectionChecking,
        remoteHostRuntime: RemoteHostRuntime,
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter,
        alertFactory: MenuBarAlertFactory,
        recordMenuAction: @escaping (String) -> Void,
        rebuildMenu: @escaping () -> Void,
        cancelMenuTracking: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.connectionChecker = connectionChecker
        self.remoteHostRuntime = remoteHostRuntime
        self.alertPresenter = alertPresenter
        self.panelPresenter = panelPresenter
        self.alertFactory = alertFactory
        self.recordMenuAction = recordMenuAction
        self.rebuildMenu = rebuildMenu
        self.cancelMenuTracking = cancelMenuTracking
    }

    func switchAccountOnHost(accountID: UUID, hostDestination: String) async {
        guard
            let remoteHost = settings.remoteHostState(for: hostDestination)?.host,
            let account = store.accounts.first(where: { $0.id == accountID })
        else {
            return
        }

        recordMenuAction("switchAccountOnHost")
        remoteHostRuntime.beginHostSwitch(to: account, on: remoteHost)
        rebuildMenu()
        let result = await store.switchToAccountOnHost(account, on: remoteHost)
        remoteHostRuntime.applySwitchOutcome(result, account: account, host: remoteHost)
        rebuildMenu()
    }

    func addHost() async {
        recordMenuAction("addHost")
        guard let remoteHost = await panelPresenter.presentHostSetup(
            alertFactory.makeAddHostRequest(),
            testConnection: { [weak self] host in
                guard let self else {
                    return .failure(RemoteHostClientError.unavailable)
                }
                do {
                    try await self.connectionChecker.testConnection(to: host)
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }
        ) else {
            return
        }

        await installActiveAccountOnNewHost(remoteHost)
    }

    func removeHost(hostDestination: String) {
        guard let hostState = settings.remoteHostState(for: hostDestination) else { return }
        let remoteHost = hostState.host
        recordMenuAction("removeHost")
        guard alertPresenter.presentConfirmation(alertFactory.makeRemoveHostRequest(hostName: remoteHost.displayName)) else {
            return
        }

        remoteHostRuntime.removeHost(hostState)
        rebuildMenu()
    }

    func reverifyHost(hostDestination: String) async {
        guard let hostState = settings.remoteHostState(for: hostDestination) else { return }
        await reverifyHost(hostState: hostState)
    }

    func adoptDetectedRemoteAccount(hostDestination: String, accountID: UUID) async {
        guard let hostState = settings.remoteHostState(for: hostDestination) else { return }
        await adoptDetectedRemoteAccount(hostState: hostState, accountID: accountID)
    }

    private func reverifyHost(hostState: PersistedRemoteHostState) async {
        guard let baseAccount = remoteHostRuntime.beginReverification(hostState: hostState) else { return }
        cancelMenuTracking()

        recordMenuAction("reverifyHost")
        rebuildMenu()

        await remoteHostRuntime.refresh(
            host: hostState.host,
            baseAccount: baseAccount,
            fallbackConnectionState: .disconnected
        )
        rebuildMenu()
    }

    private func adoptDetectedRemoteAccount(hostState: PersistedRemoteHostState, accountID: UUID) async {
        guard let detectedAccount = remoteHostRuntime.beginAdoptingDetectedAccount(
            hostState: hostState,
            accountID: accountID
        ) else {
            return
        }
        cancelMenuTracking()

        recordMenuAction("adoptDetectedRemoteAccount")
        rebuildMenu()

        await remoteHostRuntime.refresh(
            host: hostState.host,
            baseAccount: detectedAccount,
            fallbackConnectionState: .connected
        )
        rebuildMenu()
    }

    private func installActiveAccountOnNewHost(_ remoteHost: RemoteHost) async {
        guard let activeAccount = store.activeAccount else {
            rebuildMenu()
            return
        }

        let shouldInstallCurrentAccount = alertPresenter.presentConfirmation(
            alertFactory.makeInstallCurrentAccountOnHostRequest(
                accountName: activeAccount.name,
                hostName: remoteHost.displayName
            )
        )

        guard shouldInstallCurrentAccount else {
            rebuildMenu()
            return
        }

        settings.updateRemoteHostState(for: remoteHost) { state in
            state.desiredAccountID = activeAccount.id
            state.verificationStatus = .verifying
            state.lastVerificationError = nil
        }
        remoteHostRuntime.beginHostSwitch(to: activeAccount, on: remoteHost)
        rebuildMenu()
        let result = await store.switchToAccountOnHost(activeAccount, on: remoteHost)
        remoteHostRuntime.applySwitchOutcome(
            result,
            account: activeAccount,
            host: remoteHost,
            recordsInstalledAccountOnFailure: true
        )
        rebuildMenu()
    }
}
