import AppKit
import Observation
import OSLog
import UserNotifications

private let menuBarCoordinatorLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "MenuBarCoordinator")

protocol ApplicationActivator {
    func activate()
}

struct NSApplicationActivator: ApplicationActivator {
    func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private static let liveProofLayer = "live_ui"
    private static let hoverInvariantIDs = ["menubar.text_on_hover.stays_visible_inside_resized_bounds"]
    private static let switchInvariantIDs = ["accounts.switch_account.menu_action_changes_active_account"]
    private static let addAccountNameDialogInvariantIDs = [
        "accounts.add_account.name_dialog_presented",
        "accounts.add_account.name_dialog_cancelled",
        "accounts.add_account.cancel_keeps_account_state"
    ]
    private static let addHostPromptInvariantIDs = ["hosts.add_host.destination_validation_failed"]
    private static let remoteHostSwitchInvariantIDs = ["hosts.switch_account_on_host.changes_remote_active_account"]
    private static let remoteHostReverifyInvariantIDs = ["hosts.reverify_remote_account.refreshes_remote_verification_state"]
    private static let scheduledRefreshInvariantIDs = ["accounts.scheduled_refresh.requested_and_completed"]

    private let statusItemRuntime: StatusItemRuntime
    private let store: MenuBarAccountsStore
    private let settings: AppSettings
    private let remoteHostClient: RemoteHostClient
    private let cliProcessInspector: CodexCLIProcessInspector
    private let alertPresenter: MenuBarAlertPresenter
    private let panelPresenter: MenuBarPanelPresenter
    private let alertFactory: MenuBarAlertFactory
    private let notificationStateStore: NotificationStateStore
    private let notificationDelivery: AccountAvailabilityNotifier
    private let applicationActivator: ApplicationActivator
    private let notificationSettingsLauncher: NotificationSettingsLauncher
    private let validationSink: MenuBarValidationSink?
    private let validationScenario: String?
    private let sealValidationRun: CodexPillSealValidationRun?
    private let allowsEmptyStatePrompt: Bool
    private let remoteHostRuntime: RemoteHostRuntime
    private let notificationPolicy = AccountAvailabilityNotificationPolicy()
    private let notificationActionResolver = AccountAvailabilityNotificationActionResolver()
    private let notificationPayloadRenderer = AccountAvailabilityNotificationPayloadRenderer()
    private let accountActionFlow = AccountActionFlow()
    private let menuBuilder = MenuBarMenuBuilder()
    private var autoRefreshTimer: Timer?
    private var wakeRefreshTask: Task<Void, Never>?
    private var notificationWaitTask: Task<Void, Never>?
    private var hasPromptedForEmptyState = false
    private var isObservingSettings = false
    private var isObservingStore = false
    private var lastMenuAction: String?
    private var lastSwitchTargetName: String?
    private var lastConfirmationRequest: String?
    private var lastConfirmationAccepted: Bool?
    private var lastObservedActiveAccountID: UUID?
    private var lastObservedActiveAccountName: String?
    private var pendingSwitchValidationTargetID: UUID?
    private var pendingSwitchValidationTargetName: String?
    private var previousNotificationSnapshots: [UUID: AccountAvailabilitySnapshot] = [:]
    private var cachedNotificationAuthorizationState: NotificationAuthorizationState = .unknown
    private var activeIsolatedAddAccountSession: IsolatedAddAccountSignInSession?

    init(
        statusItemRuntime: StatusItemRuntime,
        store: MenuBarAccountsStore,
        settings: AppSettings,
        remoteHostClient: RemoteHostClient = UnavailableRemoteHostClient(),
        cliProcessInspector: CodexCLIProcessInspector = CodexCLIProcessInspector(),
        alertPresenter: MenuBarAlertPresenter,
        panelPresenter: MenuBarPanelPresenter? = nil,
        alertFactory: MenuBarAlertFactory = MenuBarAlertFactory(),
        notificationDelivery: AccountAvailabilityNotifier = AccountAvailabilityNotificationCenter(),
        applicationActivator: ApplicationActivator = NSApplicationActivator(),
        notificationSettingsLauncher: NotificationSettingsLauncher = SystemNotificationSettingsLauncher(),
        validationSink: MenuBarValidationSink? = nil,
        validationScenario: String? = MenuBarValidationConfiguration.scenario(),
        sealValidationRun: CodexPillSealValidationRun? = nil,
        allowsEmptyStatePrompt: Bool = true
    ) {
        self.statusItemRuntime = statusItemRuntime
        self.store = store
        self.settings = settings
        self.remoteHostClient = remoteHostClient
        self.cliProcessInspector = cliProcessInspector
        self.alertPresenter = alertPresenter
        self.panelPresenter = panelPresenter ?? SystemMenuBarPanelPresenter()
        self.alertFactory = alertFactory
        self.notificationStateStore = NotificationStateStore(settings: settings)
        self.notificationDelivery = notificationDelivery
        self.applicationActivator = applicationActivator
        self.notificationSettingsLauncher = notificationSettingsLauncher
        self.validationSink = validationSink
        self.validationScenario = validationScenario
        self.sealValidationRun = sealValidationRun ?? CodexPillSealValidationConfiguration.makeRun()
        self.allowsEmptyStatePrompt = allowsEmptyStatePrompt
        self.remoteHostRuntime = RemoteHostRuntime(
            settings: settings,
            remoteHostClient: remoteHostClient,
            accounts: { store.accounts },
            persistAccountMetadata: { store.persistAccountMetadata($0) },
            markAccountActivated: { [notificationStateStore] accountID in
                notificationStateStore.markAccountActivated(accountID)
            }
        )
    }

