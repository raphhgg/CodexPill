import AppKit
import Observation
import OSLog

private let menuBarCoordinatorLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "MenuBarCoordinator")

private enum ProgressAccentColorTarget {
    case session
    case weekly
}

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
    private let statusItemRuntime: StatusItemRuntime
    private let shortcutRuntime: GlobalShortcutRuntime
    private let store: MenuBarAccountsStore
    private let settings: CodexPillSettingsStore
    private let menuDisplaySettings: MenuDisplaySettingsStore
    private let statusItemSettings: StatusItemSettingsStore
    private let remoteHostConnectionChecker: RemoteHostConnectionChecking
    private let remoteHostAccountSignerOut: RemoteHostAccountSigningOut
    private let remoteHostAppServerRefresher: RemoteHostCodexAppServerRefreshing
    private let cliProcessInspector: CodexCLIProcessInspector
    private let alertPresenter: AlertPresenter
    private let panelPresenter: PanelPresenter
    private let shortcutCapturePanelPresenter: ShortcutCapturePanelPresenter
    private let alertFactory: MenuBarAlertFactory
    private let notificationStateStore: AccountAvailabilityNotificationStore
    private let notificationDelivery: AccountAvailabilityNotifier
    private let applicationActivator: ApplicationActivator
    private let notificationSettingsLauncher: NotificationSettingsLauncher
    private let loginItemController: LoginItemControlling
    private let loginItemsSettingsLauncher: LoginItemsSettingsLaunching
    private let diagnosticReportPresenter: DiagnosticReportPresenting
    private let diagnosticEventRecorder: DiagnosticEventRecorder
    private let validationObserver: MenuBarValidationObserver
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
    private var lastObservedActiveAccountID: UUID?
    private var lastObservedActiveAccountName: String?
    private var progressAccentColorTarget: ProgressAccentColorTarget = .weekly
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
        connectionChecker: remoteHostConnectionChecker,
        remoteHostRuntime: remoteHostRuntime,
        alertPresenter: alertPresenter,
        panelPresenter: panelPresenter,
        alertFactory: alertFactory,
        validationObserver: validationObserver,
        recordMenuAction: { [weak self] name, payload in
            self?.recordMenuAction(name, payload: payload)
        },
        rebuildMenu: { [weak self] in
            self?.rebuildMenu()
        },
        cancelMenuTracking: { [weak self] in
            self?.statusItemRuntime.menu?.cancelTracking()
        }
    )

    init(
        statusItemRuntime: StatusItemRuntime,
        shortcutRuntime: GlobalShortcutRuntime? = nil,
        store: MenuBarAccountsStore,
        settings: CodexPillSettingsStore,
        remoteHostMenuOperations: (
            RemoteHostConnectionChecking
            & RemoteHostAccountStatusReading
            & RemoteHostAccountSigningOut
            & RemoteHostCodexAppServerRefreshing
        )? = nil,
        remoteHostConnectionChecker: RemoteHostConnectionChecking = UnavailableRemoteHostClient(),
        remoteHostAccountStatusReader: RemoteHostAccountStatusReading = UnavailableRemoteHostClient(),
        remoteHostAccountSignerOut: RemoteHostAccountSigningOut = UnavailableRemoteHostClient(),
        remoteHostAppServerRefresher: RemoteHostCodexAppServerRefreshing = UnavailableRemoteHostClient(),
        cliProcessInspector: CodexCLIProcessInspector = CodexCLIProcessInspector(),
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter? = nil,
        shortcutCapturePanelPresenter: ShortcutCapturePanelPresenter? = nil,
        alertFactory: MenuBarAlertFactory = MenuBarAlertFactory(),
        notificationDelivery: AccountAvailabilityNotifier = AccountAvailabilityNotificationCenter(),
        applicationActivator: ApplicationActivator = NSApplicationActivator(),
        notificationSettingsLauncher: NotificationSettingsLauncher = SystemNotificationSettingsLauncher(),
        loginItemController: LoginItemControlling = SystemLoginItemController(),
        loginItemsSettingsLauncher: LoginItemsSettingsLaunching = SystemLoginItemsSettingsLauncher(),
        diagnosticReportPresenter: DiagnosticReportPresenting? = nil,
        diagnosticEventRecorder: DiagnosticEventRecorder? = nil,
        validationSink: MenuBarValidationSink? = nil,
        validationScenario: String? = MenuBarValidationConfiguration.scenario(),
        validationObserver: MenuBarValidationObserver? = nil,
        allowsEmptyStatePrompt: Bool = true
    ) {
        self.statusItemRuntime = statusItemRuntime
        self.shortcutRuntime = shortcutRuntime ?? GlobalShortcutRuntime()
        self.store = store
        self.settings = settings
        self.menuDisplaySettings = settings.menuDisplaySettings
        self.statusItemSettings = settings.statusItemSettings
        self.remoteHostConnectionChecker = remoteHostMenuOperations ?? remoteHostConnectionChecker
        let remoteHostAccountStatusReader = remoteHostMenuOperations ?? remoteHostAccountStatusReader
        self.remoteHostAccountSignerOut = remoteHostMenuOperations ?? remoteHostAccountSignerOut
        self.remoteHostAppServerRefresher = remoteHostMenuOperations ?? remoteHostAppServerRefresher
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
        self.loginItemController = loginItemController
        self.loginItemsSettingsLauncher = loginItemsSettingsLauncher
        self.diagnosticReportPresenter = diagnosticReportPresenter ?? SystemDiagnosticReportPresenter()
        self.diagnosticEventRecorder = diagnosticEventRecorder ?? DiagnosticEventRecorder()
        self.validationObserver = validationObserver ?? MenuBarValidationObserver(
            sink: validationSink,
            scenario: validationScenario
        )
        self.allowsEmptyStatePrompt = allowsEmptyStatePrompt
        self.remoteHostRuntime = RemoteHostRuntime(
            settings: settings.remoteHostSettings,
            accountStatusReader: remoteHostAccountStatusReader,
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
        validationObserver.cancelIfUnfinished()
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
        validationObserver.recordAddAccountMenuAction(
            activeAccount: store.activeAccount,
            savedAccounts: store.accounts
        )
        menuBarCoordinatorLogger.log("addAccount action invoked")
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        menuBarCoordinatorLogger.log("Running CLI sessions before add-account: \(runningCLISessions, privacy: .public)")

        let request = alertFactory.makeAddAccountRequest(runningCLISessions: runningCLISessions)
        validationObserver.recordAddAccountPromptPresented(runningCLISessions: runningCLISessions)

        menuBarCoordinatorLogger.log("Presenting add-account confirmation alert")
        guard let name = alertPresenter.presentTextInput(request) else {
            menuBarCoordinatorLogger.log("Add-account flow cancelled from alert")
            validationObserver.recordAddAccountPromptCancelled(
                activeAccount: store.activeAccount,
                savedAccounts: store.accounts
            )
            return
        }
        validationObserver.recordAddAccountPromptConfirmed(enteredName: name)

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
    func chooseSessionProgressAccentColor(_ sender: NSMenuItem) {
        recordMenuAction("chooseSessionProgressAccentColor")
        presentProgressColorPanel(target: .session)
    }

    @objc
    func chooseWeeklyProgressAccentColor(_ sender: NSMenuItem) {
        recordMenuAction("chooseWeeklyProgressAccentColor")
        presentProgressColorPanel(target: .weekly)
    }

    @objc
    func resetProgressAccentColor(_ sender: NSMenuItem) {
        recordMenuAction("resetProgressAccentColor")
        settings.resetProgressAccentColor()
        NSColorPanel.shared.color = resolvedProgressAccentColor(for: progressAccentColorTarget)
    }

    @objc
    func selectUsageBarDisplayMode(_ sender: NSMenuItem) {
        recordMenuAction("selectUsageBarDisplayMode")
        guard
            let rawValue = sender.representedObject as? String,
            let mode = UsageBarDisplayMode(rawValue: rawValue)
        else {
            return
        }
        statusItemSettings.usageBarDisplayMode = mode
    }

    @objc
    func selectUsageBarLayout(_ sender: NSMenuItem) {
        recordMenuAction("selectUsageBarLayout")
        guard
            let rawValue = sender.representedObject as? String,
            let layout = UsageBarLayout(rawValue: rawValue)
        else {
            return
        }
        statusItemSettings.usageBarLayout = layout
    }

    @objc
    func selectOtherAccountsDisplayMode(_ sender: NSMenuItem) {
        recordMenuAction("selectOtherAccountsDisplayMode")
        guard
            let rawValue = sender.representedObject as? String,
            let mode = OtherAccountsDisplayMode(rawValue: rawValue)
        else {
            return
        }
        statusItemSettings.otherAccountsDisplayMode = mode
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
        diagnosticEventRecorder.recordSwitchAccount(targetAccountID: account.id)
        validationObserver.recordSwitchAccountMenuAction(
            targetAccount: account,
            activeAccount: store.activeAccount,
            savedAccounts: store.accounts
        )
        requestSwitch(to: account)
    }

    @objc
    func switchAccountOnHost(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? HostAccountMenuItemPayload else { return }
        diagnosticEventRecorder.recordRemoteHostSwitch(
            targetAccountID: payload.accountID,
            hostDestination: payload.hostDestination
        )
        hostActionCoordinator.switchAccountOnHost(
            accountID: payload.accountID,
            hostDestination: payload.hostDestination
        )
    }

    @objc
    func addHost(_ sender: NSMenuItem) {
        recordMenuAction("addHost")
        hostActionCoordinator.addHost()
    }

    @objc
    func removeHost(_ sender: NSMenuItem) {
        recordMenuAction("removeHost")
        guard let payload = sender.representedObject as? HostSelectionMenuItemPayload else { return }
        hostActionCoordinator.removeHost(hostDestination: payload.hostDestination)
    }

    @objc
    func reverifyHost(_ sender: NSMenuItem) {
        recordMenuAction("reverifyHost")
        guard let payload = sender.representedObject as? HostSelectionMenuItemPayload else { return }
        hostActionCoordinator.reverifyHost(hostDestination: payload.hostDestination)
    }

    func reverifyHost(hostDestination: String) {
        hostActionCoordinator.reverifyHost(hostDestination: hostDestination)
    }

    @objc
    func adoptDetectedRemoteAccount(_ sender: NSMenuItem) {
        recordMenuAction("adoptDetectedRemoteAccount")
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
    func exportDiagnosticReport() {
        guard alertPresenter.presentConfirmation(alertFactory.makeDiagnosticsExportRequest()) else {
            return
        }

        recordMenuAction("exportDiagnosticReport")
        let report = DiagnosticReportBuilder(
            appMetadata: .current(),
            systemMetadata: .current()
        ).makeReport(
            state: menuState(),
            events: diagnosticEventRecorder.events
        )

        do {
            _ = try diagnosticReportPresenter.export(report: report)
        } catch {
            alertPresenter.presentInfo(
                alertFactory.makeErrorRequest(message: "Diagnostic report export failed.")
            )
        }
    }

    @objc
    func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        recordMenuAction("toggleLaunchAtLogin")
        switch loginItemController.state() {
        case .enabled:
            setLaunchAtLoginEnabled(false)
        case .disabled:
            guard alertPresenter.presentConfirmation(alertFactory.makeEnableLaunchAtLoginRequest()) else {
                return
            }
            setLaunchAtLoginEnabled(true)
        case .requiresApproval:
            openLoginItemsSettings(sender)
        case .unavailable:
            openLoginItemsSettings(sender)
        }
    }

    @objc
    func openLoginItemsSettings(_ sender: NSMenuItem) {
        recordMenuAction("openLoginItemsSettings")
        if !loginItemsSettingsLauncher.openLoginItemsSettings() {
            alertPresenter.presentInfo(
                alertFactory.makeErrorRequest(message: "Could not open System Settings.")
            )
        }
    }

    @objc
    func quitApp() {
        recordMenuAction("quitApp")
        NSApplication.shared.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusItemRuntime.handleMenuWillOpen()
        validationObserver.recordMenuOpened(menuItemCount: statusItemRuntime.menuItemCount)
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
            sessionProgressAccentColor: statusItemSettings.sessionProgressAccentColor
                .resolvedStatusItemAccentColor(default: StatusBarProgressColorDefaults.sessionAccent),
            progressAccentColor: statusItemSettings.progressAccentColor
                .resolvedStatusItemAccentColor(default: StatusBarProgressColorDefaults.weeklyAccent),
            usageBarDisplayMode: statusItemSettings.usageBarDisplayMode,
            usageBarLayout: statusItemSettings.usageBarLayout,
            otherAccountsDisplayMode: statusItemSettings.otherAccountsDisplayMode,
            pacingMarkersEnabled: statusItemSettings.pacingMarkersEnabled,
            hasCustomProgressAccentColor: settings.hasCustomProgressAccentColor,
            isBusy: store.isBusy,
            statusMessage: store.statusMessage,
            notificationsWhenBlockedEnabled: notificationWorkflow.whenBlockedEnabled,
            notificationsWhenOutEnabled: notificationWorkflow.whenOutEnabled,
            notificationAuthorizationState: notificationWorkflow.authorizationState,
            loginItemState: loginItemController.state(),
            showsPacingPrototypeMenu: validationObserver.showsPacingPrototypeMenu
        )
    }

    private func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try loginItemController.setEnabled(isEnabled)
        } catch {
            alertPresenter.presentInfo(
                alertFactory.makeErrorRequest(
                    message: "Could not update Launch at Login. Open System Settings and try again."
                )
            )
        }
        rebuildMenu()
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
        validationObserver.recordSwitchConfirmationPresented(targetAccount: account)
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        let request = alertFactory.makeSwitchAccountRequest(accountName: account.name, runningCLISessions: runningCLISessions)

        let accepted = alertPresenter.presentConfirmation(request)
        validationObserver.recordSwitchConfirmationResult(accepted: accepted, targetAccount: account)
        guard accepted else { return }
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
            beginLocalSwitch(to: account)
        case .none:
            break
        }
    }

    private func handleAddAccountFailure(_ step: AccountActionFlow.AddAccountFailureStep) {
        _ = store.consumePendingErrorMessage()

        switch step {
        case .showSignInFailure(let outcome):
            alertPresenter.presentInfo(alertFactory.makeAddAccountSignInFailureRequest(outcome: outcome))
        case .offerSignInRetry(let outcome, let retryName):
            let request = alertFactory.makeAddAccountSignInRetryRequest(outcome: outcome)
            guard alertPresenter.presentConfirmation(request) else { return }
            Task { @MainActor [weak self] in
                await self?.beginIsolatedAddAccount(named: retryName)
            }
        case .showError(let message):
            alertPresenter.presentInfo(alertFactory.makeErrorRequest(message: message))
        case .showEmptyNameAndRetry(let message):
            alertPresenter.presentInfo(alertFactory.makeErrorRequest(message: message))
            addAccount()
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
        validationObserver.recordSwitchWorkflowStarted(targetAccount: account)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let didRefreshAfterSwitch = await self.store.switchToAccount(account)
            if self.store.activeAccountID == account.id {
                self.validationObserver.recordCodexRelaunchRequested(targetAccount: account)
            }
            self.validationObserver.clearPendingSwitchIfTargetDidNotActivate(
                targetID: account.id,
                activeAccountID: self.store.activeAccountID
            )
            if didRefreshAfterSwitch {
                self.validationObserver.recordPostSwitchRefreshCompleted(
                    targetAccount: account,
                    activeAccount: self.store.activeAccount,
                    savedAccounts: self.store.accounts
                )
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
        diagnosticEventRecorder.recordMenuAction(name)
        validationObserver.recordMenuAction(
            name,
            payload: payload,
            state: menuState(),
            menu: statusItemRuntime.menu,
            statusItemState: statusItemRuntime.snapshotState()
        )
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
                self.validationObserver.recordScheduledRefreshRequested(
                    accountName: activeAccount.name,
                    activeAccount: activeAccount,
                    savedAccounts: self.store.accounts
                )
                let outcome = await store.refreshAccountData(for: activeAccount)
                let error: String?
                switch outcome {
                case .refreshed:
                    error = nil
                    self.diagnosticEventRecorder.recordRefresh(resultCategory: "refreshed")
                case .failed(let message):
                    error = message
                    self.diagnosticEventRecorder.recordRefresh(resultCategory: "failed")
                }
                self.validationObserver.recordScheduledRefreshResult(
                    accountName: activeAccount.name,
                    error: error,
                    activeAccount: self.store.activeAccount,
                    savedAccounts: self.store.accounts,
                    menuSnapshot: MenuBarValidationSupport.makeSnapshot(
                        state: self.menuState(),
                        menu: self.statusItemRuntime.menu,
                        statusItemState: self.statusItemRuntime.snapshotState()
                    )
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

        _ = validationObserver.recordActiveAccountTransitionIfNeeded(
            previousName: lastObservedActiveAccountName,
            currentID: currentActiveAccountID,
            currentName: currentActiveAccountName,
            activeAccount: store.activeAccount,
            savedAccounts: store.accounts
        )
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
            _ = statusItemSettings.sessionProgressAccentColor
            _ = statusItemSettings.progressAccentColor
            _ = statusItemSettings.usageBarDisplayMode
            _ = statusItemSettings.usageBarLayout
            _ = statusItemSettings.otherAccountsDisplayMode
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
            try await remoteHostAccountSignerOut.signOut(on: remoteHost)
            try await remoteHostAppServerRefresher.refreshCodexAppServer(on: remoteHost)
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
        validationObserver.recordSnapshot(
            state: state,
            menu: statusItemRuntime.menu,
            statusItemState: statusItemRuntime.snapshotState()
        )
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
            usageBarDisplayMode: statusItemSettings.usageBarDisplayMode,
            sessionProgressAccentColor: statusItemSettings.sessionProgressAccentColor
                .resolvedStatusItemAccentColor(default: StatusBarProgressColorDefaults.sessionAccent),
            weeklyProgressAccentColor: statusItemSettings.progressAccentColor
                .resolvedStatusItemAccentColor(default: StatusBarProgressColorDefaults.weeklyAccent)
        )
    }

    private func presentProgressColorPanel(target: ProgressAccentColorTarget) {
        progressAccentColorTarget = target
        let panel = NSColorPanel.shared
        panel.title = target == .session ? "Accent Color Session" : "Accent Color Weekly"
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(handleProgressColorPanelChanged(_:)))
        panel.color = resolvedProgressAccentColor(for: target)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc
    private func handleProgressColorPanelChanged(_ sender: NSColorPanel) {
        let color = sender.color.withAlphaComponent(1)
        switch progressAccentColorTarget {
        case .session:
            statusItemSettings.sessionProgressAccentColor = color.isEqualToStatusItemAccentColor(StatusBarProgressColorDefaults.sessionAccent)
                ? nil
                : StatusItemAccentColor(nsColor: color)
        case .weekly:
            statusItemSettings.progressAccentColor = color.isEqualToStatusItemAccentColor(StatusBarProgressColorDefaults.weeklyAccent)
                ? nil
                : StatusItemAccentColor(nsColor: color)
        }
    }

    private func resolvedProgressAccentColor(for target: ProgressAccentColorTarget) -> NSColor {
        switch target {
        case .session:
            return statusItemSettings.sessionProgressAccentColor
                .resolvedStatusItemAccentColor(default: StatusBarProgressColorDefaults.sessionAccent)
        case .weekly:
            return statusItemSettings.progressAccentColor
                .resolvedStatusItemAccentColor(default: StatusBarProgressColorDefaults.weeklyAccent)
        }
    }

    private func handleStatusItemRuntimeEvent(_ event: StatusItemRuntime.Event) {
        defer {
            recordValidationSnapshot(for: menuState())
        }

        validationObserver.recordStatusItemRuntimeEvent(event)
    }
}
