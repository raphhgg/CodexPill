import AppKit
import Observation
import OSLog

private let menuBarCoordinatorLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "MenuBarCoordinator")

typealias MenuBarRemoteHostOperations =
    RemoteHostConnectionChecking
    & RemoteHostAccountStatusReading
    & RemoteHostAccountSigningOut
    & RemoteHostCodexAppServerRefreshing

@MainActor
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
    private let accountsController: MenuBarAccounts
    private let menuDisplaySettings: MenuDisplaySettingsStore
    private let statusItemSettings: StatusItemSettingsStore
    private let remoteHostSettings: RemoteHostSettingsStore
    private let notificationPreferences: NotificationPreferencesStore
    private let tokenUsagePreferences: TokenUsagePreferencesStore
    private let remoteHostOperations: MenuBarRemoteHostOperations
    private let cliProcessInspector: CodexCLIProcessInspector
    private let alertPresenter: AlertPresenter
    private let panelPresenter: PanelPresenter
    private let shortcutCapturePanelPresenter: ShortcutCapturePanelPresenter
    private let alertFactory = MenuBarAlertFactory()
    private let notificationStateStore: AccountAvailabilityNotificationStore
    private let notificationDelivery: AccountAvailabilityNotifier
    private let applicationActivator: ApplicationActivator
    private let notificationSettingsLauncher: NotificationSettingsLauncher
    private let loginItemController: LoginItemControlling
    private let loginItemsSettingsLauncher: LoginItemsSettingsLaunching
    private let diagnosticReportPresenter: DiagnosticReportPresenting
    private let diagnosticEventRecorder = DiagnosticEventRecorder()
    private let tokenUsageProvider: TokenUsageMenuProviding
    private let allowsEmptyStatePrompt: Bool
    private let autoRefreshIntervalOverride: TimeInterval?
    private let remoteHostRuntime: RemoteHostRuntime
    private let accountActionFlow = AccountActionFlow()
    private let menuBuilder = MenuBarMenuBuilder()
    private var autoRefreshTimer: Timer?
    private var colorPanelTarget: UsageColorTarget?
    private var wakeRefreshTask: Task<Void, Never>?
    private var notificationWaitTask: Task<Void, Never>?
    private let tasks = TrackedTasks()
    private var rebuildsMenuAfterClose = false
    private var rebuildsMenuBeforeOpen = false
    private var hasPromptedForEmptyState = false
    private var isObservingSettings = false
    private var isObservingStore = false
    private var lastObservedActiveAccountID: UUID?
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
    private lazy var tokenUsageRuntime = TokenUsageMenuRuntime(
        provider: tokenUsageProvider,
        onStateChange: { [weak self] _ in
            self?.rebuildMenuWhenSafe()
        }
    )
    private let providerUsageSources: [any UsageProviderSource]
    private let claudeCodeUsage: ClaudeCodeUsage?
    private lazy var providerUsageRuntime = ProviderUsageRuntime(
        sources: providerUsageSources,
        onChange: { [weak self] in
            self?.rebuildMenuWhenSafe()
        }
    )
    private lazy var hostActionCoordinator = MenuBarHostActionCoordinator(
        store: accountsController,
        settings: remoteHostSettings,
        connectionChecker: remoteHostOperations,
        remoteHostRuntime: remoteHostRuntime,
        alertPresenter: alertPresenter,
        panelPresenter: panelPresenter,
        alertFactory: alertFactory,
        recordMenuAction: { [weak self] name in
            self?.recordMenuAction(name)
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
        shortcutRuntime: GlobalShortcutRuntime,
        accountsController: MenuBarAccounts,
        menuDisplaySettings: MenuDisplaySettingsStore,
        statusItemSettings: StatusItemSettingsStore,
        remoteHostSettings: RemoteHostSettingsStore,
        notificationPreferences: NotificationPreferencesStore,
        notificationState: NotificationStateStore,
        tokenUsagePreferences: TokenUsagePreferencesStore,
        remoteHostOperations: MenuBarRemoteHostOperations,
        cliProcessInspector: CodexCLIProcessInspector,
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter,
        shortcutCapturePanelPresenter: ShortcutCapturePanelPresenter,
        notificationDelivery: AccountAvailabilityNotifier,
        applicationActivator: ApplicationActivator,
        notificationSettingsLauncher: NotificationSettingsLauncher,
        loginItemController: LoginItemControlling,
        loginItemsSettingsLauncher: LoginItemsSettingsLaunching,
        diagnosticReportPresenter: DiagnosticReportPresenting,
        tokenUsageProvider: TokenUsageMenuProviding,
        providerUsageSources: [any UsageProviderSource],
        claudeCodeUsage: ClaudeCodeUsage?,
        allowsEmptyStatePrompt: Bool,
        autoRefreshIntervalOverride: TimeInterval?
    ) {
        self.statusItemRuntime = statusItemRuntime
        self.shortcutRuntime = shortcutRuntime
        self.accountsController = accountsController
        self.menuDisplaySettings = menuDisplaySettings
        self.statusItemSettings = statusItemSettings
        self.remoteHostSettings = remoteHostSettings
        self.notificationPreferences = notificationPreferences
        self.tokenUsagePreferences = tokenUsagePreferences
        self.remoteHostOperations = remoteHostOperations
        self.cliProcessInspector = cliProcessInspector
        self.alertPresenter = alertPresenter
        self.panelPresenter = panelPresenter
        self.shortcutCapturePanelPresenter = shortcutCapturePanelPresenter
        self.notificationStateStore = AccountAvailabilityNotificationStore(
            preferences: notificationPreferences,
            stateStore: notificationState
        )
        self.notificationDelivery = notificationDelivery
        self.applicationActivator = applicationActivator
        self.notificationSettingsLauncher = notificationSettingsLauncher
        self.loginItemController = loginItemController
        self.loginItemsSettingsLauncher = loginItemsSettingsLauncher
        self.diagnosticReportPresenter = diagnosticReportPresenter
        self.tokenUsageProvider = tokenUsageProvider
        self.providerUsageSources = providerUsageSources
        self.claudeCodeUsage = claudeCodeUsage
        self.allowsEmptyStatePrompt = allowsEmptyStatePrompt
        self.autoRefreshIntervalOverride = autoRefreshIntervalOverride
        self.remoteHostRuntime = RemoteHostRuntime(
            settings: remoteHostSettings,
            accountStatusReader: remoteHostOperations,
            accounts: { accountsController.accounts },
            persistAccountMetadata: { accountsController.persistAccountMetadata($0) },
            markAccountActivated: { [notificationStateStore] accountID in
                notificationStateStore.markAccountActivated(accountID)
            }
        )
    }

    func start() {
        shortcutRuntime.onShortcut = { [weak self] in
            self?.statusItemRuntime.revealTitleTemporarily(duration: 3)
        }
        restorePersistedRemoteHostState()
        statusItemRuntime.start(presentation: statusItemPresentation(for: menuState()))
        lastObservedActiveAccountID = accountsController.activeAccountID
        notificationWorkflow.start(with: menuState())
        tasks.start { [weak self] in await self?.notificationWorkflow.refreshAuthorizationState() }
        startObservingStore()
        startObservingSettings()
        rebuildMenu()
        scheduleAutoRefresh()
        syncBackgroundState()
        tasks.start { [weak self] in await self?.refreshRemoteHostStateIfNeeded() }
        registerRevealShortcutFromSettings()
        refreshMenuUsageIfNeeded()
    }

    func invalidate() {
        autoRefreshTimer?.invalidate()
        wakeRefreshTask?.cancel()
        notificationWaitTask?.cancel()
        tokenUsageRuntime.cancel()
        cancelActiveIsolatedAddAccountSession()
        shortcutRuntime.invalidate()
        statusItemRuntime.invalidate()
    }

    /// Waits until the tasks started by menu actions, notification responses, and store or settings changes finish, including tasks they started.
    func waitForPendingWork() async {
        await tasks.waitUntilIdle()
    }

    func handleSystemDidWake() {
        scheduleAutoRefresh()
        wakeRefreshTask?.cancel()
        wakeRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            await self?.performScheduledRefresh()
        }
    }

    @objc
    func addAccount() {
        recordMenuAction("addAccount")
        menuBarCoordinatorLogger.log("addAccount action invoked")
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        menuBarCoordinatorLogger.log("Running CLI sessions before add-account: \(runningCLISessions, privacy: .public)")

        let request = alertFactory.makeAddAccountRequest(runningCLISessions: runningCLISessions)

        menuBarCoordinatorLogger.log("Presenting add-account confirmation alert")
        guard let name = alertPresenter.presentTextInput(request) else {
            menuBarCoordinatorLogger.log("Add-account flow cancelled from alert")
            return
        }

        menuBarCoordinatorLogger.log("Dispatching isolated add-account task to accounts controller")
        tasks.start { [weak self] in await self?.beginIsolatedAddAccount(named: name) }
    }

    @objc
    func removeAccount(_ sender: NSMenuItem) {
        recordMenuAction("removeAccount")
        guard
            let idString = sender.representedObject as? String,
            let id = UUID(uuidString: idString),
            let account = accountsController.accounts.first(where: { $0.id == id })
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
        tasks.start { [weak self] in
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
            let account = accountsController.accounts.first(where: { $0.id == id })
        else {
            return
        }

        let request = alertFactory.makeRenameAccountRequest(accountName: account.name)
        guard let newName = alertPresenter.presentTextInput(request) else { return }
        tasks.start { [accountsController] in await accountsController.renameSavedAccount(account, to: newName) }
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
    func toggleTokenUsage(_ sender: NSMenuItem) {
        recordMenuAction("toggleTokenUsage")
        tokenUsagePreferences.isEnabled.toggle()
        tokenUsageRuntime.handleEnabledChange(
            isEnabled: tokenUsagePreferences.isEnabled,
            period: tokenUsagePreferences.period,
            peakScope: tokenUsagePreferences.peakScope
        )
        rebuildMenu()
    }

    @objc
    func selectTokenUsagePeriod(_ sender: NSMenuItem) {
        recordMenuAction("selectTokenUsagePeriod")
        guard
            let rawValue = sender.representedObject as? Int,
            let period = CodexTokenUsagePeriod(rawValue: rawValue)
        else {
            return
        }
        tokenUsagePreferences.period = period
        tokenUsageRuntime.handlePeriodChange(period: period, peakScope: tokenUsagePreferences.peakScope)
        rebuildMenu()
    }

    @objc
    func selectTokenUsagePeakScope(_ sender: NSMenuItem) {
        recordMenuAction("selectTokenUsagePeakScope")
        guard
            let rawValue = sender.representedObject as? String,
            let peakScope = TokenUsagePeakScope(rawValue: rawValue)
        else {
            return
        }
        tokenUsagePreferences.peakScope = peakScope
        tokenUsageRuntime.handlePeriodChange(period: tokenUsagePreferences.period, peakScope: peakScope)
        rebuildMenu()
    }

    @objc
    func selectTokenUsageChartStyle(_ sender: NSMenuItem) {
        recordMenuAction("selectTokenUsageChartStyle")
        guard
            let rawValue = sender.representedObject as? String,
            let style = TokenUsageChartStyle(rawValue: rawValue)
        else {
            return
        }
        tokenUsagePreferences.chartStyle = style
        rebuildMenu()
    }

    @objc
    func selectTokenUsageLoadingAnimationStyle(_ sender: NSMenuItem) {
        recordMenuAction("selectTokenUsageLoadingAnimationStyle")
        guard
            let rawValue = sender.representedObject as? String,
            let style = TokenUsageLoadingAnimationStyle(rawValue: rawValue)
        else {
            return
        }
        tokenUsagePreferences.loadingAnimationStyle = style
        rebuildMenu()
    }

    @objc
    func selectUsagePercentMode(_ sender: NSMenuItem) {
        recordMenuAction("selectUsagePercentMode")
        guard
            let rawValue = sender.representedObject as? String,
            let mode = UsagePercentMode(rawValue: rawValue)
        else {
            return
        }
        statusItemSettings.usagePercentMode = mode
    }

    @objc
    func selectUsageMeterLayout(_ sender: NSMenuItem) {
        recordMenuAction("selectUsageMeterLayout")
        guard
            let rawValue = sender.representedObject as? String,
            let layout = UsageMeterLayout(rawValue: rawValue)
        else {
            return
        }
        statusItemSettings.usageMeterLayout = layout
    }

    @objc
    func chooseSessionAccentColor(_ sender: NSMenuItem) {
        recordMenuAction("chooseSessionAccentColor")
        presentUsageColorPanel(for: .session)
    }

    @objc
    func chooseWeeklyAccentColor(_ sender: NSMenuItem) {
        recordMenuAction("chooseWeeklyAccentColor")
        presentUsageColorPanel(for: .weekly)
    }

    @objc
    func toggleOneUsageColor(_ sender: NSMenuItem) {
        recordMenuAction("toggleOneUsageColor")
        statusItemSettings.usesOneUsageColor.toggle()
    }

    @objc
    func resetUsageColors(_ sender: NSMenuItem) {
        recordMenuAction("resetUsageColors")
        statusItemSettings.resetUsageColors()
        if let colorPanelTarget {
            NSColorPanel.shared.color = resolvedUsageColor(for: colorPanelTarget)
        }
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
        tasks.start { [weak self] in await self?.notificationWorkflow.enableNotifications() }
    }

    @objc
    func switchAccount(_ sender: NSMenuItem) {
        guard
            let idString = sender.representedObject as? String,
            let id = UUID(uuidString: idString),
            let account = accountsController.accounts.first(where: { $0.id == id })
        else {
            return
        }

        recordMenuAction("switchAccount")
        diagnosticEventRecorder.recordSwitchAccount(targetAccountID: account.id)
        requestSwitch(to: account)
    }

    @objc
    func switchAccountOnHost(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? HostAccountMenuItemPayload else { return }
        diagnosticEventRecorder.recordRemoteHostSwitch(
            targetAccountID: payload.accountID,
            hostDestination: payload.hostDestination
        )
        tasks.start { [weak self] in
            await self?.hostActionCoordinator.switchAccountOnHost(
                accountID: payload.accountID,
                hostDestination: payload.hostDestination
            )
        }
    }

    @objc
    func addHost(_ sender: NSMenuItem) {
        recordMenuAction("addHost")
        tasks.start { [weak self] in await self?.hostActionCoordinator.addHost() }
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
        reverifyHost(hostDestination: payload.hostDestination)
    }

    func reverifyHost(hostDestination: String) {
        tasks.start { [weak self] in await self?.hostActionCoordinator.reverifyHost(hostDestination: hostDestination) }
    }

    @objc
    func adoptDetectedRemoteAccount(_ sender: NSMenuItem) {
        recordMenuAction("adoptDetectedRemoteAccount")
        guard let payload = sender.representedObject as? HostAccountMenuItemPayload else { return }
        adoptDetectedRemoteAccount(hostDestination: payload.hostDestination, accountID: payload.accountID)
    }

    func adoptDetectedRemoteAccount(hostDestination: String, accountID: UUID) {
        tasks.start { [weak self] in
            await self?.hostActionCoordinator.adoptDetectedRemoteAccount(
                hostDestination: hostDestination,
                accountID: accountID
            )
        }
    }

    @objc
    func connectClaudeCode() {
        recordMenuAction("connectClaudeCode")
        guard let claudeCodeUsage else { return }
        do {
            if let change = try claudeCodeUsage.connectionChange() {
                guard alertPresenter.presentConfirmation(alertFactory.makeConnectClaudeCodeRequest(change: change)) else { return }
                try claudeCodeUsage.connect(confirming: change)
            }
        } catch {
            alertPresenter.presentInfo(alertFactory.makeClaudeCodeSettingsFailureRequest(error))
        }
        refreshProviderUsageIfDue()
    }

    @objc
    func disconnectClaudeCode() {
        recordMenuAction("disconnectClaudeCode")
        guard let claudeCodeUsage else { return }
        do {
            if let change = try claudeCodeUsage.disconnectionChange() {
                guard alertPresenter.presentConfirmation(alertFactory.makeDisconnectClaudeCodeRequest(change: change)) else { return }
                try claudeCodeUsage.disconnect(confirming: change)
            }
        } catch {
            alertPresenter.presentInfo(alertFactory.makeClaudeCodeSettingsFailureRequest(error))
        }
        refreshProviderUsageIfDue()
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
        rebuildDeferredMenuIfNeeded()
        statusItemRuntime.handleMenuWillOpen()
        refreshMenuUsageIfNeeded()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // AppKit may call this while opening/tracking the menu. Rebuilding here
        // causes native item layout to settle after the first paint.
        accountsController.refreshActiveAccount()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItemRuntime.handleMenuDidClose()
        if rebuildsMenuAfterClose {
            rebuildsMenuAfterClose = false
            rebuildMenu()
        }
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
        guard let account = accountsController.accounts.first(where: { $0.id == accountID }) else { return }
        requestSwitch(to: account)
    }

    private func rebuildMenu(using state: MenuBarMenuState? = nil) {
        let state = state ?? menuState()
        let menu = statusItemRuntime.menu ?? NSMenu()
        menuBuilder.populate(menu: menu, state: state, target: self)
        statusItemRuntime.menu = menu
    }

    func menuState() -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: accountsController.activeAccount,
            inactiveAccounts: accountsController.sortedInactiveAccounts,
            remoteHosts: remoteHostRuntime.menuStates(),
            visibleInactiveAccountCount: menuDisplaySettings.visibleInactiveAccountCount,
            visibleInactiveAccountCountOptions: menuDisplaySettings.visibleInactiveAccountCountOptions,
            refreshIntervalMinutes: menuDisplaySettings.refreshIntervalMinutes,
            refreshIntervalOptions: menuDisplaySettings.refreshIntervalOptions,
            statusBarMonochrome: statusItemSettings.statusBarMonochrome,
            statusBarIndicatorStyle: statusItemSettings.statusBarIndicatorStyle,
            statusBarDisplayMode: statusItemSettings.statusBarDisplayMode,
            revealStatusItemTitleShortcut: statusItemSettings.revealStatusItemTitleShortcut,
            sessionAccentColor: resolvedUsageColor(for: .session),
            weeklyAccentColor: resolvedUsageColor(for: .weekly),
            usesOneUsageColor: statusItemSettings.usesOneUsageColor,
            hasCustomUsageColors: statusItemSettings.hasCustomUsageColors,
            usagePercentMode: statusItemSettings.usagePercentMode,
            usageMeterLayout: statusItemSettings.usageMeterLayout,
            pacingMarkersEnabled: statusItemSettings.pacingMarkersEnabled,
            isBusy: accountsController.isBusy,
            statusMessage: accountsController.statusMessage,
            notificationsWhenBlockedEnabled: notificationWorkflow.whenBlockedEnabled,
            notificationsWhenOutEnabled: notificationWorkflow.whenOutEnabled,
            notificationAuthorizationState: notificationWorkflow.authorizationState,
            loginItemState: loginItemController.state(),
            tokenUsageEnabled: tokenUsagePreferences.isEnabled,
            tokenUsagePeriod: tokenUsagePreferences.period,
            tokenUsageChartStyle: tokenUsagePreferences.chartStyle,
            tokenUsageLoadingAnimationStyle: tokenUsagePreferences.loadingAnimationStyle,
            tokenUsagePeakScope: tokenUsagePreferences.peakScope,
            tokenUsageCard: makeTokenUsageCard(),
            providerUsage: providerUsageRuntime.states
        )
    }

    private func makeTokenUsageCard() -> TokenUsageMenuCard? {
        guard tokenUsagePreferences.isEnabled else { return nil }
        return TokenUsageMenuCard.make(
            style: tokenUsagePreferences.chartStyle,
            loadingAnimationStyle: tokenUsagePreferences.loadingAnimationStyle,
            peakScope: tokenUsagePreferences.peakScope,
            period: tokenUsagePreferences.period,
            loadState: tokenUsageRuntime.loadState
        )
    }

    /// Token usage and provider usage only appear inside the menu, so opening it is the moment to bring them up to date.
    private func refreshMenuUsageIfNeeded() {
        refreshProviderUsageIfDue()
        guard tokenUsagePreferences.isEnabled else {
            tokenUsageRuntime.cancel()
            return
        }

        tokenUsageRuntime.refreshIfNeeded(period: tokenUsagePreferences.period, peakScope: tokenUsagePreferences.peakScope)
    }

    private func refreshProviderUsageIfDue() {
        tasks.start { [weak self] in await self?.providerUsageRuntime.refreshIfDue() }
    }

    /// Rebuilding an open menu makes it jump, so menu-only content rebuilds after the menu closes, or right before it next opens.
    private func rebuildMenuWhenSafe() {
        guard !statusItemRuntime.isMenuTrackingOpen else {
            rebuildsMenuAfterClose = true
            return
        }
        rebuildsMenuBeforeOpen = true
    }

    private func rebuildDeferredMenuIfNeeded() {
        guard rebuildsMenuBeforeOpen else { return }
        rebuildsMenuBeforeOpen = false
        rebuildMenu()
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
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        let request = alertFactory.makeSwitchAccountRequest(accountName: account.name, runningCLISessions: runningCLISessions)

        guard alertPresenter.presentConfirmation(request) else { return }
        beginLocalSwitch(to: account)
    }

    private func beginIsolatedAddAccount(named name: String) async {
        do {
            let session = try await accountsController.startIsolatedAddAccountFlow(named: name)
            activeIsolatedAddAccountSession = session

            let signInRequest = alertFactory.makeAddAccountSignInRequest(prompt: session.prompt)
            let result = await panelPresenter.presentAddAccountSignIn(
                signInRequest,
                waitForCompletion: { [accountsController] in
                    do {
                        let account = try await accountsController.completeIsolatedAddAccount(session)
                        return .success(account)
                    } catch {
                        return .failure(error)
                    }
                },
                onCancel: { [accountsController] in
                    accountsController.cancelIsolatedAddAccount(session)
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
        accountsController.cancelIsolatedAddAccount(session)
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
        _ = accountsController.consumePendingErrorMessage()

        switch step {
        case .showSignInFailure(let outcome):
            alertPresenter.presentInfo(alertFactory.makeAddAccountSignInFailureRequest(outcome: outcome))
        case .offerSignInRetry(let outcome, let retryName):
            let request = alertFactory.makeAddAccountSignInRetryRequest(outcome: outcome)
            guard alertPresenter.presentConfirmation(request) else { return }
            tasks.start { [weak self] in await self?.beginIsolatedAddAccount(named: retryName) }
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
        tasks.start { [accountsController] in
            _ = await accountsController.switchToAccount(account)
        }
    }

    func handleNotificationResponse(_ payload: AccountAvailabilityNotificationResponsePayload) async {
        notificationWorkflow.handleResponse(
            payload: payload,
            state: menuState()
        )
    }

    private func recordMenuAction(_ name: String) {
        diagnosticEventRecorder.recordMenuAction(name)
    }

    private func scheduleAutoRefresh() {
        autoRefreshTimer?.invalidate()
        let interval = autoRefreshIntervalOverride ?? TimeInterval(menuDisplaySettings.refreshIntervalMinutes * 60)
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tasks.start { await self?.performScheduledRefresh() }
        }
    }

    func performScheduledRefresh() async {
        refreshProviderUsageIfDue()
        guard !accountsController.isBusy else { return }
        if let activeAccount = accountsController.activeAccount {
            switch await accountsController.refreshAccountData(for: activeAccount) {
            case .refreshed:
                diagnosticEventRecorder.recordRefresh(resultCategory: "refreshed")
            case .failed:
                diagnosticEventRecorder.recordRefresh(resultCategory: "failed")
            }
        }

        await accountsController.refreshInactiveSavedAccountsMetadata()
        await refreshRemoteHostStateIfNeeded(markSyncing: false)
    }

    private func startObservingStore() {
        guard !isObservingStore else { return }
        isObservingStore = true
        observeStoreChanges()
    }

    private func observeStoreChanges() {
        withObservationTracking {
            _ = accountsController.accounts
            _ = accountsController.activeAccountID
            _ = accountsController.pendingErrorMessage
            _ = accountsController.statusMessage
            _ = accountsController.isBusy
        } onChange: { [weak self] in
            self?.tasks.start { [weak self] in
                guard let self else { return }
                let state = self.handleStoreChange()
                self.observeStoreChanges()
                await self.notificationWorkflow.evaluate(using: state)
            }
        }
    }

    private func handleStoreChange() -> MenuBarMenuState {
        let state = menuState()
        recordActiveAccountTransitionIfNeeded()
        if !accountsController.accounts.isEmpty {
            hasPromptedForEmptyState = false
        }
        statusItemRuntime.update(presentation: statusItemPresentation(for: state))
        rebuildMenu(using: state)
        presentPendingErrorIfNeeded()
        syncBackgroundState()
        return state
    }

    private func recordActiveAccountTransitionIfNeeded() {
        let currentActiveAccountID = accountsController.activeAccountID
        defer { lastObservedActiveAccountID = currentActiveAccountID }

        guard currentActiveAccountID != lastObservedActiveAccountID, let currentActiveAccountID else { return }
        notificationWorkflow.markAccountActivated(currentActiveAccountID)
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
            _ = statusItemSettings.sessionAccentColor
            _ = statusItemSettings.weeklyAccentColor
            _ = statusItemSettings.usesOneUsageColor
            _ = statusItemSettings.usagePercentMode
            _ = statusItemSettings.usageMeterLayout
            _ = statusItemSettings.pacingMarkersEnabled
            _ = remoteHostSettings.remoteHostStates
            _ = notificationPreferences.notificationsWhenBlockedEnabled
            _ = notificationPreferences.notificationsWhenOutEnabled
        } onChange: { [weak self] in
            self?.tasks.start { [weak self] in
                guard let self else { return }
                let state = self.handleSettingsChange()
                self.observeSettingsChanges()
                await self.notificationWorkflow.evaluate(using: state)
            }
        }
    }

    private func handleSettingsChange() -> MenuBarMenuState {
        let state = menuState()
        statusItemRuntime.update(presentation: statusItemPresentation(for: state))
        scheduleAutoRefresh()
        rebuildMenu(using: state)
        return state
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
            let remoteHost = remoteHostSettings.remoteHostState(for: hostDestination)?.host
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
            await self.performScheduledRefresh()
        }
    }

    private func removeSavedAccount(
        _ account: CodexAccount,
        signOutLocalAccount: Bool,
        remoteHosts: [RemoteHostMenuState]
    ) async {
        do {
            try await signOutRemoteHosts(remoteHosts)
            await accountsController.removeSavedAccount(account, signOutLocalAccount: signOutLocalAccount)
            presentPendingErrorIfNeeded()
        } catch {
            alertPresenter.presentInfo(alertFactory.makeErrorRequest(message: error.localizedDescription))
        }
        rebuildMenu()
    }

    private func signOutRemoteHosts(_ remoteHosts: [RemoteHostMenuState]) async throws {
        for remoteHostState in remoteHosts {
            guard let remoteHost = remoteHostSettings.remoteHostState(for: remoteHostState.destination)?.host else {
                throw RemoteHostClientError.commandFailed("Remote host \(remoteHostState.name) is no longer configured.")
            }
            try await remoteHostOperations.signOut(on: remoteHost)
            try await remoteHostOperations.refreshCodexAppServer(on: remoteHost)
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

    private func refreshRemoteHostStateIfNeeded(markSyncing: Bool = true) async {
        await remoteHostRuntime.refreshAll(markSyncing: markSyncing) { [weak self] in
            self?.rebuildMenu()
        }
    }

    private func presentPendingErrorIfNeeded() {
        guard let message = accountsController.consumePendingErrorMessage() else { return }
        alertPresenter.presentInfo(alertFactory.makeErrorRequest(message: message))
    }

    private func syncBackgroundState() {
        promptForEmptyStateIfNeeded()
    }

    private func promptForEmptyStateIfNeeded() {
        guard allowsEmptyStatePrompt else { return }
        guard accountsController.accounts.isEmpty, !accountsController.isBusy, !hasPromptedForEmptyState else { return }
        hasPromptedForEmptyState = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.accountsController.accounts.isEmpty, !self.accountsController.isBusy else { return }
            self.addAccount()
        }
    }

    private func statusItemPresentation(for state: MenuBarMenuState) -> StatusItemRuntimePresentation {
        StatusItemRuntimePresentation(
            activeAccount: accountsController.activeAccount,
            indicatorStyle: statusItemSettings.statusBarIndicatorStyle,
            monochrome: statusItemSettings.statusBarMonochrome,
            displayMode: state.effectiveStatusBarDisplayMode,
            percentMode: state.usagePercentMode,
            sessionAccentColor: state.sessionAccentColor,
            weeklyAccentColor: state.weeklyAccentColor
        )
    }

    private func resolvedUsageColor(for target: UsageColorTarget) -> NSColor {
        switch target {
        case .session:
            statusItemSettings.sessionAccentColor.resolvedStatusItemAccentColor
        case .weekly:
            statusItemSettings.effectiveWeeklyAccentColor.resolvedStatusItemAccentColor
        }
    }

    private func presentUsageColorPanel(for target: UsageColorTarget) {
        colorPanelTarget = target
        let panel = NSColorPanel.shared
        panel.title = target.panelTitle
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(handleUsageColorPanelChanged(_:)))
        panel.color = resolvedUsageColor(for: target)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc
    private func handleUsageColorPanelChanged(_ sender: NSColorPanel) {
        guard let colorPanelTarget else { return }
        let color = sender.color.withAlphaComponent(1)
        switch colorPanelTarget {
        case .session:
            statusItemSettings.sessionAccentColor = color.isEqualToStatusItemAccentColor(StatusBarProgressColorDefaults.accent)
                ? nil
                : StatusItemAccentColor(nsColor: color)
        case .weekly:
            guard !color.isEqualToStatusItemAccentColor(resolvedUsageColor(for: .weekly)) else { return }
            statusItemSettings.weeklyAccentColor = StatusItemAccentColor(nsColor: color)
            statusItemSettings.usesOneUsageColor = false
        }
    }
}

private enum UsageColorTarget {
    case session
    case weekly

    var panelTitle: String {
        switch self {
        case .session:
            "Session Color"
        case .weekly:
            "Weekly Color"
        }
    }
}
