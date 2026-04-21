import AppKit
import Observation
import OSLog

private let menuBarCoordinatorLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "MenuBarCoordinator")

func preferredRemoteRateLimits(
    remote: CodexRateLimitSnapshot?,
    fallback: CodexRateLimitSnapshot?,
    candidateAccounts: [CodexAccount],
    baseAccount: CodexAccount,
    remoteEmail: String?
) -> CodexRateLimitSnapshot? {
    let resolvedFallback = bestRemoteRateLimitFallback(
        fallback: fallback,
        candidateAccounts: candidateAccounts,
        baseAccount: baseAccount,
        remoteEmail: remoteEmail
    )

    guard let remote else { return resolvedFallback }
    guard let resolvedFallback else { return remote }

    return CodexRateLimitSnapshot(
        limitID: preferredRemoteMetadataValue(remote.limitID, fallback: resolvedFallback.limitID),
        limitName: preferredRemoteMetadataValue(remote.limitName, fallback: resolvedFallback.limitName),
        planType: preferredRemoteMetadataValue(remote.planType, fallback: resolvedFallback.planType),
        primary: preferredRemoteRateLimitWindow(remote.primary, fallback: resolvedFallback.primary),
        secondary: preferredRemoteRateLimitWindow(remote.secondary, fallback: resolvedFallback.secondary),
        fetchedAt: max(remote.fetchedAt, resolvedFallback.fetchedAt)
    )
}

func preferredRemoteMetadataValue(
    _ remote: String?,
    fallback: String?
) -> String? {
    let trimmedRemote = remote?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmedRemote, !trimmedRemote.isEmpty {
        return trimmedRemote
    }
    return fallback
}

func bestRemoteRateLimitFallback(
    fallback: CodexRateLimitSnapshot?,
    candidateAccounts: [CodexAccount],
    baseAccount: CodexAccount,
    remoteEmail: String?
) -> CodexRateLimitSnapshot? {
    let matchOutcome = CodexAccountMatcher().match(
        liveStableAccountID: baseAccount.identity.stableAccountID,
        liveAuthPrincipalIdentity: baseAccount.identity.authPrincipalIdentity,
        liveWorkspaceIdentity: baseAccount.identity.workspaceIdentity,
        liveAuthFingerprint: baseAccount.identity.snapshotFingerprint,
        liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: remoteEmail) ?? baseAccount.resolvedRemoteIdentity,
        accounts: candidateAccounts
    )

    if let matchedID = matchOutcome.matchedAccountID,
       let matchedAccount = candidateAccounts.first(where: { $0.id == matchedID }),
       remoteRateLimitsContainMeaningfulData(matchedAccount.rateLimits) {
        return matchedAccount.rateLimits
    }

    return fallback
}

func remoteRateLimitsContainMeaningfulData(_ snapshot: CodexRateLimitSnapshot?) -> Bool {
    guard let snapshot else { return false }
    return remoteRateLimitWindowContainsMeaningfulData(snapshot.primary)
        || remoteRateLimitWindowContainsMeaningfulData(snapshot.secondary)
}

func remoteRateLimitWindowContainsMeaningfulData(_ window: CodexRateLimitWindow?) -> Bool {
    guard let window else { return false }
    if let resetsAt = window.resetsAt {
        guard resetsAt > .now else { return false }
        return true
    }
    return window.usedPercent > 0
}