    func start() {
        statusItemRuntime.onEvent = { [weak self] event in
            self?.handleStatusItemRuntimeEvent(event)
        }
        restorePersistedRemoteHostState()
        statusItemRuntime.start(presentation: statusItemPresentation(for: menuState()))
        lastObservedActiveAccountID = store.activeAccountID
        lastObservedActiveAccountName = store.activeAccount?.name
        previousNotificationSnapshots = notificationSnapshotMap(for: menuState())
        startObservingStore()
        startObservingSettings()
        rebuildMenu()
        scheduleAutoRefresh()
        syncBackgroundState()
        refreshNotificationAuthorizationState()
        refreshRemoteHostStateIfNeeded()
    }

    func invalidate() {
        autoRefreshTimer?.invalidate()
        wakeRefreshTask?.cancel()
        notificationWaitTask?.cancel()
        cancelActiveIsolatedAddAccountSession()
        sealValidationRun?.cancelIfUnfinished()
        statusItemRuntime.invalidate()
    }

    func handleSystemDidWake() {
        scheduleAutoRefresh()
        wakeRefreshTask?.cancel()
        wakeRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            await MainActor.run {
                guard let self else { return }
                self.performScheduledRefresh()
            }
        }
    }

    @objc
    func addAccount() {
        recordMenuAction("addAccount")
        sealValidationRun?.recordAddAccountMenuAction(
            activeAccount: store.activeAccount,
            savedAccounts: store.accounts
        )
        menuBarCoordinatorLogger.log("addAccount action invoked")
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        menuBarCoordinatorLogger.log("Running CLI sessions before add-account: \(runningCLISessions, privacy: .public)")

        let request = alertFactory.makeAddAccountRequest(runningCLISessions: runningCLISessions)
        recordValidationEvent(
            "add_account_prompt_presented",
            step: "add_account_prompt",
            invariantIds: Self.addAccountNameDialogInvariantIDs
        )
        sealValidationRun?.recordAddAccountNameDialogPresented(runningCLISessions: runningCLISessions)

        menuBarCoordinatorLogger.log("Presenting add-account confirmation alert")
        guard let name = alertPresenter.presentTextInput(request) else {
            menuBarCoordinatorLogger.log("Add-account flow cancelled from alert")
            recordValidationEvent(
                "add_account_prompt_cancelled",
                step: "add_account_prompt",
                invariantIds: Self.addAccountNameDialogInvariantIDs
            )
            sealValidationRun?.recordAddAccountNameDialogCancelled(
                activeAccount: store.activeAccount,
                savedAccounts: store.accounts
            )
            return
        }
        recordValidationEvent(
            "add_account_prompt_confirmed",
            step: "add_account_prompt",
            invariantIds: Self.addAccountNameDialogInvariantIDs,
            payload: ["enteredName": name]
        )

        menuBarCoordinatorLogger.log("Dispatching isolated add-account task to store")
        Task { @MainActor [weak self] in
            await self?.beginIsolatedAddAccount(named: name)
        }
    }

    @objc
    func removeAccount(_ sender: NSMenuItem) {
        recordMenuAction("removeAccount")
        guard
            let idString = sender.representedObject as? String,
            let id = UUID(uuidString: idString),
            let account = store.accounts.first(where: { $0.id == id })
        else {
            return
        }

        let request = alertFactory.makeRemoveAccountRequest(
            accountName: account.name,
            isCurrent: account.id == store.activeAccountID
        )

        guard alertPresenter.presentConfirmation(request) else { return }
        Task { await store.removeSavedAccount(account) }
    }

    @objc
    func renameAccount(_ sender: NSMenuItem) {
        recordMenuAction("renameAccount")
        guard
            let idString = sender.representedObject as? String,
            let id = UUID(uuidString: idString),
            let account = store.accounts.first(where: { $0.id == id })
        else {
            return
        }

        let request = alertFactory.makeRenameAccountRequest(accountName: account.name)
        guard let newName = alertPresenter.presentTextInput(request) else { return }
        Task { await store.renameSavedAccount(account, to: newName) }
    }

    @objc
    func selectRefreshInterval(_ sender: NSMenuItem) {
        recordMenuAction("selectRefreshInterval")
        guard let minutes = sender.representedObject as? Int else { return }
        settings.refreshIntervalMinutes = minutes
    }

    @objc
    func selectVisibleInactiveAccountCount(_ sender: NSMenuItem) {
        recordMenuAction("selectVisibleInactiveAccountCount")
        guard let count = sender.representedObject as? Int else { return }
        settings.visibleInactiveAccountCount = count
    }

    @objc
    func selectStatusBarStyle(_ sender: NSMenuItem) {
        recordMenuAction("selectStatusBarStyle")
        guard
            let rawValue = sender.representedObject as? String,
            let style = StatusBarIndicatorStyle(rawValue: rawValue)
        else {
            return
        }
        settings.statusBarIndicatorStyle = style
    }

    @objc
    func toggleStatusBarMonochrome(_ sender: NSMenuItem) {
        recordMenuAction("toggleStatusBarMonochrome")
        settings.statusBarMonochrome.toggle()
    }

    @objc
    func selectStatusBarDisplayMode(_ sender: NSMenuItem) {
        recordMenuAction("selectStatusBarDisplayMode")
        guard
            let rawValue = sender.representedObject as? String,
            let mode = StatusBarDisplayMode(rawValue: rawValue)
        else {
            return
        }
        if !menuState().hasStatusItemContentData, mode != .iconOnly {
            settings.statusBarDisplayMode = .iconOnly
            return
        }
        settings.statusBarDisplayMode = mode
    }

    @objc
    func chooseProgressAccentColor(_ sender: NSMenuItem) {
        recordMenuAction("chooseProgressAccentColor")
        presentProgressColorPanel()
    }

    @objc
    func resetProgressAccentColor(_ sender: NSMenuItem) {
        recordMenuAction("resetProgressAccentColor")
        settings.resetProgressAccentColor()
        NSColorPanel.shared.color = settings.progressAccentColor
    }

    @objc
    func toggleNotificationsWhenBlocked(_ sender: NSMenuItem) {
        recordMenuAction("toggleNotificationsWhenBlocked")
        let hadAnyNotificationsEnabled = notificationStateStore.whenBlockedEnabled || notificationStateStore.whenOutEnabled
        notificationStateStore.whenBlockedEnabled.toggle()
        if !hadAnyNotificationsEnabled, notificationStateStore.whenBlockedEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.notificationDelivery.requestAuthorizationIfNeeded()
                self.refreshNotificationAuthorizationState()
            }
        }
    }

    @objc
    func toggleNotificationsWhenOut(_ sender: NSMenuItem) {
        recordMenuAction("toggleNotificationsWhenOut")
        let hadAnyNotificationsEnabled = notificationStateStore.whenBlockedEnabled || notificationStateStore.whenOutEnabled
        notificationStateStore.whenOutEnabled.toggle()
        if !hadAnyNotificationsEnabled, notificationStateStore.whenOutEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.notificationDelivery.requestAuthorizationIfNeeded()
                self.refreshNotificationAuthorizationState()
            }
        }
    }

    @objc
    func enableNotifications(_ sender: NSMenuItem) {
        recordMenuAction("enableNotifications")
        if !notificationStateStore.whenBlockedEnabled && !notificationStateStore.whenOutEnabled {
            notificationStateStore.whenBlockedEnabled = true
            notificationStateStore.whenOutEnabled = true
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            var state = await self.notificationDelivery.authorizationState()
            switch state {
            case .denied:
                self.notificationSettingsLauncher.openNotificationSettings()
            case .notDetermined, .unknown:
                await self.notificationDelivery.requestAuthorizationIfNeeded()
                state = await self.notificationDelivery.authorizationState()
            case .authorized:
                break
            }
            self.cachedNotificationAuthorizationState = state
            self.rebuildMenu()
        }
    }

    @objc
    func switchAccount(_ sender: NSMenuItem) {
        guard
            let idString = sender.representedObject as? String,
            let id = UUID(uuidString: idString),
            let account = store.accounts.first(where: { $0.id == id })
        else {
            return
        }

        recordMenuAction("switchAccount", payload: ["targetName": account.name])
        sealValidationRun?.recordSwitchAccountMenuAction(
            targetAccount: account,
            activeAccount: store.activeAccount,
            savedAccounts: store.accounts
        )
        lastSwitchTargetName = account.name
        requestSwitch(to: account)
    }

    @objc
    func switchAccountOnHost(_ sender: NSMenuItem) {
        guard
            let payload = sender.representedObject as? HostAccountMenuItemPayload,
            let remoteHost = settings.remoteHostState(for: payload.hostDestination)?.host,
            let account = store.accounts.first(where: { $0.id == payload.accountID })
        else {
            return
        }

        recordMenuAction("switchAccountOnHost", payload: [
            "targetName": account.name,
            "hostName": remoteHost.displayName
        ])
        sealValidationRun?.recordRemoteHostSwitchMenuAction(
            targetName: account.name,
            hostName: remoteHost.displayName
        )
        recordValidationEvent(
            "remote_host_switch_started",
            step: "remote_host_switch_start",
            invariantIds: Self.remoteHostSwitchInvariantIDs,
            payload: [
                "targetName": account.name,
                "hostName": remoteHost.displayName
            ]
        )
        sealValidationRun?.recordRemoteHostSwitchStarted(
            targetName: account.name,
            hostName: remoteHost.displayName
        )
        lastSwitchTargetName = account.name
        remoteHostRuntime.beginHostSwitch(to: account, on: remoteHost)
        rebuildMenu()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.store.switchToAccountOnHost(account, on: remoteHost)
            self.remoteHostRuntime.applySwitchOutcome(result, account: account, host: remoteHost)
            switch result {
            case .verified:
                self.recordValidationEvent(
                    "remote_host_active_account_changed",
                    step: "remote_host_switch_result",
                    invariantIds: Self.remoteHostSwitchInvariantIDs,
                    payload: [
                        "targetName": account.name,
                        "hostName": remoteHost.displayName
                    ]
                )
                self.sealValidationRun?.recordRemoteHostActiveAccountChanged(
                    targetName: account.name,
                    hostName: remoteHost.displayName
                )
            case .notVerified(let message, _):
                self.recordValidationEvent(
                    "remote_host_switch_not_verified",
                    step: "remote_host_switch_result",
                    invariantIds: Self.remoteHostSwitchInvariantIDs,
                    payload: [
                        "targetName": account.name,
                        "hostName": remoteHost.displayName,
                        "message": message
                    ]
                )
            case .failed(let message, let hostReachable):
                self.recordValidationEvent(
                    "remote_host_switch_failed",
                    step: "remote_host_switch_result",
                    invariantIds: Self.remoteHostSwitchInvariantIDs,
                    payload: [
                        "targetName": account.name,
                        "hostName": remoteHost.displayName,
                        "message": message,
                        "hostReachable": hostReachable ? "true" : "false"
                    ]
                )
            }
            self.rebuildMenu()
        }
    }

    @objc
    func addHost(_ sender: NSMenuItem) {
        recordMenuAction("addHost")
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
                        step: "add_host_setup",
                        invariantIds: Self.addHostPromptInvariantIDs
                    )
                    self?.sealValidationRun?.recordAddHostSetupPresented()
                },
                onCancelled: { [weak self] in
                    self?.recordValidationEvent(
                        "add_host_setup_cancelled",
                        step: "add_host_setup",
                        invariantIds: Self.addHostPromptInvariantIDs
                    )
                },
                onValidationStarted: { [weak self] host in
                    self?.recordValidationEvent(
                        "add_host_validation_started",
                        step: "add_host_validation",
                        invariantIds: Self.addHostPromptInvariantIDs,
                        payload: ["hostName": host.destination]
                    )
                    self?.sealValidationRun?.recordAddHostValidationStarted(hostName: host.destination)
                },
                onValidationFinished: { [weak self] host, result in
                    switch result {
                    case .success:
                        self?.recordValidationEvent(
                            "add_host_validation_succeeded",
                            step: "add_host_validation",
                            invariantIds: Self.addHostPromptInvariantIDs,
                            payload: ["hostName": host.destination]
                        )
                    case .failure(let error):
                        self?.recordValidationEvent(
                            "add_host_validation_failed",
                            step: "add_host_validation",
                            invariantIds: Self.addHostPromptInvariantIDs,
                            payload: [
                                "hostName": host.destination,
                                "message": error.localizedDescription
                            ]
                        )
                        self?.sealValidationRun?.recordAddHostValidationFailed(
                            hostName: host.destination,
                            message: error.localizedDescription
                        )
                    }
                }
            ) else {
                return
            }

            guard let activeAccount = self.store.activeAccount else {
                self.recordValidationEvent(
                    "add_host_account_setup_unavailable",
                    step: "add_host_account_setup",
                    invariantIds: Self.addHostPromptInvariantIDs,
                    payload: ["hostName": remoteHost.displayName]
                )
                self.rebuildMenu()
                return
            }

            let shouldInstallCurrentAccount = self.alertPresenter.presentConfirmation(
                self.alertFactory.makeInstallCurrentAccountOnHostRequest(
                    accountName: activeAccount.name,
                    hostName: remoteHost.displayName
                )
            )

            guard shouldInstallCurrentAccount else {
                self.recordValidationEvent(
                    "add_host_account_setup_cancelled",
                    step: "add_host_account_setup",
                    invariantIds: Self.addHostPromptInvariantIDs,
                    payload: ["hostName": remoteHost.displayName]
                )
                self.rebuildMenu()
                return
            }

            self.settings.updateRemoteHostState(for: remoteHost) { state in
                state.desiredAccountID = activeAccount.id
                state.verificationStatus = .verifying
                state.lastVerificationError = nil
            }
            self.remoteHostRuntime.beginHostSwitch(to: activeAccount, on: remoteHost)
            self.rebuildMenu()
            let result = await self.store.switchToAccountOnHost(activeAccount, on: remoteHost)
            self.remoteHostRuntime.applySwitchOutcome(
                result,
                account: activeAccount,
                host: remoteHost,
                recordsInstalledAccountOnFailure: true
            )
            self.rebuildMenu()
        }
    }

    @objc
    func removeHost(_ sender: NSMenuItem) {
        guard
            let payload = sender.representedObject as? HostSelectionMenuItemPayload,
            let hostState = settings.remoteHostState(for: payload.hostDestination)
        else { return }
        let remoteHost = hostState.host
        recordMenuAction("removeHost", payload: ["hostName": remoteHost.displayName])
        guard alertPresenter.presentConfirmation(alertFactory.makeRemoveHostRequest(hostName: remoteHost.displayName)) else {
            return
        }

        remoteHostRuntime.removeHost(hostState)
        rebuildMenu()
    }

    @objc
    func reverifyHost(_ sender: NSMenuItem) {
        guard
            let payload = sender.representedObject as? HostSelectionMenuItemPayload,
            let hostState = settings.remoteHostState(for: payload.hostDestination)
        else { return }

        reverifyHost(hostState: hostState)
    }

    func reverifyHost(hostDestination: String) {
        guard let hostState = settings.remoteHostState(for: hostDestination) else { return }
        reverifyHost(hostState: hostState)
    }

    private func reverifyHost(hostState: PersistedRemoteHostState) {
        guard let baseAccount = remoteHostRuntime.beginReverification(hostState: hostState) else { return }
        statusItemRuntime.menu?.cancelTracking()

        recordMenuAction("reverifyHost", payload: [
            "hostName": hostState.host.displayName,
            "accountName": baseAccount.name
        ])
        recordValidationEvent(
            "remote_host_reverify_started",
            step: "remote_host_reverify_start",
            invariantIds: Self.remoteHostReverifyInvariantIDs,
            payload: [
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
                step: "remote_host_reverify_result",
                invariantIds: Self.remoteHostReverifyInvariantIDs,
                payload: [
                    "hostName": hostState.host.displayName,
                    "accountName": baseAccount.name
                ]
            )
            self.rebuildMenu()
        }
    }

    @objc
    func adoptDetectedRemoteAccount(_ sender: NSMenuItem) {
        guard
            let payload = sender.representedObject as? HostAccountMenuItemPayload,
            let hostState = settings.remoteHostState(for: payload.hostDestination)
        else { return }

        adoptDetectedRemoteAccount(
            hostState: hostState,
            accountID: payload.accountID
        )
    }

    func adoptDetectedRemoteAccount(hostDestination: String, accountID: UUID) {
        guard let hostState = settings.remoteHostState(for: hostDestination) else { return }
        adoptDetectedRemoteAccount(hostState: hostState, accountID: accountID)
    }

    private func adoptDetectedRemoteAccount(hostState: PersistedRemoteHostState, accountID: UUID) {
        guard let detectedAccount = remoteHostRuntime.beginAdoptingDetectedAccount(hostState: hostState, accountID: accountID) else { return }
        statusItemRuntime.menu?.cancelTracking()

        recordMenuAction("adoptDetectedRemoteAccount", payload: [
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

    @objc
    func showAbout() {
        recordMenuAction("showAbout")
        alertPresenter.presentInfo(alertFactory.makeAboutRequest())
    }

    @objc
    func quitApp() {
        recordMenuAction("quitApp")
        NSApplication.shared.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusItemRuntime.handleMenuWillOpen()
        recordValidationEvent(
            "menu_opened",
            step: "menu_open",
            payload: ["menuItemCount": String(statusItemRuntime.menuItemCount)]
        )
        recordValidationSnapshot(for: menuState())
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        store.refreshActiveAccount()
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItemRuntime.handleMenuDidClose()
        recordValidationSnapshot(for: menuState())
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(selectStatusBarDisplayMode(_:)) else {
            return menuItem.isEnabled
        }

        guard
            let rawValue = menuItem.representedObject as? String,
            let mode = StatusBarDisplayMode(rawValue: rawValue)
        else {
            return false
        }

        return menuState().canSelectStatusBarDisplayMode(mode)
    }

    func requestSwitch(toAccountID accountID: UUID) {
        guard let account = store.accounts.first(where: { $0.id == accountID }) else { return }
        requestSwitch(to: account)
    }

    private func rebuildMenu(using state: MenuBarMenuState? = nil) {
        let state = state ?? menuState()
        let menu = statusItemRuntime.menu ?? NSMenu()
        menuBuilder.populate(menu: menu, state: state, target: self)
        statusItemRuntime.menu = menu
        recordValidationSnapshot(for: state)
    }

    private func menuState() -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: store.activeAccount,
            inactiveAccounts: store.sortedInactiveAccounts,
            remoteHosts: remoteHostRuntime.menuStates(),
            visibleInactiveAccountCount: settings.visibleInactiveAccountCount,
            visibleInactiveAccountCountOptions: settings.visibleInactiveAccountCountOptions,
            refreshIntervalMinutes: settings.refreshIntervalMinutes,
            refreshIntervalOptions: settings.refreshIntervalOptions,
            statusBarMonochrome: settings.statusBarMonochrome,
            statusBarIndicatorStyle: settings.statusBarIndicatorStyle,
            statusBarDisplayMode: settings.statusBarDisplayMode,
            progressAccentColor: settings.progressAccentColor,
            hasCustomProgressAccentColor: settings.hasCustomProgressAccentColor,
            isBusy: store.isBusy,
            statusMessage: store.statusMessage,
            notificationsWhenBlockedEnabled: notificationStateStore.whenBlockedEnabled,
            notificationsWhenOutEnabled: notificationStateStore.whenOutEnabled,
            notificationAuthorizationState: cachedNotificationAuthorizationState
        )
    }

    private func requestSwitch(to account: CodexAccount) {
        lastConfirmationRequest = "switchAccount"
        recordValidationEvent(
            "switch_confirmation_presented",
            step: "switch_confirmation",
            payload: ["targetName": account.name]
        )
        sealValidationRun?.recordSwitchConfirmationPresented(targetAccount: account)
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        let request = alertFactory.makeSwitchAccountRequest(accountName: account.name, runningCLISessions: runningCLISessions)

        let accepted = alertPresenter.presentConfirmation(request)
        lastConfirmationAccepted = accepted
        recordValidationEvent(
            accepted ? "switch_confirmation_accepted" : "switch_confirmation_cancelled",
            step: "switch_confirmation",
            payload: ["targetName": account.name]
        )
        guard accepted else { return }
        sealValidationRun?.recordSwitchConfirmationAccepted(targetAccount: account)
        beginLocalSwitch(to: account)
    }

    private func beginIsolatedAddAccount(named name: String) async {
        do {
            let session = try await store.startIsolatedAddAccountFlow(named: name)
            activeIsolatedAddAccountSession = session

            let signInRequest = alertFactory.makeAddAccountSignInRequest(prompt: session.prompt)
            let result = await panelPresenter.presentAddAccountSignIn(
                signInRequest,
                waitForCompletion: { [store] in
                    do {
                        let account = try await store.completeIsolatedAddAccount(session)
                        return .success(account)
                    } catch {
                        return .failure(error)
                    }
                },
                onCancel: { [store] in
                    store.cancelIsolatedAddAccount(session)
                }
            )
            if activeIsolatedAddAccountSession === session {
                activeIsolatedAddAccountSession = nil
            }

            handleAddAccountCompletion(result, retryName: name)
        } catch {
            handleAddAccountFailure(
                accountActionFlow.resolveAddAccountStartFailure(error, retryName: name)
            )
        }
    }

    private func cancelActiveIsolatedAddAccountSession() {
        guard let session = activeIsolatedAddAccountSession else { return }
        activeIsolatedAddAccountSession = nil
        store.cancelIsolatedAddAccount(session)
    }

    private func presentAddAccountSuccess(for account: CodexAccount) {
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        let request = alertFactory.makeAddAccountSuccessRequest(
            accountName: account.name,
            runningCLISessions: runningCLISessions
        )
        let accepted = alertPresenter.presentConfirmation(request)
        handleAddAccountSuccessConfirmation(
            accountActionFlow.resolveAddAccountSuccessConfirmation(
                account: account,
                accepted: accepted
            )
        )
    }

    private func handleAddAccountCompletion(_ result: MenuBarAddAccountSignInPanelResult, retryName: String) {
        let flowResult: AccountActionFlow.AddAccountResult
        switch result {
        case .completed(let account):
            flowResult = .completed(account)
        case .failed(let error):
            flowResult = .failed(error)
        case .cancelled:
            flowResult = .cancelled
        }

        switch accountActionFlow.resolveAddAccountCompletion(flowResult, retryName: retryName) {
        case .offerLocalSwitch(let account):
            presentAddAccountSuccess(for: account)
        case .handleFailure(let step):
            handleAddAccountFailure(step)
        case .none:
            break
        }
    }

    private func handleAddAccountSuccessConfirmation(_ step: AccountActionFlow.AddAccountConfirmationStep) {
        switch step {
        case .switchLocally(let account):
            lastSwitchTargetName = account.name
            beginLocalSwitch(to: account)
        case .none:
            break
        }
    }

    private func handleAddAccountFailure(_ step: AccountActionFlow.AddAccountFailureStep) {
        _ = store.consumePendingErrorMessage()

        switch step {
        case .showStartFailure:
            alertPresenter.presentInfo(alertFactory.makeAddAccountStartFailureRequest())
        case .offerExpiredCodeRetry(let retryName):
            let request = alertFactory.makeAddAccountExpiredRequest()
            guard alertPresenter.presentConfirmation(request) else { return }
            Task { @MainActor [weak self] in
                await self?.beginIsolatedAddAccount(named: retryName)
            }
        case .showError(let message):
            alertPresenter.presentInfo(alertFactory.makeErrorRequest(message: message))
        case .offerDuplicateNameRecovery:
            let request = alertFactory.makeAddAccountDuplicateNameRequest()
            guard alertPresenter.presentConfirmation(request) else { return }
            addAccount()
        case .showUnsafeAuthChange:
            alertPresenter.presentInfo(alertFactory.makeAddAccountUnsafeAuthChangeRequest())
        case .showSaveFailure:
            alertPresenter.presentInfo(alertFactory.makeAddAccountSaveFailureRequest())
        case .showAccountAlreadySaved(let accountName):
            alertPresenter.presentInfo(alertFactory.makeAccountAlreadySavedRequest(accountName: accountName))
        }
    }

    private func beginLocalSwitch(to account: CodexAccount) {
        pendingSwitchValidationTargetID = account.id
        pendingSwitchValidationTargetName = account.name
        recordValidationEvent(
            "switch_workflow_started",
            step: "switch_workflow_start",
            invariantIds: Self.switchInvariantIDs,
            payload: ["targetName": account.name]
        )
        sealValidationRun?.recordSwitchWorkflowStarted(targetAccount: account)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.store.switchToAccount(account)
            if self.pendingSwitchValidationTargetID == account.id,
               self.store.activeAccountID != account.id {
                self.pendingSwitchValidationTargetID = nil
                self.pendingSwitchValidationTargetName = nil
            }
        }
    }

    func handleNotificationResponse(actionIdentifier: String?, userInfo: [AnyHashable: Any]) async {
        let resolvedActionIdentifier = actionIdentifier ?? UNNotificationDefaultActionIdentifier
        guard resolvedActionIdentifier != UNNotificationDefaultActionIdentifier else {
            applicationActivator.activate()
            return
        }

        guard
            let accountIDString = userInfo["accountID"] as? String,
            let notifiedAccountID = UUID(uuidString: accountIDString)
        else {
            applicationActivator.activate()
            return
        }

        let requestedTarget = requestedNotificationTarget(
            actionIdentifier: resolvedActionIdentifier,
            userInfo: userInfo
        )

        let state = menuState()
        let resolution = notificationActionResolver.resolve(
            notifiedAccountID: notifiedAccountID,
            requestedTarget: requestedTarget,
            currentSnapshots: state.availabilitySnapshots,
            activeAccounts: activeNotificationContexts(from: state),
            settings: AccountAvailabilityNotificationSettings(
                whenBlockedEnabled: notificationStateStore.whenBlockedEnabled,
                whenOutEnabled: notificationStateStore.whenOutEnabled
            )
        )

        applicationActivator.activate()

        guard let resolution else {
            return
        }

        switch resolution.target {
        case .local:
            presentNotificationDrivenLocalSwitch(resolution: resolution)
        case .remote(let hostDestination):
            presentNotificationDrivenRemoteSwitch(
                resolution: resolution,
                hostDestination: hostDestination
            )
        }
    }

    private func recordMenuAction(_ name: String, payload: [String: String] = [:]) {
        lastMenuAction = name
        recordValidationEvent(
            "menu_action_dispatched",
            step: "menu_action_dispatch",
            payload: ["action": name].merging(payload, uniquingKeysWith: { _, new in new })
        )
        recordValidationSnapshot(for: menuState())
    }

    private func scheduleAutoRefresh() {
        autoRefreshTimer?.invalidate()
        let interval = AppRuntimeEnvironment.validationAutoRefreshIntervalSeconds() ?? TimeInterval(settings.refreshIntervalMinutes * 60)
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performScheduledRefresh()
            }
        }
    }

    private func performScheduledRefresh() {
        guard !store.isBusy else { return }
        Task {
            if let activeAccount = store.activeAccount {
                self.recordValidationEvent(
                    "scheduled_refresh_requested",
                    step: "scheduled_refresh_request",
                    invariantIds: Self.scheduledRefreshInvariantIDs,
                    payload: ["accountName": activeAccount.name]
                )
                let outcome = await store.refreshAccountData(for: activeAccount)
                let eventName: String
                let payload: [String: String]
                switch outcome {
                case .refreshed:
                    eventName = "scheduled_refresh_completed"
                    payload = ["accountName": activeAccount.name]
                case .failed(let message):
                    eventName = "scheduled_refresh_failed"
                    payload = [
                        "accountName": activeAccount.name,
                        "error": message
                    ]
                }
                self.recordValidationEvent(
                    eventName,
                    step: "scheduled_refresh_result",
                    invariantIds: Self.scheduledRefreshInvariantIDs,
                    payload: payload
                )
            }

            self.refreshRemoteHostStateIfNeeded(markSyncing: false)
        }
    }

    private func startObservingStore() {
        guard !isObservingStore else { return }
        isObservingStore = true
        observeStoreChanges()
    }

    private func observeStoreChanges() {
        withObservationTracking {
            _ = store.accounts
            _ = store.activeAccountID
            _ = store.pendingErrorMessage
            _ = store.statusMessage
            _ = store.isBusy
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleStoreChange()
                self.observeStoreChanges()
            }
        }
    }

    private func handleStoreChange() {
        let state = menuState()
        recordActiveAccountTransitionIfNeeded()
        if !store.accounts.isEmpty {
            hasPromptedForEmptyState = false
        }
        statusItemRuntime.update(presentation: statusItemPresentation(for: state))
        rebuildMenu(using: state)
        presentPendingErrorIfNeeded()
        syncBackgroundState()
        evaluateNotifications(using: state)
    }

    private func recordActiveAccountTransitionIfNeeded() {
        let currentActiveAccountID = store.activeAccountID
        let currentActiveAccountName = store.activeAccount?.name

        defer {
            lastObservedActiveAccountID = currentActiveAccountID
            lastObservedActiveAccountName = currentActiveAccountName
        }

        guard currentActiveAccountID != lastObservedActiveAccountID else { return }
        if let currentActiveAccountID {
            notificationStateStore.markAccountActivated(currentActiveAccountID)
        }

        guard
            let pendingTargetID = pendingSwitchValidationTargetID,
            currentActiveAccountID == pendingTargetID
        else {
            return
        }

        recordValidationEvent(
            "active_account_changed",
            step: "active_account_change",
            invariantIds: Self.switchInvariantIDs,
            payload: [
                "fromName": lastObservedActiveAccountName ?? "",
                "toName": currentActiveAccountName ?? pendingSwitchValidationTargetName ?? ""
            ]
        )
        sealValidationRun?.recordActiveAccountChanged(
            fromName: lastObservedActiveAccountName,
            toName: currentActiveAccountName ?? pendingSwitchValidationTargetName ?? "",
            activeAccount: store.activeAccount,
            savedAccounts: store.accounts
        )
        pendingSwitchValidationTargetID = nil
        pendingSwitchValidationTargetName = nil
    }

    private func startObservingSettings() {
        guard !isObservingSettings else { return }
        isObservingSettings = true
        observeSettingsChanges()
    }

    private func observeSettingsChanges() {
        withObservationTracking {
            _ = settings.refreshIntervalMinutes
            _ = settings.statusBarIndicatorStyle
            _ = settings.statusBarMonochrome
            _ = settings.statusBarDisplayMode
            _ = settings.visibleInactiveAccountCount
            _ = settings.progressAccentColor
            _ = settings.remoteHostStates
            _ = settings.notificationsWhenBlockedEnabled
            _ = settings.notificationsWhenOutEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleSettingsChange()
                self.observeSettingsChanges()
            }
        }
    }

    private func handleSettingsChange() {
        let state = menuState()
        statusItemRuntime.update(presentation: statusItemPresentation(for: state))
        scheduleAutoRefresh()
        rebuildMenu(using: state)
        evaluateNotifications(using: state)
    }

    private func evaluateNotifications(using state: MenuBarMenuState, now: Date = .now) {
        let currentSnapshots = state.availabilitySnapshots
        defer {
            previousNotificationSnapshots = notificationSnapshotMap(for: state)
        }

        let decision = notificationPolicy.decision(
            previousSnapshots: Array(previousNotificationSnapshots.values),
            currentSnapshots: currentSnapshots,
            activeAccounts: activeNotificationContexts(from: state),
            settings: AccountAvailabilityNotificationSettings(
                whenBlockedEnabled: notificationStateStore.whenBlockedEnabled,
                whenOutEnabled: notificationStateStore.whenOutEnabled
            ),
            now: now
        )
        scheduleNotificationEvaluation(at: decision?.waitUntil)

        guard let decision, decision.shouldNotify else { return }
        guard notificationStateStore.shouldDeliverNotification(
            for: decision.account.id,
            reason: decision.reason,
            window: decision.window
        ) else {
            return
        }
        guard let payload = notificationPayloadRenderer.payload(for: decision, state: state) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let delivered = await self.notificationDelivery.deliver(payload)
            guard delivered else { return }
            self.notificationStateStore.recordNotification(
                for: decision.account.id,
                reason: decision.reason,
                window: decision.window,
                notifiedAt: now
            )
        }
    }

    private func notificationSnapshotMap(for state: MenuBarMenuState) -> [UUID: AccountAvailabilitySnapshot] {
        Dictionary(uniqueKeysWithValues: state.availabilitySnapshots.map { ($0.account.id, $0) })
    }

    private func activeNotificationContexts(from state: MenuBarMenuState) -> [ActiveAccountAvailabilityContext] {
        var contexts: [ActiveAccountAvailabilityContext] = []
        if let activeAccount = state.activeAccount {
            contexts.append(ActiveAccountAvailabilityContext(target: .local, accountID: activeAccount.id))
        }
        contexts.append(contentsOf: state.connectedRemoteHosts.compactMap { remoteHost in
            guard let remoteAccount = remoteHost.activeAccount else { return nil }
            return ActiveAccountAvailabilityContext(
                target: .remote(hostDestination: remoteHost.destination),
                accountID: remoteAccount.id
            )
        })
        return contexts
    }

    private func requestedNotificationTarget(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> AccountAvailabilityNotificationRequestedTarget {
        switch actionIdentifier {
        case "use_local":
            return .local
        case "use_remote":
            return .remote(preferredHostDestination: userInfo["remoteHostDestination"] as? String)
        case "use_best_option":
            return .bestOption
        default:
            return .bestOption
        }
    }

    private func presentNotificationDrivenLocalSwitch(
        resolution: AccountAvailabilityNotificationActionResolution
    ) {
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        let request = alertFactory.makeNotificationActionRequest(
            accountName: resolution.account.name,
            targetDescription: "This Mac",
            substitutionMessage: resolution.substitutionMessage,
            runningCLISessions: runningCLISessions
        )
        guard alertPresenter.presentConfirmation(request) else { return }
        lastSwitchTargetName = resolution.account.name
        beginLocalSwitch(to: resolution.account)
    }

    private func presentNotificationDrivenRemoteSwitch(
        resolution: AccountAvailabilityNotificationActionResolution,
        hostDestination: String
    ) {
        guard
            let remoteHost = settings.remoteHostState(for: hostDestination)?.host
        else {
            return
        }

        let request = alertFactory.makeNotificationActionRequest(
            accountName: resolution.account.name,
            targetDescription: remoteHost.displayName,
            substitutionMessage: resolution.substitutionMessage,
            runningCLISessions: nil
        )
        guard alertPresenter.presentConfirmation(request) else { return }

        let payload = HostAccountMenuItemPayload(
            accountID: resolution.account.id,
            hostDestination: hostDestination
        )
        let menuItem = NSMenuItem()
        menuItem.representedObject = payload
        switchAccountOnHost(menuItem)
    }

    private func scheduleNotificationEvaluation(at date: Date?) {
        notificationWaitTask?.cancel()
        guard let date, date > .now else { return }
        let delay = max(0, date.timeIntervalSinceNow)
        notificationWaitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self.performScheduledRefresh()
        }
    }

    private func refreshNotificationAuthorizationState() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let state = await self.notificationDelivery.authorizationState()
            guard self.cachedNotificationAuthorizationState != state else { return }
            self.cachedNotificationAuthorizationState = state
            self.rebuildMenu()
        }
    }

    private func restorePersistedRemoteHostState() {
        remoteHostRuntime.restorePersistedState()
    }

    private func refreshRemoteHostStateIfNeeded(markSyncing: Bool = true) {
        remoteHostRuntime.refreshAll(markSyncing: markSyncing) { [weak self] in
            self?.rebuildMenu()
        }
    }

    private func presentPendingErrorIfNeeded() {
        guard let message = store.consumePendingErrorMessage() else { return }
        alertPresenter.presentInfo(alertFactory.makeErrorRequest(message: message))
    }

    private func recordValidationSnapshot(for state: MenuBarMenuState) {
        guard let validationSink else { return }

        do {
            try validationSink.record(
                MenuBarValidationSupport.makeSnapshot(
                    state: state,
                    menu: statusItemRuntime.menu,
                    statusItemState: statusItemRuntime.snapshotState(),
                    actionTrace: .init(
                        lastMenuAction: lastMenuAction,
                        lastSwitchTargetName: lastSwitchTargetName,
                        lastConfirmationRequest: lastConfirmationRequest,
                        lastConfirmationAccepted: lastConfirmationAccepted
                    )
                )
            )
        } catch {
            menuBarCoordinatorLogger.error("Failed to record validation snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordValidationEvent(
        _ name: String,
        step: String,
        invariantIds: [String] = [],
        payload: [String: String] = [:]
    ) {
        guard let validationSink, let validationScenario else { return }

        do {
            try validationSink.record(
                MenuBarValidationEvent(
                    scenario: validationScenario,
                    proofLayer: Self.liveProofLayer,
                    invariantIds: invariantIds,
                    event: name,
                    step: step,
                    payload: sanitizedValidationPayload(payload)
                )
            )
        } catch {
            menuBarCoordinatorLogger.error("Failed to record validation event: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncBackgroundState() {
        promptForEmptyStateIfNeeded()
    }

    private func promptForEmptyStateIfNeeded() {
        guard allowsEmptyStatePrompt else { return }
        guard store.accounts.isEmpty, !store.isBusy, !hasPromptedForEmptyState else { return }
        hasPromptedForEmptyState = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.store.accounts.isEmpty, !self.store.isBusy else { return }
            self.addAccount()
        }
    }

    private func statusItemPresentation(for state: MenuBarMenuState) -> StatusItemRuntimePresentation {
        StatusItemRuntimePresentation(
            activeAccount: store.activeAccount,
            indicatorStyle: settings.statusBarIndicatorStyle,
            monochrome: settings.statusBarMonochrome,
            displayMode: state.effectiveStatusBarDisplayMode,
            progressAccentColor: settings.progressAccentColor
        )
    }

    private func presentProgressColorPanel() {
        recordMenuAction("chooseProgressAccentColor")
        let panel = NSColorPanel.shared
        panel.title = "Accent Color"
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(handleProgressColorPanelChanged(_:)))
        panel.color = settings.progressAccentColor
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc
    private func handleProgressColorPanelChanged(_ sender: NSColorPanel) {
        settings.progressAccentColor = sender.color.withAlphaComponent(1)
    }

    private func handleStatusItemRuntimeEvent(_ event: StatusItemRuntime.Event) {
        defer {
            recordValidationSnapshot(for: menuState())
        }

        switch event {
        case .hoverEntered:
            recordValidationEvent(
                "status_item_hover_entered",
                step: "hover_enter",
                invariantIds: Self.hoverInvariantIDs
            )
        case .hoverExitScheduled:
            recordValidationEvent(
                "status_item_hover_exit_scheduled",
                step: "hover_exit_schedule",
                invariantIds: Self.hoverInvariantIDs
            )
        case .hoverExited:
            recordValidationEvent(
                "status_item_hover_exited",
                step: "hover_exit",
                invariantIds: Self.hoverInvariantIDs
            )
        case .titleBecameVisible(let displayedTitle):
            recordValidationEvent(
                "status_item_title_became_visible",
                step: "hover_title_visible",
                invariantIds: Self.hoverInvariantIDs,
                payload: ["displayedTitle": displayedTitle ?? ""]
            )
        case .titleHidden:
            recordValidationEvent(
                "status_item_title_hidden",
                step: "hover_title_hidden",
                invariantIds: Self.hoverInvariantIDs
            )
        }
    }
}
