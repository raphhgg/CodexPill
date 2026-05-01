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
    private static let addHostPromptInvariantIDs = ["hosts.add_host.destination_validation_failed"]
    private static let remoteHostSwitchInvariantIDs = ["hosts.switch_account_on_host.changes_remote_active_account"]
    private static let remoteHostReverifyInvariantIDs = ["hosts.reverify_remote_account.refreshes_remote_verification_state"]

    private let store: MenuBarHostActionAccountsStore
    private let settings: CodexPillSettingsStore
    private let remoteHostClient: RemoteHostClient
    private let remoteHostRuntime: RemoteHostRuntime
    private let alertPresenter: MenuBarAlertPresenter
    private let panelPresenter: MenuBarPanelPresenter
    private let alertFactory: MenuBarAlertFactory
    private let sealValidationRun: CodexPillSealValidationRun?
    private let recordMenuAction: (String, [String: String]) -> Void
    private let recordValidationEvent: (String, String, [String], [String: String]) -> Void
    private let rebuildMenu: () -> Void
    private let cancelMenuTracking: () -> Void
    private let setLastSwitchTargetName: (String?) -> Void

    init(
        store: MenuBarHostActionAccountsStore,
        settings: CodexPillSettingsStore,
        remoteHostClient: RemoteHostClient,
        remoteHostRuntime: RemoteHostRuntime,
        alertPresenter: MenuBarAlertPresenter,
        panelPresenter: MenuBarPanelPresenter,
        alertFactory: MenuBarAlertFactory,
        sealValidationRun: CodexPillSealValidationRun?,
        recordMenuAction: @escaping (String, [String: String]) -> Void,
        recordValidationEvent: @escaping (String, String, [String], [String: String]) -> Void,
        rebuildMenu: @escaping () -> Void,
        cancelMenuTracking: @escaping () -> Void,
        setLastSwitchTargetName: @escaping (String?) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.remoteHostClient = remoteHostClient
        self.remoteHostRuntime = remoteHostRuntime
        self.alertPresenter = alertPresenter
        self.panelPresenter = panelPresenter
        self.alertFactory = alertFactory
        self.sealValidationRun = sealValidationRun
        self.recordMenuAction = recordMenuAction
        self.recordValidationEvent = recordValidationEvent
        self.rebuildMenu = rebuildMenu
        self.cancelMenuTracking = cancelMenuTracking
        self.setLastSwitchTargetName = setLastSwitchTargetName
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
        sealValidationRun?.recordRemoteHostSwitchMenuAction(
            targetName: account.name,
            hostName: remoteHost.displayName
        )
        recordValidationEvent(
            "remote_host_switch_started",
            "remote_host_switch_start",
            Self.remoteHostSwitchInvariantIDs,
            [
                "targetName": account.name,
                "hostName": remoteHost.displayName
            ]
        )
        sealValidationRun?.recordRemoteHostSwitchStarted(
            targetName: account.name,
            hostName: remoteHost.displayName
        )
        setLastSwitchTargetName(account.name)
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
        sealValidationRun?.recordAddHostMenuAction()
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
                    self?.recordValidationEvent(
                        "add_host_setup_presented",
                        "add_host_setup",
                        Self.addHostPromptInvariantIDs,
                        [:]
                    )
                    self?.sealValidationRun?.recordAddHostSetupPresented()
                },
                onCancelled: { [weak self] in
                    self?.recordValidationEvent(
                        "add_host_setup_cancelled",
                        "add_host_setup",
                        Self.addHostPromptInvariantIDs,
                        [:]
                    )
                },
                onValidationStarted: { [weak self] host in
                    self?.recordValidationEvent(
                        "add_host_validation_started",
                        "add_host_validation",
                        Self.addHostPromptInvariantIDs,
                        ["hostName": host.destination]
                    )
                    self?.sealValidationRun?.recordAddHostValidationStarted(hostName: host.destination)
                },
                onValidationFinished: { [weak self] host, result in
                    self?.recordAddHostValidationFinished(host: host, result: result)
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
        recordValidationEvent(
            "remote_host_reverify_started",
            "remote_host_reverify_start",
            Self.remoteHostReverifyInvariantIDs,
            [
                "hostName": hostState.host.displayName,
                "accountName": baseAccount.name
            ]
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
            let eventName = refreshedState?.verificationStatus == .verified
                ? "remote_host_reverify_succeeded"
                : "remote_host_reverify_failed"
            self.recordValidationEvent(
                eventName,
                "remote_host_reverify_result",
                Self.remoteHostReverifyInvariantIDs,
                [
                    "hostName": hostState.host.displayName,
                    "accountName": baseAccount.name
                ]
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
            recordValidationEvent(
                "add_host_account_setup_unavailable",
                "add_host_account_setup",
                Self.addHostPromptInvariantIDs,
                ["hostName": remoteHost.displayName]
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
            recordValidationEvent(
                "add_host_account_setup_cancelled",
                "add_host_account_setup",
                Self.addHostPromptInvariantIDs,
                ["hostName": remoteHost.displayName]
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
        switch result {
        case .verified:
            recordValidationEvent(
                "remote_host_active_account_changed",
                "remote_host_switch_result",
                Self.remoteHostSwitchInvariantIDs,
                [
                    "targetName": account.name,
                    "hostName": remoteHost.displayName
                ]
            )
            sealValidationRun?.recordRemoteHostActiveAccountChanged(
                targetName: account.name,
                hostName: remoteHost.displayName
            )
        case .notVerified(let message, _):
            recordValidationEvent(
                "remote_host_switch_not_verified",
                "remote_host_switch_result",
                Self.remoteHostSwitchInvariantIDs,
                [
                    "targetName": account.name,
                    "hostName": remoteHost.displayName,
                    "message": message
                ]
            )
        case .failed(let message, let hostReachable):
            recordValidationEvent(
                "remote_host_switch_failed",
                "remote_host_switch_result",
                Self.remoteHostSwitchInvariantIDs,
                [
                    "targetName": account.name,
                    "hostName": remoteHost.displayName,
                    "message": message,
                    "hostReachable": hostReachable ? "true" : "false"
                ]
            )
        }
    }

    private func recordAddHostValidationFinished(
        host: RemoteHost,
        result: Result<Void, Error>
    ) {
        switch result {
        case .success:
            recordValidationEvent(
                "add_host_validation_succeeded",
                "add_host_validation",
                Self.addHostPromptInvariantIDs,
                ["hostName": host.destination]
            )
        case .failure(let error):
            recordValidationEvent(
                "add_host_validation_failed",
                "add_host_validation",
                Self.addHostPromptInvariantIDs,
                [
                    "hostName": host.destination,
                    "message": error.localizedDescription
                ]
            )
            sealValidationRun?.recordAddHostValidationFailed(
                hostName: host.destination,
                message: error.localizedDescription
            )
        }
    }
}
