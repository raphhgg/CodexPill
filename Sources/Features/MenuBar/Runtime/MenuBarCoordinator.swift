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
    private let claudeUsageSettings: ClaudeUsageSettingsStore
    private let appIconPreferences: AppIconPreferencesStore
    private let appIconApplier: AppIconApplying
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
    private let accountActionFlow = AccountActionFlow()
    private let menuBuilder = MenuBarMenuBuilder()
    private var autoRefreshTimer: Timer?
    private var colorPanelTarget: UsageColorTarget?
    private var wakeRefreshTask: Task<Void, Never>?
    private let tasks = TrackedTasks()
    private var rebuildsMenuAfterClose = false
    private var rebuildsMenuBeforeOpen = false
    private var menuBuiltAt: Date?
    private let now: () -> Date
    private var hasPromptedForEmptyState = false
    private var isObservingSettings = false
    private var isObservingStore = false
    private var activeIsolatedAddAccountSession: IsolatedAddAccountSignInSession?
    private lazy var tokenUsageRuntime = TokenUsageMenuRuntime(
        provider: tokenUsageProvider,
        onStateChange: { [weak self] _ in
            self?.rebuildMenuWhenSafe()
        }
    )
    private let providerConnections: [any ProviderConnection]
    private lazy var providerUsageRuntime = ProviderUsageRuntime(
        connections: providerConnections,
        onChange: { [weak self] in
            guard let self else { return }
            statusItemRuntime.update(presentation: statusItemPresentation(for: menuState()))
            rebuildMenuWhenSafe()
        }
    )

    init(
        statusItemRuntime: StatusItemRuntime,
        shortcutRuntime: GlobalShortcutRuntime,
        accountsController: MenuBarAccounts,
        menuDisplaySettings: MenuDisplaySettingsStore,
        statusItemSettings: StatusItemSettingsStore,
        tokenUsagePreferences: TokenUsagePreferencesStore,
        claudeUsageSettings: ClaudeUsageSettingsStore,
        appIconPreferences: AppIconPreferencesStore,
        appIconApplier: AppIconApplying,
        cliProcessInspector: CodexCLIProcessInspector,
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter,
        shortcutCapturePanelPresenter: ShortcutCapturePanelPresenter,
        loginItemController: LoginItemControlling,
        loginItemsSettingsLauncher: LoginItemsSettingsLaunching,
        diagnosticReportPresenter: DiagnosticReportPresenting,
        tokenUsageProvider: TokenUsageMenuProviding,
        providerConnections: [any ProviderConnection],
        allowsEmptyStatePrompt: Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.statusItemRuntime = statusItemRuntime
        self.shortcutRuntime = shortcutRuntime
        self.accountsController = accountsController
        self.menuDisplaySettings = menuDisplaySettings
        self.statusItemSettings = statusItemSettings
        self.tokenUsagePreferences = tokenUsagePreferences
        self.claudeUsageSettings = claudeUsageSettings
        self.appIconPreferences = appIconPreferences
        self.appIconApplier = appIconApplier
        self.cliProcessInspector = cliProcessInspector
        self.alertPresenter = alertPresenter
        self.panelPresenter = panelPresenter
        self.shortcutCapturePanelPresenter = shortcutCapturePanelPresenter
        self.loginItemController = loginItemController
        self.loginItemsSettingsLauncher = loginItemsSettingsLauncher
        self.diagnosticReportPresenter = diagnosticReportPresenter
        self.tokenUsageProvider = tokenUsageProvider
        self.providerConnections = providerConnections
        self.allowsEmptyStatePrompt = allowsEmptyStatePrompt
        self.now = now
    }

    func start() {
        appIconApplier.apply(appIconPreferences.appIconColor)
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
        refreshMenuUsageIfNeeded()
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

    private func addCodexAccount() {
        recordMenuAction("addAccount")
        menuBarCoordinatorLogger.log("Dispatching isolated add-account task to accounts controller")
        tasks.start { [weak self] in await self?.beginIsolatedAddAccount() }
    }

    /// What alerts call a saved Codex account: the label its side menu shows.
    private func codexAccountLabel(_ id: UUID) -> String {
        menuState().accountLabel(id, of: .codex) ?? "Saved account"
    }

    private func removeCodexAccount(_ id: UUID) {
        recordMenuAction("removeAccount")
        guard let account = accountsController.accounts.first(where: { $0.id == id }) else { return }

        let state = menuState()
        let shouldSignOutLocalAccount = state.isAccountActiveLocally(account)
        let request = alertFactory.makeRemoveAccountRequest(
            accountLabel: codexAccountLabel(account.id),
            activeTargets: shouldSignOutLocalAccount ? ["This Mac"] : []
        )

        guard alertPresenter.presentConfirmation(request) else { return }
        tasks.start { [weak self] in
            await self?.removeSavedAccount(account, signOutLocalAccount: shouldSignOutLocalAccount)
        }
    }

    @objc
    func selectRefreshInterval(_ sender: NSMenuItem) {
        recordMenuAction("selectRefreshInterval")
        guard let minutes = sender.representedObject as? Int else { return }
        menuDisplaySettings.refreshIntervalMinutes = minutes
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
    func toggleShowsModelLimits(_ sender: NSMenuItem) {
        recordMenuAction("toggleShowsModelLimits")
        claudeUsageSettings.showsModelLimits.toggle()
        rebuildMenu()
    }

    @objc
    func selectAppIconColor(_ sender: NSMenuItem) {
        recordMenuAction("selectAppIconColor")
        guard
            let rawValue = sender.representedObject as? String,
            let color = AppIconColor(rawValue: rawValue)
        else {
            return
        }
        appIconPreferences.appIconColor = color
        appIconApplier.apply(color)
    }

    @objc
    func toggleMasksEmails(_ sender: NSMenuItem) {
        recordMenuAction("toggleMasksEmails")
        menuDisplaySettings.masksEmails.toggle()
    }

    @objc
    func reorderTools(_ sender: NSMenuItem) {
        recordMenuAction("reorderTools")
        guard let order = sender.representedObject as? [UsageProvider] else { return }
        menuDisplaySettings.toolOrder = order
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

    /// The one entry point for every tool menu item: Codex, Claude Code and Cursor alike.
    @objc
    func performProviderAction(_ sender: NSMenuItem) {
        guard let menuAction = sender.representedObject as? ProviderMenuAction else { return }
        perform(menuAction.action, on: menuAction.provider)
    }

    func perform(_ action: ProviderAction, on provider: UsageProvider) {
        guard provider != .codex else {
            performCodexAction(action)
            return
        }
        recordMenuAction("\(provider).\(action.name)")
        let accountID: UUID? = switch action {
        case let .switchAccount(id), let .removeAccount(id): id
        default: nil
        }
        if let prompt = provider.copy.prompt(for: action, accountLabel: accountID.flatMap { menuState().accountLabel($0, of: provider) }) {
            guard alertPresenter.presentConfirmation(alertFactory.makeConfirmationRequest(prompt)) else { return }
        }
        tasks.start { [weak self] in
            guard let self, let notice = await providerUsageRuntime.perform(action, on: provider) else { return }
            alertPresenter.presentInfo(alertFactory.makeNoticeRequest(notice))
        }
    }

    /// Codex accounts are saved `auth.json` snapshots, switched and added through `AccountsController`.
    private func performCodexAction(_ action: ProviderAction) {
        switch action {
        case let .switchAccount(id):
            guard let account = accountsController.accounts.first(where: { $0.id == id }) else { return }
            recordMenuAction("switchAccount")
            diagnosticEventRecorder.recordSwitchAccount(targetAccountID: account.id)
            requestSwitch(to: account)
        case .addAccount:
            addCodexAccount()
        case let .removeAccount(id):
            removeCodexAccount(id)
        case .useResetCredit:
            useCodexResetCredit()
        case .connect, .allowKeychainAccess, .cancelSignIn, .disconnect:
            break
        }
    }

    private func useCodexResetCredit() {
        recordMenuAction("useResetCredit")
        let request = alertFactory.makeUseResetCreditRequest(accountsController.activeAccount?.usage?.resetCredits)
        guard alertPresenter.presentConfirmation(request) else { return }
        tasks.start { [weak self] in
            guard let self else { return }
            let result = await accountsController.useResetCredit()
            alertPresenter.presentInfo(alertFactory.makeResetCreditResultRequest(result))
        }
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

    private func rebuildMenu(using state: MenuBarMenuState? = nil) {
        let state = state ?? menuState()
        let menu = statusItemRuntime.menu ?? NSMenu()
        menuBuilder.populate(menu: menu, state: state, target: self)
        statusItemRuntime.menu = menu
        menuBuiltAt = state.now
    }

    func menuState() -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: accountsController.activeAccount,
            inactiveAccounts: accountsController.sortedInactiveAccounts,
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
            loginItemState: loginItemController.state(),
            tokenUsageEnabled: tokenUsagePreferences.isEnabled,
            tokenUsageCard: makeTokenUsageCard(),
            providerUsage: providerUsageRuntime.states,
            toolOrder: menuDisplaySettings.toolOrder,
            masksEmails: menuDisplaySettings.masksEmails,
            showsModelLimits: claudeUsageSettings.showsModelLimits,
            appIconColor: appIconPreferences.appIconColor,
            now: now()
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

    private func refreshProviderUsageIfDue(forcing forcedProvider: UsageProvider? = nil) {
        tasks.start { [weak self] in
            await self?.providerUsageRuntime.refreshIfDue(forcing: forcedProvider)
            await self?.providerUsageRuntime.renewLiveSignInsIfNeeded()
        }
    }

    /// Rebuilding an open menu makes it jump, so menu-only content rebuilds after the menu closes, or right before it next opens.
    private func rebuildMenuWhenSafe() {
        guard !statusItemRuntime.isMenuTrackingOpen else {
            rebuildsMenuAfterClose = true
            return
        }
        rebuildsMenuBeforeOpen = true
    }

    /// Reset countdowns are measured from when the menu was built, so a menu built a while ago is rebuilt as it opens.
    private func rebuildDeferredMenuIfNeeded() {
        let showsStaleTimes = menuBuiltAt.map { now().timeIntervalSince($0) >= Self.menuTimesStaleAfter } ?? false
        guard rebuildsMenuBeforeOpen || showsStaleTimes else { return }
        rebuildsMenuBeforeOpen = false
        rebuildMenu()
    }

    private static let menuTimesStaleAfter: TimeInterval = 30

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
        guard !accountsController.isApplyingResetCredit else {
            alertPresenter.presentInfo(alertFactory.makeResetInProgressRequest())
            return
        }
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        let request = alertFactory.makeSwitchAccountRequest(
            accountLabel: codexAccountLabel(account.id),
            runningCLISessions: runningCLISessions
        )

        guard alertPresenter.presentConfirmation(request) else { return }
        beginLocalSwitch(to: account)
    }

    private func beginIsolatedAddAccount() async {
        do {
            let session = try await accountsController.startIsolatedAddAccountFlow()
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

            handleAddAccountCompletion(result)
        } catch {
            handleAddAccountFailure(accountActionFlow.resolveAddAccountStartFailure(error))
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
            accountLabel: codexAccountLabel(account.id),
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

    private func handleAddAccountCompletion(_ result: MenuBarAddAccountSignInPanelResult) {
        let flowResult: AccountActionFlow.AddAccountResult
        switch result {
        case .completed(let account):
            flowResult = .completed(account)
        case .failed(let error):
            flowResult = .failed(error)
        case .cancelled:
            flowResult = .cancelled
        }

        switch accountActionFlow.resolveAddAccountCompletion(flowResult) {
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
        case .offerSignInRetry(let outcome):
            let request = alertFactory.makeAddAccountSignInRetryRequest(outcome: outcome)
            guard alertPresenter.presentConfirmation(request) else { return }
            tasks.start { [weak self] in await self?.beginIsolatedAddAccount() }
        case .showError(let message):
            alertPresenter.presentInfo(alertFactory.makeErrorRequest(message: message))
        case .showUnsafeAuthChange:
            alertPresenter.presentInfo(alertFactory.makeAddAccountUnsafeAuthChangeRequest())
        case .showSaveFailure:
            alertPresenter.presentInfo(alertFactory.makeAddAccountSaveFailureRequest())
        case .showAccountAlreadySaved(let accountID):
            alertPresenter.presentInfo(alertFactory.makeAccountAlreadySavedRequest(accountLabel: codexAccountLabel(accountID)))
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
        let interval = TimeInterval(menuDisplaySettings.refreshIntervalMinutes * 60)
        autoRefreshTimer = Timer.repeatingInCommonModes(interval: interval) { [weak self] in
            self?.tasks.start { await self?.performScheduledRefresh() }
        }
    }

    func performScheduledRefresh() async {
        refreshProviderUsageIfDue()
        tasks.start { [weak self] in await self?.providerUsageRuntime.refreshInactiveAccountsIfDue() }
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
            _ = menuDisplaySettings.toolOrder
            _ = menuDisplaySettings.masksEmails
            _ = statusItemSettings.sessionAccentColor
            _ = statusItemSettings.weeklyAccentColor
            _ = statusItemSettings.usesOneUsageColor
            _ = statusItemSettings.usagePercentMode
            _ = statusItemSettings.usageMeterLayout
            _ = statusItemSettings.pacingMarkersEnabled
            _ = appIconPreferences.appIconColor
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

    /// Asks to add a Codex account only on a first run: no saved Codex account and no other tool connected.
    private func promptForEmptyStateIfNeeded() {
        guard allowsEmptyStatePrompt, !providerUsageRuntime.hasConnectedTool else { return }
        guard accountsController.accounts.isEmpty, !accountsController.isBusy, !hasPromptedForEmptyState else { return }
        hasPromptedForEmptyState = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.accountsController.accounts.isEmpty, !self.accountsController.isBusy,
                  !self.providerUsageRuntime.hasConnectedTool,
                  self.alertPresenter.presentConfirmation(self.alertFactory.makeFirstRunAddAccountRequest()) else { return }
            self.addCodexAccount()
        }
    }

    private func statusItemPresentation(for state: MenuBarMenuState) -> StatusItemRuntimePresentation {
        StatusItemRuntimePresentation(
            source: state.statusItemSource,
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
