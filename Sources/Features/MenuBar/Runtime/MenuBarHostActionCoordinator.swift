import AppKit
import Foundation

@MainActor
protocol MenuBarHostActionAccountsStore: AnyObject {
    var accounts: [CodexAccount] { get }
    var activeAccount: CodexAccount? { get }

    func switchToAccountOnHost(_ account: CodexAccount, on host: RemoteHost) async -> AccountsController.RemoteHostSwitchOutcome
}

extension MenuBarAccountsStore: MenuBarHostActionAccountsStore {}

@MainActor
final class MenuBarHostActionCoordinator {
    private let store: MenuBarHostActionAccountsStore
    private let settings: CodexPillSettingsStore
    private let remoteHostClient: RemoteHostClient
    private let remoteHostRuntime: RemoteHostRuntime
    private let alertPresenter: AlertPresenter
    private let panelPresenter: PanelPresenter
    private let alertFactory: MenuBarAlertFactory
    private let validationObserver: MenuBarValidationObserver
    private let recordMenuAction: (String, [String: String]) -> Void
    private let rebuildMenu: () -> Void
    private let cancelMenuTracking: () -> Void

    init(
        store: MenuBarHostActionAccountsStore,
        settings: CodexPillSettingsStore,
        remoteHostClient: RemoteHostClient,
        remoteHostRuntime: RemoteHostRuntime,
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter,
        alertFactory: MenuBarAlertFactory,
        validationObserver: MenuBarValidationObserver,
        recordMenuAction: @escaping (String, [String: String]) -> Void,
        rebuildMenu: @escaping () -> Void,
        cancelMenuTracking: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.remoteHostClient = remoteHostClient
        self.remoteHostRuntime = remoteHostRuntime
        self.alertPresenter = alertPresenter
        self.panelPresenter = panelPresenter
        self.alertFactory = alertFactory
        self.validationObserver = validationObserver
        self.recordMenuAction = recordMenuAction
        self.rebuildMenu = rebuildMenu
        self.cancelMenuTracking = cancelMenuTracking
    }

    func switchAccountOnHost(accountID: UUID, hostDestination: String) {
        guard
            let remoteHost = settings.remoteHostState(for: hostDestination)?.host,
            let account = store.accounts.first(where: { $0.id == accountID })
        else {
            return
        }

        recordMenuAction("switchAccountOnHost", [
            "targetName": account.name,
            "hostName": remoteHost.displayName
        ])
        validationObserver.recordRemoteHostSwitchMenuAction(
            targetName: account.name,
            hostName: remoteHost.displayName
        )
        remoteHostRuntime.beginHostSwitch(to: account, on: remoteHost)
        rebuildMenu()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.store.switchToAccountOnHost(account, on: remoteHost)
            self.remoteHostRuntime.applySwitchOutcome(result, account: account, host: remoteHost)
            self.recordSwitchResult(result, account: account, host: remoteHost)
            self.rebuildMenu()
        }
    }

    func addHost() {
        recordMenuAction("addHost", [:])
        validationObserver.recordAddHostMenuAction()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let remoteHost = await self.panelPresenter.presentHostSetup(
                self.alertFactory.makeAddHostRequest(),
                testConnection: { [weak self] host in
                    guard let self else {
                        return .failure(RemoteHostClientError.unavailable)
                    }
                    do {
                        try await self.remoteHostClient.testConnection(to: host)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                },
                onPresented: { [weak self] in
                    self?.validationObserver.recordAddHostSetupPresented()
                },
                onCancelled: { [weak self] in
                    self?.validationObserver.recordAddHostSetupCancelled()
                },
                onValidationStarted: { [weak self] host in
                    self?.validationObserver.recordAddHostValidationStarted(host: host)
                },
                onValidationFinished: { [weak self] host, result in
                    self?.validationObserver.recordAddHostValidationFinished(host: host, result: result)
                }
            ) else {
                return
            }

            await self.installActiveAccountOnNewHost(remoteHost)
        }
    }

    func removeHost(hostDestination: String) {
        guard let hostState = settings.remoteHostState(for: hostDestination) else { return }
        let remoteHost = hostState.host
        recordMenuAction("removeHost", ["hostName": remoteHost.displayName])
        guard alertPresenter.presentConfirmation(alertFactory.makeRemoveHostRequest(hostName: remoteHost.displayName)) else {
            return
        }

        remoteHostRuntime.removeHost(hostState)
        rebuildMenu()
    }

    func reverifyHost(hostDestination: String) {
        guard let hostState = settings.remoteHostState(for: hostDestination) else { return }
        reverifyHost(hostState: hostState)
    }

    func adoptDetectedRemoteAccount(hostDestination: String, accountID: UUID) {
        guard let hostState = settings.remoteHostState(for: hostDestination) else { return }
        adoptDetectedRemoteAccount(hostState: hostState, accountID: accountID)
    }

    private func reverifyHost(hostState: PersistedRemoteHostState) {
        guard let baseAccount = remoteHostRuntime.beginReverification(hostState: hostState) else { return }
        cancelMenuTracking()

        recordMenuAction("reverifyHost", [
            "hostName": hostState.host.displayName,
            "accountName": baseAccount.name
        ])
        validationObserver.recordRemoteHostReverifyStarted(
            hostName: hostState.host.displayName,
            accountName: baseAccount.name
        )

        rebuildMenu()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.remoteHostRuntime.refresh(
                host: hostState.host,
                baseAccount: baseAccount,
                fallbackConnectionState: .disconnected
            )

            let refreshedState = self.settings.remoteHostState(for: hostState.host.destination)
            self.validationObserver.recordRemoteHostReverifyResult(
                succeeded: refreshedState?.verificationStatus == .verified,
                hostName: hostState.host.displayName,
                accountName: baseAccount.name
            )
            self.rebuildMenu()
        }
    }

    private func adoptDetectedRemoteAccount(hostState: PersistedRemoteHostState, accountID: UUID) {
        guard let detectedAccount = remoteHostRuntime.beginAdoptingDetectedAccount(
            hostState: hostState,
            accountID: accountID
        ) else {
            return
        }
        cancelMenuTracking()

        recordMenuAction("adoptDetectedRemoteAccount", [
            "hostName": hostState.host.displayName,
            "accountName": detectedAccount.name
        ])
        rebuildMenu()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.remoteHostRuntime.refresh(
                host: hostState.host,
                baseAccount: detectedAccount,
                fallbackConnectionState: .connected
            )
            self.rebuildMenu()
        }
    }

    private func installActiveAccountOnNewHost(_ remoteHost: RemoteHost) async {
        guard let activeAccount = store.activeAccount else {
            validationObserver.recordAddHostAccountSetupUnavailable(
                hostName: remoteHost.displayName
            )
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
            validationObserver.recordAddHostAccountSetupCancelled(
                hostName: remoteHost.displayName
            )
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

    private func recordSwitchResult(
        _ result: AccountsController.RemoteHostSwitchOutcome,
        account: CodexAccount,
        host remoteHost: RemoteHost
    ) {
        validationObserver.recordRemoteHostSwitchResult(result, account: account, host: remoteHost)
    }
}
