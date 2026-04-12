import AppKit
import OSLog

private let menuBarCoordinatorLogger = Logger(subsystem: "com.raphhgg.codex-switchboard", category: "MenuBarCoordinator")

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: MenuBarStore
    private let settings: AppSettings
    private let iconRenderer: StatusBarIconRenderer
    private let cliProcessInspector: CodexCLIProcessInspector
    private let alertPresenter: MenuBarAlertPresenter
    private let alertFactory: MenuBarAlertFactory
    private let validationSink: MenuBarValidationSink?
    private let menuBuilder = MenuBarMenuBuilder()
    private var autoRefreshTimer: Timer?
    private var pendingSignInMonitorTimer: Timer?
    private var wakeRefreshTask: Task<Void, Never>?
    private var hasPromptedForEmptyState = false

    init(
        statusItem: NSStatusItem,
        store: MenuBarStore,
        settings: AppSettings,
        iconRenderer: StatusBarIconRenderer = StatusBarIconRenderer(),
        cliProcessInspector: CodexCLIProcessInspector = CodexCLIProcessInspector(),
        alertPresenter: MenuBarAlertPresenter,
        alertFactory: MenuBarAlertFactory = MenuBarAlertFactory(),
        validationSink: MenuBarValidationSink? = nil
    ) {
        self.statusItem = statusItem
        self.store = store
        self.settings = settings
        self.iconRenderer = iconRenderer
        self.cliProcessInspector = cliProcessInspector
        self.alertPresenter = alertPresenter
        self.alertFactory = alertFactory
        self.validationSink = validationSink
    }

    func start() {
        updateStatusItemAppearance()
        rebuildMenu()
        scheduleAutoRefresh()
        syncBackgroundState()
    }

    func invalidate() {
        autoRefreshTimer?.invalidate()
        pendingSignInMonitorTimer?.invalidate()
        wakeRefreshTask?.cancel()
    }

    func handleStoreChange() {
        if !store.accounts.isEmpty {
            hasPromptedForEmptyState = false
        }
        updateStatusItemAppearance()
        rebuildMenu()
        presentPendingErrorIfNeeded()
        syncBackgroundState()
    }

    func handleSettingsChange() {
        updateStatusItemAppearance()
        scheduleAutoRefresh()
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        store.refreshActiveAccount()
        rebuildMenu()
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
        let request = alertFactory.makeSaveCurrentAccountRequest(activeAccountEmail: store.activeAccount?.email)

        guard let name = alertPresenter.presentTextInput(request) else { return }
        Task { await store.saveCurrentAccountSnapshot(named: name) }
    }

    @objc
    func signInAnotherAccount() {
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
    func selectRefreshInterval(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        settings.refreshIntervalMinutes = minutes
    }

    @objc
    func selectVisibleInactiveAccountCount(_ sender: NSMenuItem) {
        guard let count = sender.representedObject as? Int else { return }
        settings.visibleInactiveAccountCount = count
    }

    @objc
    func selectStatusBarStyle(_ sender: NSMenuItem) {
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
        settings.statusBarMonochrome.toggle()
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

        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        let request = alertFactory.makeSwitchAccountRequest(accountName: account.name, runningCLISessions: runningCLISessions)

        guard alertPresenter.presentConfirmation(request) else { return }
        Task { await store.switchToAccount(account) }
    }

    @objc
    func showAbout() {
        alertPresenter.presentInfo(alertFactory.makeAboutRequest())
    }

    @objc
    func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func rebuildMenu() {
        let state = menuState()
        statusItem.menu = menuBuilder.makeMenu(state: state, target: self)
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
            isBusy: store.isBusy,
            statusMessage: store.statusMessage
        )
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
        let primary = store.activeAccount?.rateLimits?.primary?.displayedUsedPercent()
        let secondary = store.activeAccount?.rateLimits?.secondary?.displayedUsedPercent()
        statusItem.button?.image = iconRenderer.makeImage(
            style: settings.statusBarIndicatorStyle,
            primaryPercent: primary,
            secondaryPercent: secondary,
            monochrome: settings.statusBarMonochrome
        )
        statusItem.button?.toolTip = statusItemTooltip(primary: primary, secondary: secondary)
    }

    private func statusItemTooltip(primary: Int?, secondary: Int?) -> String {
        let session = primary.map { "Session \($0)%" } ?? "Session --"
        let weekly = secondary.map { "Weekly \($0)%" } ?? "Weekly --"
        return "CodexPill\n\(session)\n\(weekly)"
    }

    private func presentPendingErrorIfNeeded() {
        guard let message = store.consumePendingErrorMessage() else { return }
        alertPresenter.presentInfo(alertFactory.makeErrorRequest(message: message))
    }

    private func recordValidationSnapshot(for state: MenuBarMenuState) {
        guard let validationSink else { return }

        do {
            try validationSink.record(MenuBarValidationSupport.makeSnapshot(state: state))
        } catch {
            menuBarCoordinatorLogger.error("Failed to record validation snapshot: \(error.localizedDescription, privacy: .public)")
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
        guard store.accounts.isEmpty, !store.isBusy, !store.hasPendingSignedInAccount, !hasPromptedForEmptyState else { return }
        hasPromptedForEmptyState = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.store.accounts.isEmpty, !self.store.isBusy, !self.store.hasPendingSignedInAccount else { return }
            self.addCurrentAccount()
        }
    }
}
