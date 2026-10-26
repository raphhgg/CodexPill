import AppKit
import Observation
import OSLog

private let menuBarCoordinatorLogger = Logger(subsystem: "com.raphhgg.rusage", category: "MenuBarCoordinator")

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate, NSMenuItemValidation, SettingsActions {
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
    private var wakeRefreshTask: Task<Void, Never>?
    private let tasks = TrackedTasks()
    private var rebuildsMenuAfterClose = false
    private var opensSettingsAfterClose = false
    private var rebuildsMenuBeforeOpen = false
    private var menuBuiltAt: Date?
    private let now: () -> Date
    private var hasPromptedForEmptyState = false
    private var isObservingSettings = false
    private var isObservingStore = false
    private var activeCodexSignInSession: CodexSignInSession?
    private lazy var tokenUsageRuntime = TokenUsageMenuRuntime(
        provider: tokenUsageProvider,
        onStateChange: { [weak self] _ in
            guard let self else { return }
            // The open card redraws from its model, so progress shows without rebuilding the menu.
            tokenUsageCard.card = makeTokenUsageCard()
            rebuildMenuWhenSafe()
        }
    )
    /// The tools the menu showed when it was last built, in its order.
    private var tokenUsageTools = GeneralSettings.defaultToolOrder.map(\.tokenUsageTool)
    private lazy var tokenUsageCard = TokenUsageCardModel(card: makeTokenUsageCard(), theme: settings.general.theme, settings: settings)
    private let providerConnections: [any ProviderConnection]
    private lazy var providerUsageRuntime = ProviderUsageRuntime(
        connections: providerConnections,
        onChange: { [weak self] in
            guard let self else { return }
            let state = menuState()
            statusItemRuntime.update(presentation: statusItemPresentation(for: state))
            settingsWindowState.update(from: state)
            rebuildMenuWhenSafe()
        }
    )
    let settingsWindowState = SettingsWindowState()
    private(set) lazy var settingsWindow = SettingsWindow(
        settings: settings,
        state: settingsWindowState,
        actions: self,
        bringsAppForward: bringsSettingsForward
    )
    private let bringsSettingsForward: Bool

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
        bringsSettingsForward: Bool = true,
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
        self.bringsSettingsForward = bringsSettingsForward
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
        cancelActiveCodexSignIn()
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

    /// Signs in to another Codex account in the browser, then asks before it replaces the one on this Mac.
    private func signInToCodex() {
        recordMenuAction("signInToCodex")
        settings.codex.isConnected = true
        tasks.start { [weak self] in await self?.beginCodexSignIn() }
    }

    /// What alerts call a Codex account: its email, masked with Hide Emails, else its plan.
    private func codexAccountLabel(_ account: CodexAccount) -> String {
        if let email = account.email { return displayedEmail(email, masked: settings.general.masksEmails) }
        return planTag(for: .codex, planName: account.effectivePlanType).map { "Codex \($0)" } ?? "This Codex account"
    }

    /// ⌘, runs the Settings item while the menu still tracks, and an activation then is lost when the menu closes, so
    /// the window waits for that.
    @objc
    func openSettings() {
        recordMenuAction("openSettings")
        if statusItemRuntime.isMenuTrackingOpen {
            opensSettingsAfterClose = true
        } else {
            settingsWindow.show()
        }
    }

    func setTool(_ provider: UsageProvider, shown: Bool) {
        perform(shown ? .connect : .disconnect, on: provider)
    }

    /// Showing or hiding the card starts or stops its scan. Between the two visible modes the card redraws itself.
    func setTokenUsageDisplay(_ display: TokenUsageDisplay) {
        guard settings.tokenUsage.display != display else { return }
        recordMenuAction("setTokenUsageDisplay")
        let wasEnabled = settings.tokenUsage.isEnabled
        settings.tokenUsage.display = display
        if settings.tokenUsage.isEnabled != wasEnabled {
            tokenUsageRuntime.handleEnabledChange(
                isEnabled: settings.tokenUsage.isEnabled,
                period: Self.tokenUsagePeriod,
                peakScope: settings.tokenUsage.peakScope
            )
        }
        // On hover moves the breakdown into a side menu, so every change rebuilds the menu.
        rebuildMenu()
    }

    func setShowsModelLimits(_ isOn: Bool) {
        recordMenuAction("setShowsModelLimits")
        settings.claude.update { $0.showsModelLimits = isOn }
        rebuildMenu()
    }

    func recordRevealShortcut() {
        recordMenuAction("recordRevealShortcut")
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

    func settingsWindowDidBecomeKey() {
        settingsWindowState.update(from: menuState())
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

    /// Codex shows the one account `auth.json` signs in to, read and replaced through `AccountsController`.
    private func performCodexAction(_ action: ProviderAction) {
        switch action {
        case .addAccount:
            signInToCodex()
        case .useResetCredit:
            useCodexResetCredit()
        case .connect:
            showCodex()
        case .disconnect:
            recordMenuAction("hideCodex")
            settings.codex.isConnected = false
        case .signOut:
            signOutOfCodex()
        case .allowKeychainAccess, .signIn:
            break
        }
    }

    /// Asks first, since it signs the Codex app and CLI out too.
    private func signOutOfCodex() {
        guard !accountsController.isApplyingResetCredit else {
            alertPresenter.presentInfo(alertFactory.makeResetInProgressRequest())
            return
        }
        guard alertPresenter.presentConfirmation(alertFactory.makeCodexSignOutRequest()) else { return }
        recordMenuAction("signOutOfCodex")
        tasks.start { [weak self] in
            guard let self else { return }
            _ = await accountsController.signOut()
            presentPendingErrorIfNeeded()
        }
    }

    /// Shows a hidden Codex card and reads it again. Signed out of Codex, it signs in first.
    private func showCodex() {
        guard accountsController.activeAccount != nil else {
            signInToCodex()
            return
        }
        recordMenuAction("showCodex")
        settings.codex.isConnected = true
        tasks.start { [weak self] in await self?.refreshCodex() }
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

    /// Turning it on asks first. While it waits for approval or can't be set here, System Settings opens instead.
    func setLaunchAtLogin(_ isOn: Bool) {
        recordMenuAction("setLaunchAtLogin")
        switch (loginItemController.state(), isOn) {
        case (.disabled, true):
            guard alertPresenter.presentConfirmation(alertFactory.makeEnableLaunchAtLoginRequest()) else {
                settingsWindowState.update(from: menuState())
                return
            }
            setLaunchAtLoginEnabled(true)
        case (.enabled, false), (.requiresApproval, false):
            setLaunchAtLoginEnabled(false)
        case (.requiresApproval, true), (.unavailable, _):
            openLoginItemsSettings()
        case (.enabled, true), (.disabled, false):
            break
        }
    }

    func openLoginItemsSettings() {
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
        if opensSettingsAfterClose {
            opensSettingsAfterClose = false
            settingsWindow.show()
        }
    }

    /// Items keep the enabled state the builder gave them.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.isEnabled
    }

    private func rebuildMenu(using state: MenuBarMenuState? = nil) {
        let state = state ?? menuState()
        let menu = statusItemRuntime.menu ?? NSMenu()
        menuBuilder.populate(menu: menu, state: state, target: self)
        statusItemRuntime.menu = menu
        menuBuiltAt = state.now
        settingsWindowState.update(from: state)
    }

    func menuState() -> MenuBarMenuState {
        let state = MenuBarMenuState(
            activeAccount: accountsController.activeAccount,
            refreshIntervalMinutes: settings.general.refreshIntervalMinutes,
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
            tokenUsage: settings.tokenUsage.isEnabled ? tokenUsageCard : nil,
            providerUsage: providerUsageRuntime.states,
            toolOrder: settings.general.toolOrder,
            masksEmails: settings.general.masksEmails,
            hidesCodex: !settings.codex.isConnected,
            showsModelLimits: settings.claude.value.showsModelLimits,
            theme: settings.general.theme,
            now: now()
        )
        if state.tokenUsage != nil {
            // The card shows the tools the menu shows, in the menu's order.
            tokenUsageTools = state.toolSections.map(\.provider.tokenUsageTool)
            updateTokenUsageCard()
        }
        return state
    }

    private func makeTokenUsageCard() -> TokenUsageMenuCard {
        TokenUsageMenuCard.make(
            period: Self.tokenUsagePeriod,
            loadState: tokenUsageRuntime.loadState,
            shownTools: tokenUsageTools,
            now: now()
        )
    }

    private func updateTokenUsageCard() {
        let card = makeTokenUsageCard()
        if tokenUsageCard.card != card {
            tokenUsageCard.card = card
        }
        if tokenUsageCard.theme != settings.general.theme {
            tokenUsageCard.theme = settings.general.theme
        }
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

    private func beginCodexSignIn() async {
        do {
            let session = try await accountsController.startSignIn()
            activeCodexSignInSession = session

            let result = await panelPresenter.presentAddAccountSignIn(
                alertFactory.makeSignInRequest(prompt: session.prompt),
                waitForCompletion: { [accountsController] in
                    do {
                        return .success(try await accountsController.completeSignIn(session))
                    } catch {
                        return .failure(error)
                    }
                },
                onCancel: { [accountsController] in
                    accountsController.cancelSignIn(session)
                }
            )
            if activeCodexSignInSession === session {
                activeCodexSignInSession = nil
            }
            handleSignInCompletion(result)
        } catch {
            handleSignInFailure(accountActionFlow.resolveSignInFailure(error))
        }
    }

    private func cancelActiveCodexSignIn() {
        guard let session = activeCodexSignInSession else { return }
        activeCodexSignInSession = nil
        accountsController.cancelSignIn(session)
    }

    private func handleSignInCompletion(_ result: MenuBarAddAccountSignInPanelResult) {
        let flowResult: AccountActionFlow.SignInResult = switch result {
        case .completed(let signedIn): .completed(signedIn)
        case .failed(let error): .failed(error)
        case .cancelled: .cancelled
        }

        switch accountActionFlow.resolveSignInCompletion(flowResult) {
        case .confirmReplace(let signedIn):
            confirmReplacingCodexAccount(with: signedIn)
        case .handleFailure(let step):
            handleSignInFailure(step)
        case .none:
            break
        }
    }

    /// The new sign-in replaces `auth.json` only after the user agrees.
    private func confirmReplacingCodexAccount(with signedIn: CodexSignedInAccount) {
        guard !accountsController.isApplyingResetCredit else {
            alertPresenter.presentInfo(alertFactory.makeResetInProgressRequest())
            return
        }
        let request = alertFactory.makeReplaceCodexAccountRequest(
            newLabel: codexAccountLabel(signedIn.account),
            currentLabel: accountsController.activeAccount.map(codexAccountLabel),
            runningCLISessions: cliProcessInspector.runningCLISessionCount()
        )
        guard alertPresenter.presentConfirmation(request) else { return }
        recordMenuAction("useSignedInCodexAccount")
        tasks.start { [weak self] in
            guard let self else { return }
            let relaunch = await accountsController.use(signedIn)
            presentPendingErrorIfNeeded()
            if relaunch == .appNotFound {
                alertPresenter.presentInfo(alertFactory.makeCodexAppNotFoundAfterSignInRequest())
            }
        }
    }

    private func handleSignInFailure(_ step: AccountActionFlow.SignInFailureStep) {
        _ = accountsController.consumePendingErrorMessage()

        switch step {
        case .showSignInFailure(let outcome):
            alertPresenter.presentInfo(alertFactory.makeSignInFailureRequest(outcome: outcome))
        case .offerSignInRetry(let outcome):
            guard alertPresenter.presentConfirmation(alertFactory.makeSignInRetryRequest(outcome: outcome)) else { return }
            tasks.start { [weak self] in await self?.beginCodexSignIn() }
        case .showError(let message):
            alertPresenter.presentInfo(alertFactory.makeErrorRequest(message: message))
        case .showCodexAppNotFound:
            alertPresenter.presentInfo(alertFactory.makeCodexAppNotFoundForSignInRequest())
        case .showUnsafeAuthChange:
            alertPresenter.presentInfo(alertFactory.makeSignInUnsafeAuthChangeRequest())
        case .showAccountAlreadyInUse:
            alertPresenter.presentInfo(alertFactory.makeAccountAlreadyInUseRequest())
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
        await refreshCodex()
    }

    /// Reads the Codex limits unless the Codex card is hidden or Codex is signed out.
    func refreshCodex() async {
        guard settings.codex.isConnected, !accountsController.isBusy, accountsController.activeAccount != nil else { return }
        switch await accountsController.refreshAccountData() {
        case .refreshed:
            diagnosticEventRecorder.recordRefresh(resultCategory: "refreshed")
        case .failed:
            diagnosticEventRecorder.recordRefresh(resultCategory: "failed")
        }
    }

    private func startObservingStore() {
        guard !isObservingStore else { return }
        isObservingStore = true
        observeStoreChanges()
    }

    private func observeStoreChanges() {
        withObservationTracking {
            _ = accountsController.activeAccount
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
        if accountsController.activeAccount != nil {
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

    private func presentPendingErrorIfNeeded() {
        guard let message = accountsController.consumePendingErrorMessage() else { return }
        alertPresenter.presentInfo(alertFactory.makeErrorRequest(message: message))
    }

    private func syncBackgroundState() {
        promptForEmptyStateIfNeeded()
    }

    /// Asks to sign in to Codex only on a first run: Codex signed out and no other tool connected.
    private func promptForEmptyStateIfNeeded() {
        guard allowsEmptyStatePrompt, !providerUsageRuntime.hasConnectedTool else { return }
        guard accountsController.activeAccount == nil, !accountsController.isBusy, !hasPromptedForEmptyState else { return }
        hasPromptedForEmptyState = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.accountsController.activeAccount == nil, !self.accountsController.isBusy,
                  !self.providerUsageRuntime.hasConnectedTool,
                  self.alertPresenter.presentConfirmation(self.alertFactory.makeFirstRunAddAccountRequest()) else { return }
            self.signInToCodex()
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
}