func preferredRemoteRateLimitWindow(
    _ remote: CodexRateLimitWindow?,
    fallback: CodexRateLimitWindow?
) -> CodexRateLimitWindow? {
    guard let remote else { return fallback }
    guard let fallback else { return remote }

    if remoteRateLimitWindowContainsMeaningfulData(remote) {
        return CodexRateLimitWindow(
            usedPercent: remote.usedPercent,
            resetsAt: remote.resetsAt ?? fallback.resetsAt,
            windowDurationMinutes: remote.windowDurationMinutes ?? fallback.windowDurationMinutes
        )
    }
    return fallback
}

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private static let liveProofLayer = "live_ui"
    private static let hoverInvariantIDs = ["menubar.text_on_hover.stays_visible_inside_resized_bounds"]
    private static let switchInvariantIDs = ["accounts.switch_account.menu_action_changes_active_account"]
    private static let saveCurrentPromptInvariantIDs = ["accounts.save_current_account.prompt_presented_and_cancellable"]
    private static let addAccountPromptInvariantIDs = ["accounts.add_account.prompt_presented_and_cancellable"]
    private static let addHostPromptInvariantIDs = ["hosts.add_host.prompt_validates_destination"]
    private static let remoteHostSwitchInvariantIDs = ["hosts.switch_account_on_host.changes_remote_active_account"]
    private static let remoteHostReverifyInvariantIDs = ["hosts.reverify_remote_account.refreshes_remote_verification_state"]
    private static let scheduledRefreshInvariantIDs = ["accounts.scheduled_refresh.requested_and_completed"]

    private let statusItemRuntime: StatusItemRuntime
    private let store: MenuBarAccountsStore
    private let settings: AppSettings
    private let remoteHostClient: RemoteHostSwitching
    private let cliProcessInspector: CodexCLIProcessInspector
    private let alertPresenter: MenuBarAlertPresenting
    private let alertFactory: MenuBarAlertFactory
    private let validationSink: MenuBarValidationSink?
    private let validationScenario: String?
    private let allowsEmptyStatePrompt: Bool
    private let remoteHostAccountVerifier = RemoteHostAccountVerifier()
    private let savedAccountRelinker = SavedAccountRelinker()
    private let menuBuilder = MenuBarMenuBuilder()
    private var autoRefreshTimer: Timer?
    private var wakeRefreshTask: Task<Void, Never>?
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
    private var remoteHostConnectionStates: [String: RemoteHostConnectionState] = [:]

    init(
        statusItemRuntime: StatusItemRuntime,
        store: MenuBarAccountsStore,
        settings: AppSettings,
        remoteHostClient: RemoteHostSwitching = UnavailableRemoteHostClient(),
        cliProcessInspector: CodexCLIProcessInspector = CodexCLIProcessInspector(),
        alertPresenter: MenuBarAlertPresenting,
        alertFactory: MenuBarAlertFactory = MenuBarAlertFactory(),
        validationSink: MenuBarValidationSink? = nil,
        validationScenario: String? = MenuBarValidationConfiguration.scenario(),
        allowsEmptyStatePrompt: Bool = true
    ) {
        self.statusItemRuntime = statusItemRuntime
        self.store = store
        self.settings = settings
        self.remoteHostClient = remoteHostClient
        self.cliProcessInspector = cliProcessInspector
        self.alertPresenter = alertPresenter
        self.alertFactory = alertFactory
        self.validationSink = validationSink
        self.validationScenario = validationScenario
        self.allowsEmptyStatePrompt = allowsEmptyStatePrompt
    }

    func start() {
        statusItemRuntime.onEvent = { [weak self] event in
            self?.handleStatusItemRuntimeEvent(event)
        }
        restorePersistedRemoteHostState()
        statusItemRuntime.start(presentation: statusItemPresentation(for: menuState()))
        lastObservedActiveAccountID = store.activeAccountID
        lastObservedActiveAccountName = store.activeAccount?.name
        startObservingStore()
        startObservingSettings()
        rebuildMenu()
        scheduleAutoRefresh()
        syncBackgroundState()
        refreshRemoteHostStateIfNeeded()
    }

    func invalidate() {
        autoRefreshTimer?.invalidate()
        wakeRefreshTask?.cancel()
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
    func addCurrentAccount() {
        recordMenuAction("addCurrentAccount")
        let request = alertFactory.makeSaveCurrentAccountRequest(activeAccountEmail: store.activeAccount?.email)
        recordValidationEvent(
            "save_current_prompt_presented",
            step: "save_current_prompt",
            invariantIds: Self.saveCurrentPromptInvariantIDs
        )

        guard let name = alertPresenter.presentTextInput(request) else {
            recordValidationEvent(
                "save_current_prompt_cancelled",
                step: "save_current_prompt",
                invariantIds: Self.saveCurrentPromptInvariantIDs
            )
            return
        }
        recordValidationEvent(
            "save_current_prompt_confirmed",
            step: "save_current_prompt",
            invariantIds: Self.saveCurrentPromptInvariantIDs,
            payload: ["enteredName": name]
        )
        Task { await store.saveCurrentAccountSnapshot(named: name) }
    }

    @objc
    func addAccount() {
        recordMenuAction("addAccount")
        menuBarCoordinatorLogger.log("addAccount action invoked")
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        menuBarCoordinatorLogger.log("Running CLI sessions before add-account: \(runningCLISessions, privacy: .public)")

        let request = alertFactory.makeAddAccountRequest(runningCLISessions: runningCLISessions)
        recordValidationEvent(
            "add_account_prompt_presented",
            step: "add_account_prompt",
            invariantIds: Self.addAccountPromptInvariantIDs
        )

        menuBarCoordinatorLogger.log("Presenting add-account confirmation alert")
        guard let name = alertPresenter.presentTextInput(request) else {
            menuBarCoordinatorLogger.log("Add-account flow cancelled from alert")
            recordValidationEvent(
                "add_account_prompt_cancelled",
                step: "add_account_prompt",
                invariantIds: Self.addAccountPromptInvariantIDs
            )
            return
        }
        recordValidationEvent(
            "add_account_prompt_confirmed",
            step: "add_account_prompt",
            invariantIds: Self.addAccountPromptInvariantIDs,
            payload: ["enteredName": name]
        )

        menuBarCoordinatorLogger.log("Dispatching add-account task to store")
        Task {
            await store.startAddAccountFlow(named: name) { [weak self] prompt in
                self?.presentDeviceAuthPrompt(prompt)
            }
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
    func chooseProgressAccentColor(_ sender: NSMenuItem) {
        recordMenuAction("chooseProgressAccentColor")
        presentProgressColorPanel()
    }

    @objc
    func resetProgressAccentColor(_ sender: NSMenuItem) {
        recordMenuAction("resetProgressAccentColor")
        settings.resetProgressAccentColor()
        NSColorPanel.shared.color = settings.progressAccentColor
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
    func switchAccountOnHost(_ sender: NSMenuItem) {
        guard
            let payload = sender.representedObject as? HostAccountMenuItemPayload,
            let remoteHost = settings.remoteHostState(for: payload.hostDestination)?.host,
            let account = store.accounts.first(where: { $0.id == payload.accountID })
        else {
            return
        }

        recordMenuAction("switchAccountOnHost", payload: [
            "targetName": account.name,
            "hostName": remoteHost.displayName
        ])
        recordValidationEvent(
            "remote_host_switch_started",
            step: "remote_host_switch_start",
            invariantIds: Self.remoteHostSwitchInvariantIDs,
            payload: [
                "targetName": account.name,
                "hostName": remoteHost.displayName
            ]
        )
        lastSwitchTargetName = account.name
        if let previousRemoteAccount = settings.remoteHostState(for: remoteHost.destination)?.verifiedAccount,
           previousRemoteAccount.id != account.id {
            persistRemoteAccountIntoCatalogIfNeeded(previousRemoteAccount)
        }
        setRemoteHostConnectionState(.syncing, for: remoteHost.destination)
        rebuildMenu()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.store.switchToAccountOnHost(account, on: remoteHost)
            switch result {
            case .verified(let status):
                self.settings.updateRemoteHostState(for: remoteHost) { state in
                    if !state.installedAccountIDs.contains(account.id) {
                        state.installedAccountIDs.append(account.id)
                    }
                    state.desiredAccountID = account.id
                    state.verifiedAccount = self.mergedRemoteAccount(account, status: status)
                    state.detectedAccountID = nil
                    state.verificationStatus = .verified
                    state.lastVerificationError = nil
                }
                self.setRemoteHostConnectionState(.connected, for: remoteHost.destination)
                self.recordValidationEvent(
                    "remote_host_active_account_changed",
                    step: "remote_host_switch_result",
                    invariantIds: Self.remoteHostSwitchInvariantIDs,
                    payload: [
                        "targetName": account.name,
                        "hostName": remoteHost.displayName
                    ]
                )
            case .notVerified(let message, let detectedAccountID):
                self.setRemoteHostConnectionState(.connected, for: remoteHost.destination)
                self.settings.updateRemoteHostState(for: remoteHost) { state in
                    if !state.installedAccountIDs.contains(account.id) {
                        state.installedAccountIDs.append(account.id)
                    }
                    state.desiredAccountID = account.id
                    state.verifiedAccount = nil
                    state.detectedAccountID = detectedAccountID
                    state.verificationStatus = .failed
                    state.lastVerificationError = message
                }
                self.recordValidationEvent(
                    "remote_host_switch_not_verified",
                    step: "remote_host_switch_result",
                    invariantIds: Self.remoteHostSwitchInvariantIDs,
                    payload: [
                        "targetName": account.name,
                        "hostName": remoteHost.displayName,
                        "message": message
                    ]
                )
            case .failed(let message, let hostReachable):
                self.setRemoteHostConnectionState(hostReachable ? .connected : .disconnected, for: remoteHost.destination)
                self.settings.updateRemoteHostState(for: remoteHost) { state in
                    state.desiredAccountID = account.id
                    state.verifiedAccount = nil
                    state.detectedAccountID = nil
                    state.verificationStatus = .failed
                    state.lastVerificationError = message
                }
                self.recordValidationEvent(
                    "remote_host_switch_failed",
                    step: "remote_host_switch_result",
                    invariantIds: Self.remoteHostSwitchInvariantIDs,
                    payload: [
                        "targetName": account.name,
                        "hostName": remoteHost.displayName,
                        "message": message,
                        "hostReachable": hostReachable ? "true" : "false"
                    ]
                )
            }
            self.rebuildMenu()
        }
    }

    @objc
    func addHost(_ sender: NSMenuItem) {
        recordMenuAction("addHost")
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let remoteHost = await self.alertPresenter.presentHostSetup(
                self.alertFactory.makeAddHostRequest(),
                testConnection: { [weak self] host in
                    guard let self else {
                        return .failure(RemoteHostClientError.unavailable)
                    }
                    do {
                        try await self.remoteHostClient.testConnection(to: host)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                },
                onPresented: { [weak self] in
                    self?.recordValidationEvent(
                        "add_host_prompt_presented",
                        step: "add_host_prompt",
                        invariantIds: Self.addHostPromptInvariantIDs
                    )
                },
                onCancelled: { [weak self] in
                    self?.recordValidationEvent(
                        "add_host_prompt_cancelled",
                        step: "add_host_prompt",
                        invariantIds: Self.addHostPromptInvariantIDs
                    )
                },
                onValidationStarted: { [weak self] host in
                    self?.recordValidationEvent(
                        "add_host_validation_started",
                        step: "add_host_validation",
                        invariantIds: Self.addHostPromptInvariantIDs,
                        payload: ["hostName": host.destination]
                    )
                },
                onValidationFinished: { [weak self] host, result in
                    switch result {
                    case .success:
                        self?.recordValidationEvent(
                            "add_host_validation_succeeded",
                            step: "add_host_validation",
                            invariantIds: Self.addHostPromptInvariantIDs,
                            payload: ["hostName": host.destination]
                        )
                    case .failure(let error):
                        self?.recordValidationEvent(
                            "add_host_validation_failed",
                            step: "add_host_validation",
                            invariantIds: Self.addHostPromptInvariantIDs,
                            payload: [
                                "hostName": host.destination,
                                "message": error.localizedDescription
                            ]
                        )
                    }
                }
            ) else {
                return
            }

            self.settings.upsertRemoteHost(remoteHost)
            self.setRemoteHostConnectionState(.connected, for: remoteHost.destination)

            if let activeAccount = self.store.activeAccount {
                let shouldInstallCurrentAccount = self.alertPresenter.presentConfirmation(
                    self.alertFactory.makeInstallCurrentAccountOnHostRequest(
                        accountName: activeAccount.name,
                        hostName: remoteHost.displayName
                    )
                )

                if shouldInstallCurrentAccount {
                    self.setRemoteHostConnectionState(.syncing, for: remoteHost.destination)
                    self.rebuildMenu()
                    let result = await self.store.switchToAccountOnHost(activeAccount, on: remoteHost)
                    switch result {
                    case .verified(let status):
                        self.settings.updateRemoteHostState(for: remoteHost) { state in
                            if !state.installedAccountIDs.contains(activeAccount.id) {
                                state.installedAccountIDs.append(activeAccount.id)
                            }
                            state.desiredAccountID = activeAccount.id
                            state.verifiedAccount = self.mergedRemoteAccount(activeAccount, status: status)
                            state.detectedAccountID = nil
                            state.verificationStatus = .verified
                            state.lastVerificationError = nil
                        }
                        self.setRemoteHostConnectionState(.connected, for: remoteHost.destination)
                    case .notVerified(let message, let detectedAccountID):
                        self.setRemoteHostConnectionState(.connected, for: remoteHost.destination)
                        self.settings.updateRemoteHostState(for: remoteHost) { state in
                            if !state.installedAccountIDs.contains(activeAccount.id) {
                                state.installedAccountIDs.append(activeAccount.id)
                            }
                            state.desiredAccountID = activeAccount.id
                            state.verifiedAccount = nil
                            state.detectedAccountID = detectedAccountID
                            state.verificationStatus = .failed
                            state.lastVerificationError = message
                        }
                    case .failed(let message, let hostReachable):
                        self.setRemoteHostConnectionState(hostReachable ? .connected : .disconnected, for: remoteHost.destination)
                        self.settings.updateRemoteHostState(for: remoteHost) { state in
                            if !state.installedAccountIDs.contains(activeAccount.id) {
                                state.installedAccountIDs.append(activeAccount.id)
                            }
                            state.desiredAccountID = activeAccount.id
                            state.verifiedAccount = nil
                            state.detectedAccountID = nil
                            state.verificationStatus = .failed
                            state.lastVerificationError = message
                        }
                    }
                }
            }

            self.rebuildMenu()
        }
    }

    @objc
    func removeHost(_ sender: NSMenuItem) {
        guard
            let payload = sender.representedObject as? HostSelectionMenuItemPayload,
            let hostState = settings.remoteHostState(for: payload.hostDestination)
        else { return }
        let remoteHost = hostState.host
        recordMenuAction("removeHost", payload: ["hostName": remoteHost.displayName])
        guard alertPresenter.presentConfirmation(alertFactory.makeRemoveHostRequest(hostName: remoteHost.displayName)) else {
            return
        }

        persistRemoteAccountIntoCatalogIfNeeded(hostState.verifiedAccount)
        settings.removeRemoteHost(destination: remoteHost.destination)
        remoteHostConnectionStates.removeValue(forKey: remoteHost.destination)
        rebuildMenu()
    }

    @objc
    func reverifyHost(_ sender: NSMenuItem) {
        guard
            let payload = sender.representedObject as? HostSelectionMenuItemPayload,
            let hostState = settings.remoteHostState(for: payload.hostDestination)
        else { return }

        reverifyHost(hostState: hostState)
    }

    func reverifyHost(hostDestination: String) {
        guard let hostState = settings.remoteHostState(for: hostDestination) else { return }
        reverifyHost(hostState: hostState)
    }

    private func reverifyHost(hostState: PersistedRemoteHostState) {
        guard hostState.verificationStatus != .verifying else { return }
        guard let baseAccount = baseAccountForRemoteRefresh(hostState: hostState) else { return }
        statusItemRuntime.menu?.cancelTracking()

        recordMenuAction("reverifyHost", payload: [
            "hostName": hostState.host.displayName,
            "accountName": baseAccount.name
        ])
        recordValidationEvent(
            "remote_host_reverify_started",
            step: "remote_host_reverify_start",
            invariantIds: Self.remoteHostReverifyInvariantIDs,
            payload: [
                "hostName": hostState.host.displayName,
                "accountName": baseAccount.name
            ]
        )

        setRemoteHostConnectionState(.syncing, for: hostState.host.destination)
        settings.updateRemoteHostState(for: hostState.host) { state in
            state.verificationStatus = .verifying
            state.lastVerificationError = nil
            if state.desiredAccountID == nil {
                state.desiredAccountID = baseAccount.id
            }
        }
        rebuildMenu()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshRemoteHostState(
                for: baseAccount,
                on: hostState.host,
                fallbackConnectionState: .disconnected
            )

            let refreshedState = self.settings.remoteHostState(for: hostState.host.destination)
            let eventName = refreshedState?.verificationStatus == .verified
                ? "remote_host_reverify_succeeded"
                : "remote_host_reverify_failed"
            self.recordValidationEvent(
                eventName,
                step: "remote_host_reverify_result",
                invariantIds: Self.remoteHostReverifyInvariantIDs,
                payload: [
                    "hostName": hostState.host.displayName,
                    "accountName": baseAccount.name
                ]
            )
            self.rebuildMenu()
        }
    }

    @objc
    func adoptDetectedRemoteAccount(_ sender: NSMenuItem) {
        guard
            let payload = sender.representedObject as? HostAccountMenuItemPayload,
            let hostState = settings.remoteHostState(for: payload.hostDestination)
        else { return }

        adoptDetectedRemoteAccount(
            hostState: hostState,
            accountID: payload.accountID
        )
    }

    func adoptDetectedRemoteAccount(hostDestination: String, accountID: UUID) {
        guard let hostState = settings.remoteHostState(for: hostDestination) else { return }
        adoptDetectedRemoteAccount(hostState: hostState, accountID: accountID)
    }

    private func adoptDetectedRemoteAccount(hostState: PersistedRemoteHostState, accountID: UUID) {
        guard let detectedAccount = store.accounts.first(where: { $0.id == accountID })
        else { return }
        statusItemRuntime.menu?.cancelTracking()

        recordMenuAction("adoptDetectedRemoteAccount", payload: [
            "hostName": hostState.host.displayName,
            "accountName": detectedAccount.name
        ])
        setRemoteHostConnectionState(.syncing, for: hostState.host.destination)
        settings.updateRemoteHostState(for: hostState.host) { state in
            state.desiredAccountID = detectedAccount.id
            state.detectedAccountID = detectedAccount.id
            state.verificationStatus = .verifying
            state.lastVerificationError = nil
        }
        rebuildMenu()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshRemoteHostState(
                for: detectedAccount,
                on: hostState.host,
                fallbackConnectionState: .connected
            )
            self.rebuildMenu()
        }
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

    private func rebuildMenu() {
        let state = menuState()
        let menu = statusItemRuntime.menu ?? NSMenu()
        menuBuilder.populate(menu: menu, state: state, target: self)
        statusItemRuntime.menu = menu
        recordValidationSnapshot(for: state)
    }

    private func menuState() -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: store.activeAccount,
            inactiveAccounts: store.sortedInactiveAccounts,
            remoteHosts: settings.remoteHostStates.map { configuredHost in
                RemoteHostMenuState(
                    name: configuredHost.host.displayName,
                    destination: configuredHost.host.destination,
                    connectionState: remoteHostConnectionState(for: configuredHost),
                    desiredAccount: desiredRemoteAccount(for: configuredHost),
                    activeAccount: configuredHost.verifiedAccount,
                    detectedAccount: detectedRemoteAccount(for: configuredHost),
                    verificationStatus: configuredHost.verificationStatus,
                    lastVerificationError: configuredHost.lastVerificationError,
                    deployedAccountIDs: configuredHost.installedAccountIDs
                )
            },
            visibleInactiveAccountCount: settings.visibleInactiveAccountCount,
            visibleInactiveAccountCountOptions: settings.visibleInactiveAccountCountOptions,
            refreshIntervalMinutes: settings.refreshIntervalMinutes,
            refreshIntervalOptions: settings.refreshIntervalOptions,
            statusBarMonochrome: settings.statusBarMonochrome,
            statusBarIndicatorStyle: settings.statusBarIndicatorStyle,
            statusBarDisplayMode: settings.statusBarDisplayMode,
            progressAccentColor: settings.progressAccentColor,
            hasCustomProgressAccentColor: settings.hasCustomProgressAccentColor,
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
        let interval = AppRuntimeEnvironment.validationAutoRefreshIntervalSeconds() ?? TimeInterval(settings.refreshIntervalMinutes * 60)
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
                self.recordValidationEvent(
                    outcome == .refreshed ? "scheduled_refresh_completed" : "scheduled_refresh_failed",
                    step: "scheduled_refresh_result",
                    invariantIds: Self.scheduledRefreshInvariantIDs,
                    payload: ["accountName": activeAccount.name]
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
        recordActiveAccountTransitionIfNeeded()
        if !store.accounts.isEmpty {
            hasPromptedForEmptyState = false
        }
        statusItemRuntime.update(presentation: statusItemPresentation(for: menuState()))
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
            _ = settings.progressAccentColor
            _ = settings.remoteHostStates
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleSettingsChange()
                self.observeSettingsChanges()
            }
        }
    }

    private func handleSettingsChange() {
        statusItemRuntime.update(presentation: statusItemPresentation(for: menuState()))
        scheduleAutoRefresh()
        rebuildMenu()
    }

    private func restorePersistedRemoteHostState() {
        remoteHostConnectionStates = [:]
        for hostState in settings.remoteHostStates {
            remoteHostConnectionStates[hostState.host.destination] = .disconnected
        }
    }

    private func refreshRemoteHostStateIfNeeded(markSyncing: Bool = true) {
        for hostState in settings.remoteHostStates {
            guard let baseAccount = baseAccountForRemoteRefresh(hostState: hostState) else {
                guard hostState.desiredAccountID != nil || hostState.verifiedAccount != nil else { continue }
                persistRemoteAccountIntoCatalogIfNeeded(hostState.verifiedAccount)
                setRemoteHostConnectionState(.disconnected, for: hostState.host.destination)
                settings.updateRemoteHostState(for: hostState.host) { state in
                    state.verifiedAccount = nil
                    state.detectedAccountID = nil
                    state.verificationStatus = .failed
                    state.lastVerificationError = "Saved account for \(hostState.host.displayName) is no longer available on this Mac."
                }
                continue
            }
            if markSyncing {
                setRemoteHostConnectionState(.syncing, for: hostState.host.destination)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshRemoteHostState(for: baseAccount, on: hostState.host, fallbackConnectionState: .disconnected)
                self.rebuildMenu()
            }
        }
    }

    private func refreshRemoteHostState(
        for baseAccount: CodexAccount,
        on host: RemoteHost,
        fallbackConnectionState: RemoteHostConnectionState
    ) async {
        do {
            let status = try await remoteHostClient.readCurrentAccountStatus(on: host)
            switch remoteHostAccountVerifier.verify(
                status: status,
                expectedAccount: baseAccount,
                among: store.accounts
            ) {
            case .verified(let verifiedStatus):
                let refreshedAccount = mergedRemoteAccount(baseAccount, status: verifiedStatus)
                setRemoteHostConnectionState(.connected, for: host.destination)
                settings.updateRemoteHostState(for: host) { state in
                    state.desiredAccountID = baseAccount.id
                    state.verifiedAccount = refreshedAccount
                    state.detectedAccountID = nil
                    state.verificationStatus = .verified
                    state.lastVerificationError = nil
                }
            case .notVerified(let matchOutcome):
                persistRemoteAccountIntoCatalogIfNeeded(settings.remoteHostState(for: host.destination)?.verifiedAccount)
                setRemoteHostConnectionState(.connected, for: host.destination)
                settings.updateRemoteHostState(for: host) { state in
                    state.desiredAccountID = baseAccount.id
                    state.verifiedAccount = nil
                    state.detectedAccountID = matchOutcome.matchedAccountID
                    state.verificationStatus = .failed
                    state.lastVerificationError = remoteHostAccountVerifier.failureMessage(
                        for: baseAccount,
                        on: host,
                        among: store.accounts,
                        matchOutcome: matchOutcome
                    )
                }
            }
        } catch {
            persistRemoteAccountIntoCatalogIfNeeded(settings.remoteHostState(for: host.destination)?.verifiedAccount)
            let connectionState = Self.isReachableRemoteVerificationFailure(error) ? RemoteHostConnectionState.connected : fallbackConnectionState
            setRemoteHostConnectionState(connectionState, for: host.destination)
            settings.updateRemoteHostState(for: host) { state in
                state.desiredAccountID = baseAccount.id
                state.verifiedAccount = nil
                state.detectedAccountID = nil
                state.verificationStatus = .failed
                state.lastVerificationError = error.localizedDescription
            }
        }
    }

    private func remoteHostConnectionState(for hostState: PersistedRemoteHostState) -> RemoteHostConnectionState {
        remoteHostConnectionStates[hostState.host.destination]
            ?? (hostState.desiredAccountID != nil ? .syncing : .disconnected)
    }

    private func desiredRemoteAccount(for hostState: PersistedRemoteHostState) -> CodexAccount? {
        if let canonicalAccount = savedAccountRelinker.resolveCanonicalAccount(
            for: hostState,
            among: store.accounts
        ) {
            return canonicalAccount
        }

        guard let desiredAccountID = hostState.desiredAccountID else { return nil }
        if let verifiedAccount = hostState.verifiedAccount, verifiedAccount.id == desiredAccountID {
            return verifiedAccount
        }
        return nil
    }

    private func detectedRemoteAccount(for hostState: PersistedRemoteHostState) -> CodexAccount? {
        guard let detectedAccountID = hostState.detectedAccountID else { return nil }
        return store.accounts.first(where: { $0.id == detectedAccountID })
    }

    private func baseAccountForRemoteRefresh(hostState: PersistedRemoteHostState) -> CodexAccount? {
        if let canonicalAccount = savedAccountRelinker.resolveCanonicalAccount(
            for: hostState,
            among: store.accounts
        ) {
            return canonicalAccount
        }

        return hostState.verifiedAccount
    }

    private func setRemoteHostConnectionState(_ state: RemoteHostConnectionState, for hostDestination: String) {
        remoteHostConnectionStates[hostDestination] = state
    }

    private func mergedRemoteAccount(_ baseAccount: CodexAccount, status: CodexAccountStatus) -> CodexAccount {
        var account = baseAccount
        let mergedRateLimits = preferredRemoteRateLimits(
            remote: status.rateLimits,
            fallback: baseAccount.rateLimits,
            candidateAccounts: store.accounts,
            baseAccount: baseAccount,
            remoteEmail: status.email
        )
        account.applyRemoteMetadata(
            email: status.email ?? baseAccount.email,
            planType: status.planType ?? baseAccount.planType,
            rateLimits: mergedRateLimits
        )
        account.updatedAt = .now
        return account
    }

    private func persistRemoteAccountIntoCatalogIfNeeded(_ account: CodexAccount?) {
        guard let account else { return }
        store.persistAccountMetadata(account)
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
                    payload: payload
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
            self.addCurrentAccount()
        }
    }

    private func presentDeviceAuthPrompt(_ prompt: CodexDeviceAuthPrompt) {
        NSWorkspace.shared.open(prompt.verificationURL)
        alertPresenter.presentInfo(alertFactory.makeAddAccountDeviceAuthRequest(prompt: prompt))
    }

    private func statusItemPresentation(for state: MenuBarMenuState) -> StatusItemRuntimePresentation {
        StatusItemRuntimePresentation(
            activeAccount: store.activeAccount,
            indicatorStyle: settings.statusBarIndicatorStyle,
            monochrome: settings.statusBarMonochrome,
            displayMode: state.effectiveStatusBarDisplayMode,
            progressAccentColor: settings.progressAccentColor
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
        panel.color = settings.progressAccentColor
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc
    private func handleProgressColorPanelChanged(_ sender: NSColorPanel) {
        settings.progressAccentColor = sender.color.withAlphaComponent(1)
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

private extension MenuBarCoordinator {
    static func isReachableRemoteVerificationFailure(_ error: Error) -> Bool {
        guard let clientError = error as? RemoteHostClientError else { return false }
        if case .authReadFailed = clientError {
            return true
        }
        return false
    }
}
