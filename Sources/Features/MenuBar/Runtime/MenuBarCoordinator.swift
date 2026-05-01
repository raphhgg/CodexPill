import AppKit
import Observation
import OSLog

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
    private static let shortcutRevealInvariantIDs = ["status_bar.reveal_shortcut.temporarily_shows_label"]
    private static let switchInvariantIDs = ["accounts.switch_account.menu_action_changes_active_account"]
    private static let addAccountNameDialogInvariantIDs = [
        "accounts.add_account.name_dialog_presented",
        "accounts.add_account.name_dialog_cancelled",
        "accounts.add_account.cancel_keeps_account_state"
    ]
    private static let scheduledRefreshInvariantIDs = ["accounts.scheduled_refresh.requested_and_completed"]

    private let statusItemRuntime: StatusItemRuntime
    private let shortcutRuntime: GlobalShortcutRuntime
    private let store: MenuBarAccountsStore
    private let settings: CodexPillSettingsStore
    private let menuDisplaySettings: MenuDisplaySettingsStore
    private let statusItemSettings: StatusItemSettingsStore
    private let remoteHostClient: RemoteHostClient
    private let cliProcessInspector: CodexCLIProcessInspector
    private let alertPresenter: AlertPresenter
    private let panelPresenter: PanelPresenter
    private let shortcutCapturePanelPresenter: ShortcutCapturePanelPresenter
    private let alertFactory: MenuBarAlertFactory
    private let notificationStateStore: AccountAvailabilityNotificationStore
    private let notificationDelivery: AccountAvailabilityNotifier
    private let applicationActivator: ApplicationActivator
    private let notificationSettingsLauncher: NotificationSettingsLauncher
    private let validationSink: MenuBarValidationSink?
    private let validationScenario: String?
    private let sealValidationRun: CodexPillSealValidationRun?
    private let allowsEmptyStatePrompt: Bool
    private let remoteHostRuntime: RemoteHostRuntime
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
    private var activeIsolatedAddAccountSession: IsolatedAddAccountSignInSession?
    private lazy var notificationWorkflow = MenuBarNotificationWorkflow(
        stateStore: notificationStateStore,
        delivery: notificationDelivery,
        applicationActivator: applicationActivator,
        settingsLauncher: notificationSettingsLauncher,
        scheduleRefresh: { [weak self] date in
            self?.scheduleNotificationEvaluation(at: date)
        },
        presentLocalSwitch: { [weak self] resolution in
            self?.presentNotificationDrivenLocalSwitch(resolution: resolution)
        },
        presentRemoteSwitch: { [weak self] resolution, hostDestination in
            self?.presentNotificationDrivenRemoteSwitch(
                resolution: resolution,
                hostDestination: hostDestination
            )
        },
        rebuildMenu: { [weak self] in
            self?.rebuildMenu()
        }
    )
    private lazy var hostActionCoordinator = MenuBarHostActionCoordinator(
        store: store,
        settings: settings,
        remoteHostClient: remoteHostClient,
        remoteHostRuntime: remoteHostRuntime,
        alertPresenter: alertPresenter,
        panelPresenter: panelPresenter,
        alertFactory: alertFactory,
        sealValidationRun: sealValidationRun,
        recordMenuAction: { [weak self] name, payload in
            self?.recordMenuAction(name, payload: payload)
        },
        recordValidationEvent: { [weak self] name, step, invariantIds, payload in
            self?.recordValidationEvent(
                name,
                step: step,
                invariantIds: invariantIds,
                payload: payload
            )
        },
        rebuildMenu: { [weak self] in
            self?.rebuildMenu()
        },
        cancelMenuTracking: { [weak self] in
            self?.statusItemRuntime.menu?.cancelTracking()
        },
        setLastSwitchTargetName: { [weak self] name in
            self?.lastSwitchTargetName = name
        }
    )

    init(
        statusItemRuntime: StatusItemRuntime,
        shortcutRuntime: GlobalShortcutRuntime? = nil,
        store: MenuBarAccountsStore,
        settings: CodexPillSettingsStore,
        remoteHostClient: RemoteHostClient = UnavailableRemoteHostClient(),
        cliProcessInspector: CodexCLIProcessInspector = CodexCLIProcessInspector(),
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter? = nil,
        shortcutCapturePanelPresenter: ShortcutCapturePanelPresenter? = nil,
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
        self.shortcutRuntime = shortcutRuntime ?? GlobalShortcutRuntime()
        self.store = store
        self.settings = settings
        self.menuDisplaySettings = settings.menuDisplaySettings
        self.statusItemSettings = settings.statusItemSettings
        self.remoteHostClient = remoteHostClient
        self.cliProcessInspector = cliProcessInspector
        self.alertPresenter = alertPresenter
        self.panelPresenter = panelPresenter ?? SystemPanelPresenter()
        self.shortcutCapturePanelPresenter = shortcutCapturePanelPresenter ?? SystemShortcutCapturePanelPresenter()
        self.alertFactory = alertFactory
        self.notificationStateStore = AccountAvailabilityNotificationStore(
            preferences: settings.notificationPreferences,
            stateStore: settings.notificationState
        )
        self.notificationDelivery = notificationDelivery
        self.applicationActivator = applicationActivator
        self.notificationSettingsLauncher = notificationSettingsLauncher
        self.validationSink = validationSink
        self.validationScenario = validationScenario
        self.sealValidationRun = sealValidationRun ?? CodexPillSealValidationConfiguration.makeRun()
        self.allowsEmptyStatePrompt = allowsEmptyStatePrompt
        self.remoteHostRuntime = RemoteHostRuntime(
            settings: settings.remoteHostSettings,
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
        shortcutRuntime.onShortcut = { [weak self] in
            self?.statusItemRuntime.revealTitleTemporarily(duration: 3)
        }
        restorePersistedRemoteHostState()
        statusItemRuntime.start(presentation: statusItemPresentation(for: menuState()))
        lastObservedActiveAccountID = store.activeAccountID
        lastObservedActiveAccountName = store.activeAccount?.name
        notificationWorkflow.start(with: menuState())
        startObservingStore()
        startObservingSettings()
        rebuildMenu()
        scheduleAutoRefresh()
        syncBackgroundState()
        refreshRemoteHostStateIfNeeded()
        registerRevealShortcutFromSettings()
    }

    func invalidate() {
        autoRefreshTimer?.invalidate()
        wakeRefreshTask?.cancel()
        notificationWaitTask?.cancel()
        cancelActiveIsolatedAddAccountSession()
        sealValidationRun?.cancelIfUnfinished()
        shortcutRuntime.invalidate()
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

        let state = menuState()
        let shouldSignOutLocalAccount = state.isAccountActiveLocally(account)
        let activeRemoteHosts = state.activeRemoteHosts(for: account)
        let request = alertFactory.makeRemoveAccountRequest(
            accountName: account.name,
            activeTargets: removeAccountActiveTargetNames(
                signsOutLocalAccount: shouldSignOutLocalAccount,
                remoteHosts: activeRemoteHosts
            )
        )

        guard alertPresenter.presentConfirmation(request) else { return }
        Task { @MainActor [weak self] in
            await self?.removeSavedAccount(
                account,
                signOutLocalAccount: shouldSignOutLocalAccount,
                remoteHosts: activeRemoteHosts
            )
        }
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
        menuDisplaySettings.refreshIntervalMinutes = minutes
    }

    @objc
    func selectVisibleInactiveAccountCount(_ sender: NSMenuItem) {
        recordMenuAction("selectVisibleInactiveAccountCount")
        guard let count = sender.representedObject as? Int else { return }
        menuDisplaySettings.visibleInactiveAccountCount = count
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
        statusItemSettings.statusBarIndicatorStyle = style
    }

    @objc
    func toggleStatusBarMonochrome(_ sender: NSMenuItem) {
        recordMenuAction("toggleStatusBarMonochrome")
        statusItemSettings.statusBarMonochrome.toggle()
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
            statusItemSettings.statusBarDisplayMode = .iconOnly
            return
        }
        statusItemSettings.statusBarDisplayMode = mode
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
        NSColorPanel.shared.color = statusItemSettings.progressAccentColor
    }

    @objc
    func togglePacingMarkers(_ sender: NSMenuItem) {
        recordMenuAction("togglePacingMarkers")
        statusItemSettings.pacingMarkersEnabled.toggle()
    }

    @objc
    func configureRevealStatusItemTitleShortcut(_ sender: NSMenuItem) {
        recordMenuAction("configureRevealStatusItemTitleShortcut")
        let previousShortcut = statusItemSettings.revealStatusItemTitleShortcut
        try? shortcutRuntime.apply(shortcut: nil)

        switch shortcutCapturePanelPresenter.presentShortcutCapture(
            currentShortcut: statusItemSettings.revealStatusItemTitleShortcut
        ) {
        case .cancelled:
            try? shortcutRuntime.apply(shortcut: previousShortcut)
            return
        case .saved(let shortcut):
            do {
                try shortcutRuntime.apply(shortcut: shortcut)
                statusItemSettings.revealStatusItemTitleShortcut = shortcut
            } catch {
                try? shortcutRuntime.apply(shortcut: previousShortcut)
                alertPresenter.presentInfo(
                    alertFactory.makeErrorRequest(
                        message: error.localizedDescription
                    )
                )
            }
        }
        rebuildMenu()
    }

    @objc
    func toggleNotificationsWhenBlocked(_ sender: NSMenuItem) {
        recordMenuAction("toggleNotificationsWhenBlocked")
        notificationWorkflow.handleNotificationToggle(enabled: \.whenBlockedEnabled)
    }

    @objc
    func toggleNotificationsWhenOut(_ sender: NSMenuItem) {
        recordMenuAction("toggleNotificationsWhenOut")
        notificationWorkflow.handleNotificationToggle(enabled: \.whenOutEnabled)
    }

    @objc
    func enableNotifications(_ sender: NSMenuItem) {
        recordMenuAction("enableNotifications")
        notificationWorkflow.enableNotifications()
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
        guard let payload = sender.representedObject as? HostAccountMenuItemPayload else { return }
        hostActionCoordinator.switchAccountOnHost(
            accountID: payload.accountID,
            hostDestination: payload.hostDestination
        )
    }

    @objc
    func addHost(_ sender: NSMenuItem) {
        hostActionCoordinator.addHost()
    }

    @objc
    func removeHost(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? HostSelectionMenuItemPayload else { return }
        hostActionCoordinator.removeHost(hostDestination: payload.hostDestination)
    }

    @objc
    func reverifyHost(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? HostSelectionMenuItemPayload else { return }
        hostActionCoordinator.reverifyHost(hostDestination: payload.hostDestination)
    }

    func reverifyHost(hostDestination: String) {
        hostActionCoordinator.reverifyHost(hostDestination: hostDestination)
    }

    @objc
    func adoptDetectedRemoteAccount(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? HostAccountMenuItemPayload else { return }
        hostActionCoordinator.adoptDetectedRemoteAccount(
            hostDestination: payload.hostDestination,
            accountID: payload.accountID
        )
    }

    func adoptDetectedRemoteAccount(hostDestination: String, accountID: UUID) {
        hostActionCoordinator.adoptDetectedRemoteAccount(
            hostDestination: hostDestination,
            accountID: accountID
        )
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
            visibleInactiveAccountCount: menuDisplaySettings.visibleInactiveAccountCount,
            visibleInactiveAccountCountOptions: menuDisplaySettings.visibleInactiveAccountCountOptions,
            refreshIntervalMinutes: menuDisplaySettings.refreshIntervalMinutes,
            refreshIntervalOptions: settings.refreshIntervalOptions,
            statusBarMonochrome: statusItemSettings.statusBarMonochrome,
            statusBarIndicatorStyle: statusItemSettings.statusBarIndicatorStyle,
            statusBarDisplayMode: statusItemSettings.statusBarDisplayMode,
            revealStatusItemTitleShortcut: statusItemSettings.revealStatusItemTitleShortcut,
            progressAccentColor: statusItemSettings.progressAccentColor,
            pacingMarkersEnabled: statusItemSettings.pacingMarkersEnabled,
            hasCustomProgressAccentColor: settings.hasCustomProgressAccentColor,
            isBusy: store.isBusy,
            statusMessage: store.statusMessage,
            notificationsWhenBlockedEnabled: notificationWorkflow.whenBlockedEnabled,
            notificationsWhenOutEnabled: notificationWorkflow.whenOutEnabled,
            notificationAuthorizationState: notificationWorkflow.authorizationState,
            showsPacingPrototypeMenu: validationScenario == "live-pacing-prototypes"
        )
    }

    private func registerRevealShortcutFromSettings() {
        do {
            try shortcutRuntime.apply(shortcut: statusItemSettings.revealStatusItemTitleShortcut)
        } catch {
            alertPresenter.presentInfo(
                alertFactory.makeErrorRequest(
                    message: error.localizedDescription
                )
            )
        }
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
        notificationWorkflow.handleResponse(
            actionIdentifier: actionIdentifier,
            userInfo: userInfo,
            state: menuState()
        )
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
        let interval = AppRuntimeEnvironment.validationAutoRefreshIntervalSeconds() ?? TimeInterval(menuDisplaySettings.refreshIntervalMinutes * 60)
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
        notificationWorkflow.evaluate(using: state)
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
            notificationWorkflow.markAccountActivated(currentActiveAccountID)
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
            _ = menuDisplaySettings.refreshIntervalMinutes
            _ = statusItemSettings.statusBarIndicatorStyle
            _ = statusItemSettings.statusBarMonochrome
            _ = statusItemSettings.statusBarDisplayMode
            _ = menuDisplaySettings.visibleInactiveAccountCount
            _ = statusItemSettings.progressAccentColor
            _ = statusItemSettings.pacingMarkersEnabled
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
        notificationWorkflow.evaluate(using: state)
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

    private func removeSavedAccount(
        _ account: CodexAccount,
        signOutLocalAccount: Bool,
        remoteHosts: [RemoteHostMenuState]
    ) async {
        do {
            try await signOutRemoteHosts(remoteHosts)
            await store.removeSavedAccount(account, signOutLocalAccount: signOutLocalAccount)
            presentPendingErrorIfNeeded()
        } catch {
            alertPresenter.presentInfo(alertFactory.makeErrorRequest(message: error.localizedDescription))
        }
        rebuildMenu()
    }

    private func signOutRemoteHosts(_ remoteHosts: [RemoteHostMenuState]) async throws {
        for remoteHostState in remoteHosts {
            guard let remoteHost = settings.remoteHostState(for: remoteHostState.destination)?.host else {
                throw RemoteHostClientError.commandFailed("Remote host \(remoteHostState.name) is no longer configured.")
            }
            try await remoteHostClient.signOut(on: remoteHost)
            try await remoteHostClient.refreshCodexAppServer(on: remoteHost)
            remoteHostRuntime.applySignOut(on: remoteHost)
        }
    }

    private func removeAccountActiveTargetNames(
        signsOutLocalAccount: Bool,
        remoteHosts: [RemoteHostMenuState]
    ) -> [String] {
        var targets: [String] = []
        if signsOutLocalAccount {
            targets.append("This Mac")
        }
        targets.append(contentsOf: remoteHosts.map(\.name))
        return targets
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
            indicatorStyle: statusItemSettings.statusBarIndicatorStyle,
            monochrome: statusItemSettings.statusBarMonochrome,
            displayMode: state.effectiveStatusBarDisplayMode,
            progressAccentColor: statusItemSettings.progressAccentColor
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
        panel.color = statusItemSettings.progressAccentColor
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc
    private func handleProgressColorPanelChanged(_ sender: NSColorPanel) {
        statusItemSettings.progressAccentColor = sender.color.withAlphaComponent(1)
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
        case .shortcutRevealStarted:
            recordValidationEvent(
                "status_item_shortcut_reveal_started",
                step: "shortcut_reveal_start",
                invariantIds: Self.shortcutRevealInvariantIDs
            )
        case .shortcutRevealEnded:
            recordValidationEvent(
                "status_item_shortcut_reveal_ended",
                step: "shortcut_reveal_end",
                invariantIds: Self.shortcutRevealInvariantIDs
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
