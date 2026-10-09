import AppKit
import Observation
import OSLog

private let menuBarCoordinatorLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "MenuBarCoordinator")

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let statusItemRuntime: StatusItemRuntime
    private let shortcutRuntime: GlobalShortcutRuntime
    private let store: MenuBarAccountsStore
    private let menuDisplaySettings: MenuDisplaySettingsStore
    private let statusItemSettings: StatusItemSettingsStore
    private let tokenUsagePreferences: TokenUsagePreferencesStore
    private let cliProcessInspector: CodexCLIProcessInspector
    private let alertPresenter: AlertPresenter
    private let panelPresenter: PanelPresenter
    private let shortcutCapturePanelPresenter: ShortcutCapturePanelPresenter
    private let alertFactory: MenuBarAlertFactory
    private let loginItemController: LoginItemControlling
    private let loginItemsSettingsLauncher: LoginItemsSettingsLaunching
    private let diagnosticReportPresenter: DiagnosticReportPresenting
    private let diagnosticEventRecorder: DiagnosticEventRecorder
    private let tokenUsageProvider: TokenUsageMenuProviding
    private let validationObserver: MenuBarValidationObserver
    private let allowsEmptyStatePrompt: Bool
    private let accountActionFlow = AccountActionFlow()
    private let menuBuilder = MenuBarMenuBuilder()
    private var autoRefreshTimer: Timer?
    private var wakeRefreshTask: Task<Void, Never>?
    private var pendingTokenUsageMenuRebuild = false
    private var deferredTokenUsageMenuRebuild = false
    private var hasPromptedForEmptyState = false
    private var isObservingSettings = false
    private var isObservingStore = false
    private var lastObservedActiveAccountID: UUID?
    private var lastObservedActiveAccountName: String?
    private var activeIsolatedAddAccountSession: IsolatedAddAccountSignInSession?
    private lazy var tokenUsageRuntime = TokenUsageMenuRuntime(
        provider: tokenUsageProvider,
        onStateChange: { [weak self] _ in
            self?.rebuildTokenUsageMenuWhenSafe()
        }
    )

    init(
        statusItemRuntime: StatusItemRuntime,
        shortcutRuntime: GlobalShortcutRuntime? = nil,
        store: MenuBarAccountsStore,
        menuDisplaySettings: MenuDisplaySettingsStore,
        statusItemSettings: StatusItemSettingsStore,
        tokenUsagePreferences: TokenUsagePreferencesStore,
        cliProcessInspector: CodexCLIProcessInspector = CodexCLIProcessInspector(),
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter? = nil,
        shortcutCapturePanelPresenter: ShortcutCapturePanelPresenter? = nil,
        alertFactory: MenuBarAlertFactory = MenuBarAlertFactory(),
        loginItemController: LoginItemControlling = SystemLoginItemController(),
        loginItemsSettingsLauncher: LoginItemsSettingsLaunching = SystemLoginItemsSettingsLauncher(),
        diagnosticReportPresenter: DiagnosticReportPresenting? = nil,
        diagnosticEventRecorder: DiagnosticEventRecorder? = nil,
        tokenUsageProvider: TokenUsageMenuProviding = LocalCodexSessionTokenUsageMenuProvider(),
        validationSink: MenuBarValidationSink? = nil,
        validationScenario: String? = MenuBarValidationConfiguration.scenario(),
        validationObserver: MenuBarValidationObserver? = nil,
        allowsEmptyStatePrompt: Bool = true
    ) {
        self.statusItemRuntime = statusItemRuntime
        self.shortcutRuntime = shortcutRuntime ?? GlobalShortcutRuntime()
        self.store = store
        self.menuDisplaySettings = menuDisplaySettings
        self.statusItemSettings = statusItemSettings
        self.tokenUsagePreferences = tokenUsagePreferences
        self.cliProcessInspector = cliProcessInspector
        self.alertPresenter = alertPresenter
        self.panelPresenter = panelPresenter ?? SystemPanelPresenter()
        self.shortcutCapturePanelPresenter = shortcutCapturePanelPresenter ?? SystemShortcutCapturePanelPresenter()
        self.alertFactory = alertFactory
        self.loginItemController = loginItemController
        self.loginItemsSettingsLauncher = loginItemsSettingsLauncher
        self.diagnosticReportPresenter = diagnosticReportPresenter ?? SystemDiagnosticReportPresenter()
        self.diagnosticEventRecorder = diagnosticEventRecorder ?? DiagnosticEventRecorder()
        self.tokenUsageProvider = tokenUsageProvider
        self.validationObserver = validationObserver ?? MenuBarValidationObserver(
            sink: validationSink,
            scenario: validationScenario
        )
        self.allowsEmptyStatePrompt = allowsEmptyStatePrompt
    }

    func start() {
        statusItemRuntime.onEvent = { [weak self] event in
            self?.handleStatusItemRuntimeEvent(event)
        }
        shortcutRuntime.onShortcut = { [weak self] in
            self?.statusItemRuntime.revealTitleTemporarily(duration: 3)
        }
        statusItemRuntime.start(presentation: statusItemPresentation(for: menuState()))
        lastObservedActiveAccountID = store.activeAccountID
        lastObservedActiveAccountName = store.activeAccount?.name
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
        let request = alertFactory.makeRemoveAccountRequest(
            accountName: account.name,
            activeTargets: shouldSignOutLocalAccount ? ["This Mac"] : []
        )

        guard alertPresenter.presentConfirmation(request) else { return }
        Task { @MainActor [weak self] in
            await self?.removeSavedAccount(account, signOutLocalAccount: shouldSignOutLocalAccount)
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
        validationObserver.recordMenuOpened(menuItemCount: statusItemRuntime.menuItemCount)
        refreshTokenUsageIfNeeded()
        recordValidationSnapshot(for: menuState())
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // AppKit may call this while opening/tracking the menu. Rebuilding here
        // causes native item layout to settle after the first paint.
        store.refreshActiveAccount()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItemRuntime.handleMenuDidClose()
        if pendingTokenUsageMenuRebuild {
            pendingTokenUsageMenuRebuild = false
            rebuildMenu()
        }
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
            isBusy: store.isBusy,
            statusMessage: store.statusMessage,
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

            await self.store.refreshInactiveSavedAccountsMetadata()
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
    }

    private func recordActiveAccountTransitionIfNeeded() {
        let currentActiveAccountID = store.activeAccountID
        let currentActiveAccountName = store.activeAccount?.name

        defer {
            lastObservedActiveAccountID = currentActiveAccountID
            lastObservedActiveAccountName = currentActiveAccountName
        }

        guard currentActiveAccountID != lastObservedActiveAccountID else { return }

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
            _ = statusItemSettings.progressAccentColor
            _ = statusItemSettings.pacingMarkersEnabled
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
    }

    private func removeSavedAccount(_ account: CodexAccount, signOutLocalAccount: Bool) async {
        await store.removeSavedAccount(account, signOutLocalAccount: signOutLocalAccount)
        presentPendingErrorIfNeeded()
        rebuildMenu()
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

    private func handleStatusItemRuntimeEvent(_ event: StatusItemRuntime.Event) {
        defer {
            recordValidationSnapshot(for: menuState())
        }

        validationObserver.recordStatusItemRuntimeEvent(event)
    }
}
