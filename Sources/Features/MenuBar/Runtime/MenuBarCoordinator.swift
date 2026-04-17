import AppKit
import Observation
import OSLog

private let menuBarCoordinatorLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "MenuBarCoordinator")

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private static let liveProofLayer = "live_ui"
    private static let hoverInvariantIDs = ["menubar.text_on_hover.stays_visible_inside_resized_bounds"]
    private static let switchInvariantIDs = ["accounts.switch_account.menu_action_changes_active_account"]

    private let statusItem: NSStatusItem
    private let store: MenuBarAccountsStore
    private let settings: AppSettings
    private let iconRenderer: StatusBarIconRenderer
    private let cliProcessInspector: CodexCLIProcessInspector
    private let alertPresenter: MenuBarAlertPresenter
    private let alertFactory: MenuBarAlertFactory
    private let validationSink: MenuBarValidationSink?
    private let validationScenario: String?
    private let allowsEmptyStatePrompt: Bool
    private let menuBuilder = MenuBarMenuBuilder()
    private var autoRefreshTimer: Timer?
    private var pendingSignInMonitorTimer: Timer?
    private var wakeRefreshTask: Task<Void, Never>?
    private var hoverActivationTimer: Timer?
    private var hoverExitValidationTimer: Timer?
    private var hoverPollingTimer: Timer?
    private var hoverTracker: StatusItemHoverTracker?
    private var hasPromptedForEmptyState = false
    private var isObservingSettings = false
    private var isObservingStore = false
    private var isMenuOpen = false
    private var isStatusItemHovered = false
    private var isPointerInsideStatusItem = false
    private var keepsStatusTitleWhileMenuOpen = false
    private var keepsStatusTitleForNextMenuOpen = false
    private var lastMenuAction: String?
    private var lastSwitchTargetName: String?
    private var lastConfirmationRequest: String?
    private var lastConfirmationAccepted: Bool?
    private var lastRenderedStatusTitleVisible: Bool?
    private var lastObservedActiveAccountID: UUID?
    private var lastObservedActiveAccountName: String?
    private var pendingSwitchValidationTargetID: UUID?
    private var pendingSwitchValidationTargetName: String?

    init(
        statusItem: NSStatusItem,
        store: MenuBarAccountsStore,
        settings: AppSettings,
        iconRenderer: StatusBarIconRenderer = StatusBarIconRenderer(),
        cliProcessInspector: CodexCLIProcessInspector = CodexCLIProcessInspector(),
        alertPresenter: MenuBarAlertPresenter,
        alertFactory: MenuBarAlertFactory = MenuBarAlertFactory(),
        validationSink: MenuBarValidationSink? = nil,
        validationScenario: String? = MenuBarValidationConfiguration.scenario(),
        allowsEmptyStatePrompt: Bool = true
    ) {
        self.statusItem = statusItem
        self.store = store
        self.settings = settings
        self.iconRenderer = iconRenderer
        self.cliProcessInspector = cliProcessInspector
        self.alertPresenter = alertPresenter
        self.alertFactory = alertFactory
        self.validationSink = validationSink
        self.validationScenario = validationScenario
        self.allowsEmptyStatePrompt = allowsEmptyStatePrompt
    }

    func start() {
        configureStatusItemButton()
        lastObservedActiveAccountID = store.activeAccountID
        lastObservedActiveAccountName = store.activeAccount?.name
        startObservingStore()
        startObservingSettings()
        updateStatusItemAppearance()
        rebuildMenu()
        scheduleAutoRefresh()
        startHoverPolling()
        syncBackgroundState()
    }

    func invalidate() {
        autoRefreshTimer?.invalidate()
        pendingSignInMonitorTimer?.invalidate()
        wakeRefreshTask?.cancel()
        hoverActivationTimer?.invalidate()
        hoverExitValidationTimer?.invalidate()
        hoverPollingTimer?.invalidate()
        hoverTracker?.invalidate()
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
    func addCurrentAccount() {
        recordMenuAction("addCurrentAccount")
        let request = alertFactory.makeSaveCurrentAccountRequest(activeAccountEmail: store.activeAccount?.email)

        guard let name = alertPresenter.presentTextInput(request) else { return }
        Task { await store.saveCurrentAccountSnapshot(named: name) }
    }

    @objc
    func signInAnotherAccount() {
        recordMenuAction("signInAnotherAccount")
        menuBarCoordinatorLogger.log("signInAnotherAccount action invoked")
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        menuBarCoordinatorLogger.log("Running CLI sessions before sign-in-another: \(runningCLISessions, privacy: .public)")

        let request = alertFactory.makeSignInAnotherRequest(runningCLISessions: runningCLISessions)

        menuBarCoordinatorLogger.log("Presenting sign-in-another confirmation alert")
        guard let name = alertPresenter.presentTextInput(request) else {
            menuBarCoordinatorLogger.log("Sign-in-another flow cancelled from alert")
            return
        }

        menuBarCoordinatorLogger.log("Dispatching sign-in-another task to store")
        Task { await store.startSignInAnotherAccountFlow(named: name) }
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
    func switchAccount(_ sender: NSMenuItem) {
        guard
            let idString = sender.representedObject as? String,
            let id = UUID(uuidString: idString),
            let account = store.accounts.first(where: { $0.id == id })
        else {
            return
        }

        recordMenuAction("switchAccount", payload: ["targetName": account.name])
        lastSwitchTargetName = account.name
        requestSwitch(to: account)
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
        isMenuOpen = true
        keepsStatusTitleWhileMenuOpen = keepsStatusTitleForNextMenuOpen || isStatusItemHovered
        keepsStatusTitleForNextMenuOpen = false
        recordValidationEvent(
            "menu_opened",
            step: "menu_open",
            payload: ["menuItemCount": String(statusItem.menu?.items.count ?? 0)]
        )
        updateStatusItemAppearance()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        store.refreshActiveAccount()
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        keepsStatusTitleWhileMenuOpen = false
        updateStatusItemAppearance()
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

    private func rebuildMenu() {
        let state = menuState()
        let menu = statusItem.menu ?? NSMenu()
        menuBuilder.populate(menu: menu, state: state, target: self)
        statusItem.menu = menu
        recordValidationSnapshot(for: state)
    }

    private func menuState() -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: store.activeAccount,
            inactiveAccounts: store.sortedInactiveAccounts,
            visibleInactiveAccountCount: settings.visibleInactiveAccountCount,
            visibleInactiveAccountCountOptions: settings.visibleInactiveAccountCountOptions,
            refreshIntervalMinutes: settings.refreshIntervalMinutes,
            refreshIntervalOptions: settings.refreshIntervalOptions,
            statusBarMonochrome: settings.statusBarMonochrome,
            statusBarIndicatorStyle: settings.statusBarIndicatorStyle,
            statusBarDisplayMode: settings.statusBarDisplayMode,
            isBusy: store.isBusy,
            statusMessage: store.statusMessage
        )
    }

    private func requestSwitch(to account: CodexAccount) {
        lastConfirmationRequest = "switchAccount"
        recordValidationEvent(
            "switch_confirmation_presented",
            step: "switch_confirmation",
            payload: ["targetName": account.name]
        )
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
        pendingSwitchValidationTargetID = account.id
        pendingSwitchValidationTargetName = account.name
        recordValidationEvent(
            "switch_workflow_started",
            step: "switch_workflow_start",
            invariantIds: Self.switchInvariantIDs,
            payload: ["targetName": account.name]
        )
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
        let interval = TimeInterval(settings.refreshIntervalMinutes * 60)
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
                await store.refreshAccountData(for: activeAccount)
            }
        }
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }
        let primary = store.activeAccount?.rateLimits?.primary?.displayedUsedPercent()
        let secondary = store.activeAccount?.rateLimits?.secondary?.displayedUsedPercent()
        applyStatusItemAppearance(
            to: button,
            primary: primary,
            secondary: secondary
        )
        recordStatusTitleVisibilityTransition(
            isVisible: shouldShowStatusTitle,
            displayedTitle: shouldShowStatusTitle ? button.title : nil
        )
        recordValidationSnapshot(for: menuState())
    }

    private func applyStatusItemAppearance(to button: NSStatusBarButton, primary: Int?, secondary: Int?) {
        button.image = iconRenderer.makeImage(
            style: settings.statusBarIndicatorStyle,
            primaryPercent: primary,
            secondaryPercent: secondary,
            monochrome: settings.statusBarMonochrome
        )
        button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        if shouldShowStatusTitle {
            let title = hoverStatusTitle(primary: primary, secondary: secondary)
            button.imagePosition = .imageLeading
            button.title = title
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            )
        } else {
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
        }
        button.toolTip = statusItemTooltip(primary: primary, secondary: secondary)
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
            _ = store.hasPendingSignedInAccount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleStoreChange()
                self.observeStoreChanges()
            }
        }
    }

    private func handleStoreChange() {
        recordActiveAccountTransitionIfNeeded()
        if !store.accounts.isEmpty {
            hasPromptedForEmptyState = false
        }
        updateStatusItemAppearance()
        rebuildMenu()
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
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleSettingsChange()
                self.observeSettingsChanges()
            }
        }
    }

    private func handleSettingsChange() {
        updateStatusItemAppearance()
        scheduleAutoRefresh()
        rebuildMenu()
    }

    private func animateStatusItemAppearanceUpdate() {
        updateStatusItemAppearance()
    }

    private var shouldShowStatusTitle: Bool {
        StatusItemTitleVisibilityPolicy(
            displayMode: menuState().effectiveStatusBarDisplayMode,
            isStatusItemHovered: isStatusItemHovered,
            isMenuOpen: isMenuOpen,
            keepsStatusTitleWhileMenuOpen: keepsStatusTitleWhileMenuOpen
        ).shouldShowTitle
    }

    private func statusItemTooltip(primary: Int?, secondary: Int?) -> String? {
        let _ = primary
        let _ = secondary
        return statusItemTooltipText(for: store.activeAccount)
    }

    private func hoverStatusTitle(primary: Int?, secondary: Int?) -> String {
        let _ = primary
        let _ = secondary
        return statusItemHoverTitle(for: store.activeAccount)
    }

    private func configureStatusItemButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = nil
        button.sendAction(on: [])
        button.imageHugsTitle = true
        if hoverTracker == nil {
            let tracker = StatusItemHoverTracker(button: button)
            tracker.onHoverChanged = { [weak self] isHovered in
                guard let self else { return }
                if isHovered {
                    self.handleStatusItemHoverEnter()
                } else {
                    self.scheduleStatusItemHoverCancellation()
                }
            }
            hoverTracker = tracker
        }
        hoverTracker?.installIfNeeded()
    }

    private func startHoverPolling() {
        hoverPollingTimer?.invalidate()
        hoverPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncStatusItemPointerState()
            }
        }
    }

    private func syncStatusItemPointerState() {
        let isPointerInside = isPointerInsideButtonBounds
        guard isPointerInside != isPointerInsideStatusItem else { return }
        isPointerInsideStatusItem = isPointerInside
        if isPointerInside {
            handleStatusItemHoverEnter()
        } else {
            scheduleStatusItemHoverCancellation()
        }
    }

    private func handleStatusItemHoverEnter() {
        hoverExitValidationTimer?.invalidate()
        guard !isMenuOpen else {
            if !isStatusItemHovered {
                isStatusItemHovered = true
                recordValidationEvent(
                    "status_item_hover_entered",
                    step: "hover_enter",
                    invariantIds: Self.hoverInvariantIDs
                )
            }
            updateStatusItemAppearance()
            return
        }
        hoverActivationTimer?.invalidate()
        hoverActivationTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isMenuOpen else { return }
                guard !self.isStatusItemHovered else { return }
                self.isStatusItemHovered = true
                self.recordValidationEvent(
                    "status_item_hover_entered",
                    step: "hover_enter",
                    invariantIds: Self.hoverInvariantIDs
                )
                self.animateStatusItemAppearanceUpdate()
            }
        }
    }

    private func scheduleStatusItemHoverCancellation() {
        hoverExitValidationTimer?.invalidate()
        recordValidationEvent(
            "status_item_hover_exit_scheduled",
            step: "hover_exit_schedule",
            invariantIds: Self.hoverInvariantIDs
        )
        hoverExitValidationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelStatusItemHover()
            }
        }
    }

    private func cancelStatusItemHover() {
        hoverActivationTimer?.invalidate()
        hoverActivationTimer = nil
        hoverExitValidationTimer?.invalidate()
        guard shouldEndStatusItemHover else { return }
        guard isStatusItemHovered else { return }
        isStatusItemHovered = false
        recordValidationEvent(
            "status_item_hover_exited",
            step: "hover_exit",
            invariantIds: Self.hoverInvariantIDs
        )
        animateStatusItemAppearanceUpdate()
    }

    private func handleStatusItemMouseDown() {
        keepsStatusTitleForNextMenuOpen = shouldShowStatusTitle
    }

    private var shouldEndStatusItemHover: Bool {
        !isPointerInsideButtonBounds
    }

    private var isPointerInsideButtonBounds: Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let pointerLocation = NSEvent.mouseLocation
        let windowLocation = window.convertPoint(fromScreen: pointerLocation)
        let buttonLocation = button.convert(windowLocation, from: nil)
        return !StatusItemHoverExitPolicy.shouldEndHover(
            pointerLocation: buttonLocation,
            in: button.bounds
        )
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
                    menu: statusItem.menu,
                    statusItemButton: statusItem.button,
                    isStatusItemHovered: isStatusItemHovered,
                    shouldShowStatusTitle: shouldShowStatusTitle,
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
                    payload: payload
                )
            )
        } catch {
            menuBarCoordinatorLogger.error("Failed to record validation event: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordStatusTitleVisibilityTransition(isVisible: Bool, displayedTitle: String?) {
        defer { lastRenderedStatusTitleVisible = isVisible }
        guard let lastRenderedStatusTitleVisible else { return }
        guard lastRenderedStatusTitleVisible != isVisible else { return }

        if isVisible {
            recordValidationEvent(
                "status_item_title_became_visible",
                step: "hover_title_visible",
                invariantIds: Self.hoverInvariantIDs,
                payload: ["displayedTitle": displayedTitle ?? ""]
            )
        } else {
            recordValidationEvent(
                "status_item_title_hidden",
                step: "hover_title_hidden",
                invariantIds: Self.hoverInvariantIDs
            )
        }
    }

    private func syncBackgroundState() {
        schedulePendingSignInMonitorIfNeeded()
        promptForEmptyStateIfNeeded()
    }

    private func schedulePendingSignInMonitorIfNeeded() {
        guard store.hasPendingSignedInAccount else {
            pendingSignInMonitorTimer?.invalidate()
            pendingSignInMonitorTimer = nil
            return
        }

        guard pendingSignInMonitorTimer == nil else { return }

        pendingSignInMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.store.completePendingSignedInAccountIfNeeded()
                if !self.store.hasPendingSignedInAccount {
                    self.pendingSignInMonitorTimer?.invalidate()
                    self.pendingSignInMonitorTimer = nil
                }
            }
        }
    }

    private func promptForEmptyStateIfNeeded() {
        guard allowsEmptyStatePrompt else { return }
        guard store.accounts.isEmpty, !store.isBusy, !store.hasPendingSignedInAccount, !hasPromptedForEmptyState else { return }
        hasPromptedForEmptyState = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.store.accounts.isEmpty, !self.store.isBusy, !self.store.hasPendingSignedInAccount else { return }
            self.addCurrentAccount()
        }
    }
}
