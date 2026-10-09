import AppKit
import Observation
import OSLog

private let menuBarCoordinatorLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "MenuBarCoordinator")

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let statusItemRuntime: StatusItemRuntime
    private let shortcutRuntime: GlobalShortcutRuntime
    private let accountsController: MenuBarAccounts
    private let menuDisplaySettings: MenuDisplaySettingsStore
    private let statusItemSettings: StatusItemSettingsStore
    private let tokenUsagePreferences: TokenUsagePreferencesStore
    private let cliProcessInspector: CodexCLIProcessInspector
    private let alertPresenter: AlertPresenter
    private let panelPresenter: PanelPresenter
    private let shortcutCapturePanelPresenter: ShortcutCapturePanelPresenter
    private let alertFactory = MenuBarAlertFactory()
    private let loginItemController: LoginItemControlling
    private let loginItemsSettingsLauncher: LoginItemsSettingsLaunching
    private let diagnosticReportPresenter: DiagnosticReportPresenting
    private let diagnosticEventRecorder = DiagnosticEventRecorder()
    private let tokenUsageProvider: TokenUsageMenuProviding
    private let allowsEmptyStatePrompt: Bool
    private let autoRefreshIntervalOverride: TimeInterval?
    private let accountActionFlow = AccountActionFlow()
    private let menuBuilder = MenuBarMenuBuilder()
    private var autoRefreshTimer: Timer?
    private var wakeRefreshTask: Task<Void, Never>?
    private let tasks = TrackedTasks()
    private var pendingTokenUsageMenuRebuild = false
    private var deferredTokenUsageMenuRebuild = false
    private var hasPromptedForEmptyState = false
    private var isObservingSettings = false
    private var isObservingStore = false
    private var activeIsolatedAddAccountSession: IsolatedAddAccountSignInSession?
    private lazy var tokenUsageRuntime = TokenUsageMenuRuntime(
        provider: tokenUsageProvider,
        onStateChange: { [weak self] _ in
            self?.rebuildTokenUsageMenuWhenSafe()
        }
    )

    init(
        statusItemRuntime: StatusItemRuntime,
        shortcutRuntime: GlobalShortcutRuntime,
        accountsController: MenuBarAccounts,
        menuDisplaySettings: MenuDisplaySettingsStore,
        statusItemSettings: StatusItemSettingsStore,
        tokenUsagePreferences: TokenUsagePreferencesStore,
        cliProcessInspector: CodexCLIProcessInspector,
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter,
        shortcutCapturePanelPresenter: ShortcutCapturePanelPresenter,
        loginItemController: LoginItemControlling,
        loginItemsSettingsLauncher: LoginItemsSettingsLaunching,
        diagnosticReportPresenter: DiagnosticReportPresenting,
        tokenUsageProvider: TokenUsageMenuProviding,
        allowsEmptyStatePrompt: Bool,
        autoRefreshIntervalOverride: TimeInterval?
    ) {
        self.statusItemRuntime = statusItemRuntime
        self.shortcutRuntime = shortcutRuntime
        self.accountsController = accountsController
        self.menuDisplaySettings = menuDisplaySettings
        self.statusItemSettings = statusItemSettings
        self.tokenUsagePreferences = tokenUsagePreferences
        self.cliProcessInspector = cliProcessInspector
        self.alertPresenter = alertPresenter
        self.panelPresenter = panelPresenter
        self.shortcutCapturePanelPresenter = shortcutCapturePanelPresenter
        self.loginItemController = loginItemController
        self.loginItemsSettingsLauncher = loginItemsSettingsLauncher
        self.diagnosticReportPresenter = diagnosticReportPresenter
        self.tokenUsageProvider = tokenUsageProvider
        self.allowsEmptyStatePrompt = allowsEmptyStatePrompt
        self.autoRefreshIntervalOverride = autoRefreshIntervalOverride
    }

    func start() {
        shortcutRuntime.onShortcut = { [weak self] in
            self?.statusItemRuntime.revealTitleTemporarily(duration: 3)
        }
        statusItemRuntime.start(presentation: statusItemPresentation(for: menuState()))
        startObservingStore()
        startObservingSettings()
        rebuildMenu()
        scheduleAutoRefresh()
        syncBackgroundState()
        registerRevealShortcutFromSettings()
        refreshTokenUsageIfNeeded()
    }

    func invalidate() {
        autoRefreshTimer?.invalidate()
        wakeRefreshTask?.cancel()
        tokenUsageRuntime.cancel()
        cancelActiveIsolatedAddAccountSession()
        shortcutRuntime.invalidate()
        statusItemRuntime.invalidate()
    }

    /// Waits until the tasks started by menu actions and store or settings changes finish, including tasks they started.
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
        let request = alertFactory.makeRemoveAccountRequest(
            accountName: account.name,
            activeTargets: shouldSignOutLocalAccount ? ["This Mac"] : []
        )

        guard alertPresenter.presentConfirmation(request) else { return }
        tasks.start { [weak self] in
            await self?.removeSavedAccount(account, signOutLocalAccount: shouldSignOutLocalAccount)
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
    func chooseProgressAccentColor(_ sender: NSMenuItem) {
        recordMenuAction("chooseProgressAccentColor")
        presentProgressColorPanel()
    }

    @objc
    func resetProgressAccentColor(_ sender: NSMenuItem) {
        recordMenuAction("resetProgressAccentColor")
        statusItemSettings.resetProgressAccentColor()
        NSColorPanel.shared.color = statusItemSettings.progressAccentColor.resolvedStatusItemAccentColor
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
        rebuildDeferredTokenUsageMenuIfNeeded()
        statusItemRuntime.handleMenuWillOpen()
        refreshTokenUsageIfNeeded()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // AppKit may call this while opening/tracking the menu. Rebuilding here
        // causes native item layout to settle after the first paint.
        accountsController.refreshActiveAccount()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItemRuntime.handleMenuDidClose()
        if pendingTokenUsageMenuRebuild {
            pendingTokenUsageMenuRebuild = false
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
            visibleInactiveAccountCount: menuDisplaySettings.visibleInactiveAccountCount,
            visibleInactiveAccountCountOptions: menuDisplaySettings.visibleInactiveAccountCountOptions,
            refreshIntervalMinutes: menuDisplaySettings.refreshIntervalMinutes,
            refreshIntervalOptions: menuDisplaySettings.refreshIntervalOptions,
            statusBarMonochrome: statusItemSettings.statusBarMonochrome,
            statusBarIndicatorStyle: statusItemSettings.statusBarIndicatorStyle,
            statusBarDisplayMode: statusItemSettings.statusBarDisplayMode,
            revealStatusItemTitleShortcut: statusItemSettings.revealStatusItemTitleShortcut,
            progressAccentColor: statusItemSettings.progressAccentColor.resolvedStatusItemAccentColor,
            pacingMarkersEnabled: statusItemSettings.pacingMarkersEnabled,
            hasCustomProgressAccentColor: statusItemSettings.hasCustomProgressAccentColor,
            isBusy: accountsController.isBusy,
            statusMessage: accountsController.statusMessage,
            loginItemState: loginItemController.state(),
            tokenUsageEnabled: tokenUsagePreferences.isEnabled,
            tokenUsagePeriod: tokenUsagePreferences.period,
            tokenUsageChartStyle: tokenUsagePreferences.chartStyle,
            tokenUsageLoadingAnimationStyle: tokenUsagePreferences.loadingAnimationStyle,
            tokenUsagePeakScope: tokenUsagePreferences.peakScope,
            tokenUsageCard: makeTokenUsageCard()
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

    private func refreshTokenUsageIfNeeded() {
        guard tokenUsagePreferences.isEnabled else {
            tokenUsageRuntime.cancel()
            return
        }

        tokenUsageRuntime.refreshIfNeeded(period: tokenUsagePreferences.period, peakScope: tokenUsagePreferences.peakScope)
    }

    private func rebuildTokenUsageMenuWhenSafe() {
        guard !statusItemRuntime.isMenuTrackingOpen else {
            pendingTokenUsageMenuRebuild = true
            return
        }
        deferredTokenUsageMenuRebuild = true
    }

    private func rebuildDeferredTokenUsageMenuIfNeeded() {
        guard deferredTokenUsageMenuRebuild else { return }
        deferredTokenUsageMenuRebuild = false
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
                self.handleStoreChange()
                self.observeStoreChanges()
            }
        }
    }

    private func handleStoreChange() {
        let state = menuState()
        if !accountsController.accounts.isEmpty {
            hasPromptedForEmptyState = false
        }
        statusItemRuntime.update(presentation: statusItemPresentation(for: state))
        rebuildMenu(using: state)
        presentPendingErrorIfNeeded()
        syncBackgroundState()
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
        } onChange: { [weak self] in
            self?.tasks.start { [weak self] in
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
    }

    private func removeSavedAccount(_ account: CodexAccount, signOutLocalAccount: Bool) async {
        await accountsController.removeSavedAccount(account, signOutLocalAccount: signOutLocalAccount)
        presentPendingErrorIfNeeded()
        rebuildMenu()
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
            progressAccentColor: statusItemSettings.progressAccentColor.resolvedStatusItemAccentColor
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
        panel.color = statusItemSettings.progressAccentColor.resolvedStatusItemAccentColor
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc
    private func handleProgressColorPanelChanged(_ sender: NSColorPanel) {
        let color = sender.color.withAlphaComponent(1)
        statusItemSettings.progressAccentColor = color.isEqualToStatusItemAccentColor(StatusBarProgressColorDefaults.accent)
            ? nil
            : StatusItemAccentColor(nsColor: color)
    }
}
