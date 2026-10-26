import AppKit
import Observation
import OSLog

private let menuBarCoordinatorLogger = Logger(subsystem: "com.raphhgg.rusage", category: "MenuBarCoordinator")

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let statusItemRuntime: StatusItemRuntime
    private let shortcutRuntime: GlobalShortcutRuntime
    private let accountsController: MenuBarAccounts
    private let settings: SettingsModel
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
            guard let self else { return }
            // The open card redraws from its model, so progress shows without rebuilding the menu.
            tokenUsageCard.card = makeTokenUsageCard()
            rebuildMenuWhenSafe()
        }
    )
    private lazy var tokenUsageCard = TokenUsageCardModel(card: makeTokenUsageCard(), theme: settings.general.theme, settings: settings)
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
        settings: SettingsModel,
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
        self.settings = settings
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

    func presentNotice(_ request: MenuBarInfoAlertRequest) {
        alertPresenter.presentInfo(request)
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
        settings.codex.isConnected = true
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
        settings.general.refreshIntervalMinutes = minutes
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
        settings.menuBar.statusBarIndicatorStyle = style
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
            settings.menuBar.statusBarDisplayMode = .iconOnly
            return
        }
        settings.menuBar.statusBarDisplayMode = mode
    }

    @objc
    func toggleTokenUsage(_ sender: NSMenuItem) {
        recordMenuAction("toggleTokenUsage")
        settings.tokenUsage.isEnabled.toggle()
        tokenUsageRuntime.handleEnabledChange(
            isEnabled: settings.tokenUsage.isEnabled,
            period: Self.tokenUsagePeriod,
            peakScope: settings.tokenUsage.peakScope
        )
        rebuildMenu()
    }

    @objc
    func toggleShowsModelLimits(_ sender: NSMenuItem) {
        recordMenuAction("toggleShowsModelLimits")
        settings.claude.update { $0.showsModelLimits.toggle() }
        rebuildMenu()
    }

    @objc
    func selectTheme(_ sender: NSMenuItem) {
        recordMenuAction("selectTheme")
        guard
            let rawValue = sender.representedObject as? String,
            let theme = AppTheme(rawValue: rawValue)
        else {
            return
        }
        settings.general.theme = theme
        tokenUsageCard.theme = theme
        rebuildMenu()
    }

    @objc
    func toggleMasksEmails(_ sender: NSMenuItem) {
        recordMenuAction("toggleMasksEmails")
        settings.general.masksEmails.toggle()
    }

    @objc
    func reorderTools(_ sender: NSMenuItem) {
        recordMenuAction("reorderTools")
        guard let order = sender.representedObject as? [UsageProvider] else { return }
        settings.general.toolOrder = order
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
        settings.menuBar.usagePercentMode = mode
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
        settings.menuBar.usageMeterLayout = layout
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
        settings.menuBar.usesOneUsageColor.toggle()
    }

    @objc
    func resetUsageColors(_ sender: NSMenuItem) {
        recordMenuAction("resetUsageColors")
        settings.menuBar.resetUsageColors()
        if let colorPanelTarget {
            NSColorPanel.shared.color = resolvedUsageColor(for: colorPanelTarget)
        }
    }

    @objc
    func togglePacingMarkers(_ sender: NSMenuItem) {
        recordMenuAction("togglePacingMarkers")
        settings.menuBar.pacingMarkersEnabled.toggle()
    }

    @objc
    func configureRevealStatusItemTitleShortcut(_ sender: NSMenuItem) {
        recordMenuAction("configureRevealStatusItemTitleShortcut")
        let previousShortcut = settings.menuBar.revealStatusItemTitleShortcut
        try? shortcutRuntime.apply(shortcut: nil)

        switch shortcutCapturePanelPresenter.presentShortcutCapture(
            currentShortcut: settings.menuBar.revealStatusItemTitleShortcut
        ) {
        case .cancelled:
            try? shortcutRuntime.apply(shortcut: previousShortcut)
            return
        case .saved(let shortcut):
            do {
                try shortcutRuntime.apply(shortcut: shortcut)
                settings.menuBar.revealStatusItemTitleShortcut = shortcut
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
        if let prompt = provider.copy.prompt(for: action) {
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
        case .connect:
            showCodex()
        case .disconnect:
            recordMenuAction("hideCodex")
            settings.codex.isConnected = false
        case .allowKeychainAccess, .signIn, .signOut:
            break
        }
    }

    /// Shows a hidden Codex card and reads it again. With no saved Codex account, adds one.
    private func showCodex() {
        guard !accountsController.accounts.isEmpty else {
            addCodexAccount()
            return
        }
        recordMenuAction("showCodex")
        settings.codex.isConnected = true
        tasks.start { [weak self] in await self?.refreshCodex(includingSavedAccounts: true) }
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
            refreshIntervalMinutes: settings.general.refreshIntervalMinutes,
            refreshIntervalOptions: GeneralSettings.refreshIntervalOptions,
            statusBarIndicatorStyle: settings.menuBar.statusBarIndicatorStyle,
            statusBarDisplayMode: settings.menuBar.statusBarDisplayMode,
            revealStatusItemTitleShortcut: settings.menuBar.revealStatusItemTitleShortcut,
            sessionAccentColor: settings.menuBar.sessionAccentColor?.nsColor,
            weeklyAccentColor: settings.menuBar.effectiveWeeklyAccentColor?.nsColor,
            usesOneUsageColor: settings.menuBar.usesOneUsageColor,
            hasCustomUsageColors: settings.menuBar.hasCustomUsageColors,
            usagePercentMode: settings.menuBar.usagePercentMode,
            usageMeterLayout: settings.menuBar.usageMeterLayout,
            pacingMarkersEnabled: settings.menuBar.pacingMarkersEnabled,
            isBusy: accountsController.isBusy,
            statusMessage: accountsController.statusMessage,
            loginItemState: loginItemController.state(),
            tokenUsageEnabled: settings.tokenUsage.isEnabled,
            tokenUsage: currentTokenUsageCard(),
            providerUsage: providerUsageRuntime.states,
            toolOrder: settings.general.toolOrder,
            masksEmails: settings.general.masksEmails,
            hidesCodex: !settings.codex.isConnected,
            showsModelLimits: settings.claude.value.showsModelLimits,
            theme: settings.general.theme,
            now: now()
        )
    }

    private func makeTokenUsageCard() -> TokenUsageMenuCard {
        TokenUsageMenuCard.make(period: Self.tokenUsagePeriod, loadState: tokenUsageRuntime.loadState, now: now())
    }

    private func currentTokenUsageCard() -> TokenUsageCardModel? {
        guard settings.tokenUsage.isEnabled else { return nil }
        let card = makeTokenUsageCard()
        if tokenUsageCard.card != card {
            tokenUsageCard.card = card
        }
        if tokenUsageCard.theme != settings.general.theme {
            tokenUsageCard.theme = settings.general.theme
        }
        return tokenUsageCard
    }

    /// Token usage and provider usage only appear inside the menu, so opening it is the moment to bring them up to date.
    private func refreshMenuUsageIfNeeded() {
        refreshProviderUsageIfDue()
        guard settings.tokenUsage.isEnabled else {
            tokenUsageRuntime.cancel()
            return
        }

        tokenUsageRuntime.refreshIfNeeded(period: Self.tokenUsagePeriod, peakScope: settings.tokenUsage.peakScope)
    }

    private func refreshProviderUsageIfDue(forcing forcedProvider: UsageProvider? = nil) {
        tasks.start { [weak self] in
            await self?.providerUsageRuntime.refreshIfDue(forcing: forcedProvider)
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
    /// The Token Usage card always shows the last 30 days.
    private static let tokenUsagePeriod = CodexTokenUsagePeriod.last30Days

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
            try shortcutRuntime.apply(shortcut: settings.menuBar.revealStatusItemTitleShortcut)
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
        case .showCodexAppNotFound:
            alertPresenter.presentInfo(alertFactory.makeCodexAppNotFoundForAddRequest())
        case .showUnsafeAuthChange:
            alertPresenter.presentInfo(alertFactory.makeAddAccountUnsafeAuthChangeRequest())
        case .showSaveFailure:
            alertPresenter.presentInfo(alertFactory.makeAddAccountSaveFailureRequest())
        case .showAccountAlreadySaved(let accountID):
            alertPresenter.presentInfo(alertFactory.makeAccountAlreadySavedRequest(accountLabel: codexAccountLabel(accountID)))
        }
    }

    private func beginLocalSwitch(to account: CodexAccount) {
        tasks.start { [weak self] in
            guard let self, await accountsController.switchToAccount(account).relaunch == .appNotFound else { return }
            alertPresenter.presentInfo(alertFactory.makeCodexAppNotFoundAfterSwitchRequest())
        }
    }

    private func recordMenuAction(_ name: String) {
        diagnosticEventRecorder.recordMenuAction(name)
    }

    private func scheduleAutoRefresh() {
        autoRefreshTimer?.invalidate()
        let interval = TimeInterval(settings.general.refreshIntervalMinutes * 60)
        autoRefreshTimer = Timer.repeatingInCommonModes(interval: interval) { [weak self] in
            self?.tasks.start { await self?.performScheduledRefresh() }
        }
    }

    func performScheduledRefresh() async {
        refreshProviderUsageIfDue()
        await refreshCodex(includingSavedAccounts: true)
    }

    /// Reads the Codex limits unless the Codex card is hidden. At launch only the account in use is read.
    func refreshCodex(includingSavedAccounts: Bool) async {
        guard settings.codex.isConnected, !accountsController.isBusy else { return }
        if let activeAccount = accountsController.activeAccount {
            switch await accountsController.refreshAccountData(for: activeAccount) {
            case .refreshed:
                diagnosticEventRecorder.recordRefresh(resultCategory: "refreshed")
            case .failed:
                diagnosticEventRecorder.recordRefresh(resultCategory: "failed")
            }
        }

        if includingSavedAccounts {
            await accountsController.refreshInactiveSavedAccountsMetadata()
        }
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
            // Token Usage is left out: its card redraws itself, and rebuilding would make an open menu jump.
            _ = settings.general
            _ = settings.menuBar
            _ = settings.codex
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
            indicatorStyle: settings.menuBar.statusBarIndicatorStyle,
            displayMode: state.effectiveStatusBarDisplayMode,
            percentMode: state.usagePercentMode
        )
    }

    /// The color a usage bar shows: the custom one, otherwise the theme's color for Codex.
    private func resolvedUsageColor(for target: UsageColorTarget) -> NSColor {
        switch target {
        case .session:
            settings.menuBar.sessionAccentColor?.nsColor ?? themeUsageColor(for: .session)
        case .weekly:
            settings.menuBar.effectiveWeeklyAccentColor?.nsColor ?? themeUsageColor(for: .weekly)
        }
    }

    private func themeUsageColor(for target: UsageColorTarget) -> NSColor {
        let palette = ThemePalette(theme: settings.general.theme)
        switch target {
        case .session: return palette.sessionColor(for: .codex)
        case .weekly: return palette.weeklyColor(for: .codex)
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
            settings.menuBar.sessionAccentColor = color.isEqualToStatusItemAccentColor(themeUsageColor(for: .session))
                ? nil
                : StatusItemAccentColor(nsColor: color)
        case .weekly:
            guard !color.isEqualToStatusItemAccentColor(resolvedUsageColor(for: .weekly)) else { return }
            settings.menuBar.weeklyAccentColor = StatusItemAccentColor(nsColor: color)
            settings.menuBar.usesOneUsageColor = false
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
