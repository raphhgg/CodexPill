import AppKit
import Observation
import OSLog
import UserNotifications

private let menuBarCoordinatorLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "MenuBarCoordinator")

enum AccountAvailabilityNotificationActionKind: Equatable {
    case local
    case remote(hostDestination: String)
    case bestOption
}

struct AccountAvailabilityNotificationAction: Equatable {
    let identifier: String
    let title: String
    let kind: AccountAvailabilityNotificationActionKind
}

struct AccountAvailabilityNotificationPayload: Equatable {
    let accountID: UUID
    let title: String
    let body: String
    let actions: [AccountAvailabilityNotificationAction]
}

struct AccountAvailabilityNotificationCopyRenderer {
    func render(
        decision: AccountAvailabilityNotificationDecision,
        remoteHosts: [RemoteHostMenuState]
    ) -> (title: String, body: String) {
        switch decision.reason {
        case .whenBlocked:
            return ("CodexPill", "\(decision.account.name) is available again")
        case .whenOut:
            guard let triggerContext = decision.triggerContext else {
                return ("CodexPill", "\(decision.account.name) is available again")
            }

            return (
                "\(triggerContext.accountName) is out on \(targetLabel(for: triggerContext.target, remoteHosts: remoteHosts))",
                "\(limitSummary(for: triggerContext)). \(decision.account.name) is ready."
            )
        }
    }

    private func targetLabel(
        for target: AccountAvailabilityTarget,
        remoteHosts: [RemoteHostMenuState]
    ) -> String {
        switch target {
        case .local:
            return "This Mac"
        case .remote(let hostDestination):
            return remoteHosts.first(where: { $0.destination == hostDestination })?.name ?? hostDestination
        }
    }

    private func limitSummary(
        for triggerContext: AccountAvailabilityNotificationTriggerContext
    ) -> String {
        let sessionOut = triggerContext.sessionRemainingPercent <= 0
        let weeklyOut = triggerContext.weeklyRemainingPercent <= 0

        switch (sessionOut, weeklyOut) {
        case (true, true):
            return "Session and weekly limits reached"
        case (true, false):
            return "Session limit reached"
        case (false, true):
            return "Weekly limit reached"
        case (false, false):
            return "Limit reached"
        }
    }
}

protocol AccountAvailabilityNotificationDelivering {
    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorizationIfNeeded() async
    func deliver(_ payload: AccountAvailabilityNotificationPayload) async -> Bool
}

protocol ApplicationForegrounding {
    func activate()
}

protocol NotificationSettingsOpening {
    func openNotificationSettings()
}

protocol UserNotificationCentering: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
}

extension UNUserNotificationCenter: UserNotificationCentering {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

struct NSApplicationForegrounder: ApplicationForegrounding {
    func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SystemNotificationSettingsOpener: NotificationSettingsOpening {
    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

final class AccountAvailabilityNotificationCenter: AccountAvailabilityNotificationDelivering {
    private let center: UserNotificationCentering
    private var hasRequestedAuthorization = false

    init(center: UserNotificationCentering = UNUserNotificationCenter.current()) {
        self.center = center
    }

    func authorizationState() async -> NotificationAuthorizationState {
        switch await center.authorizationStatus() {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unknown
        }
    }

    func requestAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func deliver(_ payload: AccountAvailabilityNotificationPayload) async -> Bool {
        let rendered = renderedActions(for: payload.actions)
        if let category = rendered.category {
            center.setNotificationCategories([category])
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        if let categoryIdentifier = rendered.category?.identifier {
            content.categoryIdentifier = categoryIdentifier
        }
        content.userInfo = userInfo(for: payload, renderedActions: rendered.actions)

        let request = UNNotificationRequest(
            identifier: "account-availability-\(payload.accountID.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    private func renderedActions(
        for actions: [AccountAvailabilityNotificationAction]
    ) -> (actions: [AccountAvailabilityNotificationAction], category: UNNotificationCategory?) {
        guard !actions.isEmpty else {
            return (actions: [], category: nil)
        }

        let directActions = actions.filter {
            if case .bestOption = $0.kind {
                return false
            }
            return true
        }

        let finalActions: [AccountAvailabilityNotificationAction]
        if !directActions.isEmpty, directActions.count <= 2 {
            finalActions = directActions
        } else {
            finalActions = [AccountAvailabilityNotificationAction(
                identifier: "use_best_option",
                title: "Use Best Option",
                kind: .bestOption
            )]
        }

        guard !finalActions.isEmpty else {
            return (actions: [], category: nil)
        }

        let categoryActions = finalActions.map {
            UNNotificationAction(identifier: $0.identifier, title: $0.title)
        }
        let categoryIdentifier = "account_availability_\(finalActions.map(\.identifier).joined(separator: "_"))"
        return (
            actions: finalActions,
            category: UNNotificationCategory(
                identifier: categoryIdentifier,
                actions: categoryActions,
                intentIdentifiers: [],
                options: []
            )
        )
    }

    private func userInfo(
        for payload: AccountAvailabilityNotificationPayload,
        renderedActions: [AccountAvailabilityNotificationAction]
    ) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [
            "accountID": payload.accountID.uuidString
        ]

        if let remoteAction = renderedActions.first(where: {
            if case .remote = $0.kind {
                return true
            }
            return false
        }),
           case .remote(let hostDestination) = remoteAction.kind {
            userInfo["remoteHostDestination"] = hostDestination
        }

        return userInfo
    }
}

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
    private static let saveCurrentNameDialogInvariantIDs = [
        "accounts.save_current_account.name_dialog_presented",
        "accounts.save_current_account.name_dialog_cancelled",
        "accounts.save_current_account.cancel_keeps_account_state"
    ]
    private static let addAccountNameDialogInvariantIDs = [
        "accounts.add_account.name_dialog_presented",
        "accounts.add_account.name_dialog_cancelled",
        "accounts.add_account.cancel_keeps_account_state"
    ]
    private static let addHostPromptInvariantIDs = ["hosts.add_host.destination_validation_failed"]
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
    private let notificationStateStore: NotificationStateStore
    private let notificationDelivery: AccountAvailabilityNotificationDelivering
    private let applicationForegrounder: ApplicationForegrounding
    private let notificationSettingsOpener: NotificationSettingsOpening
    private let validationSink: MenuBarValidationSink?
    private let validationScenario: String?
    private let sealValidationRun: CodexPillSealValidationRun?
    private let allowsEmptyStatePrompt: Bool
    private let remoteHostRuntime: RemoteHostRuntime
    private let notificationPolicy = AccountAvailabilityNotificationPolicy()
    private let notificationActionResolver = AccountAvailabilityNotificationActionResolver()
    private let notificationCopyRenderer = AccountAvailabilityNotificationCopyRenderer()
    private let menuBuilder = MenuBarMenuBuilder()
    private var autoRefreshTimer: Timer?
    private var pendingSignInMonitorTimer: Timer?
    private var wakeRefreshTask: Task<Void, Never>?
    private var notificationWaitTask: Task<Void, Never>?
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
    private var previousNotificationSnapshots: [UUID: AccountAvailabilitySnapshot] = [:]
    private var cachedNotificationAuthorizationState: NotificationAuthorizationState = .unknown

    init(
        statusItemRuntime: StatusItemRuntime,
        store: MenuBarAccountsStore,
        settings: AppSettings,
        remoteHostClient: RemoteHostSwitching = UnavailableRemoteHostClient(),
        cliProcessInspector: CodexCLIProcessInspector = CodexCLIProcessInspector(),
        alertPresenter: MenuBarAlertPresenting,
        alertFactory: MenuBarAlertFactory = MenuBarAlertFactory(),
        notificationDelivery: AccountAvailabilityNotificationDelivering = AccountAvailabilityNotificationCenter(),
        applicationForegrounder: ApplicationForegrounding = NSApplicationForegrounder(),
        notificationSettingsOpener: NotificationSettingsOpening = SystemNotificationSettingsOpener(),
        validationSink: MenuBarValidationSink? = nil,
        validationScenario: String? = MenuBarValidationConfiguration.scenario(),
        sealValidationRun: CodexPillSealValidationRun? = nil,
        allowsEmptyStatePrompt: Bool = true
    ) {
        self.statusItemRuntime = statusItemRuntime
        self.store = store
        self.settings = settings
        self.remoteHostClient = remoteHostClient
        self.cliProcessInspector = cliProcessInspector
        self.alertPresenter = alertPresenter
        self.alertFactory = alertFactory
        self.notificationStateStore = NotificationStateStore(settings: settings)
        self.notificationDelivery = notificationDelivery
        self.applicationForegrounder = applicationForegrounder
        self.notificationSettingsOpener = notificationSettingsOpener
        self.validationSink = validationSink
        self.validationScenario = validationScenario
        self.sealValidationRun = sealValidationRun ?? CodexPillSealValidationConfiguration.makeRun()
        self.allowsEmptyStatePrompt = allowsEmptyStatePrompt
        self.remoteHostRuntime = RemoteHostRuntime(
            settings: settings,
            remoteHostClient: remoteHostClient,
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
        restorePersistedRemoteHostState()
        statusItemRuntime.start(presentation: statusItemPresentation(for: menuState()))
        lastObservedActiveAccountID = store.activeAccountID
        lastObservedActiveAccountName = store.activeAccount?.name
        previousNotificationSnapshots = notificationSnapshotMap(for: menuState())
        startObservingStore()
        startObservingSettings()
        rebuildMenu()
        scheduleAutoRefresh()
        syncBackgroundState()
        triggerValidationScenarioIfNeeded()
        refreshNotificationAuthorizationState()
        refreshRemoteHostStateIfNeeded()
    }

    func invalidate() {
        autoRefreshTimer?.invalidate()
        pendingSignInMonitorTimer?.invalidate()
        wakeRefreshTask?.cancel()
        notificationWaitTask?.cancel()
        sealValidationRun?.cancelIfUnfinished()
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
        sealValidationRun?.recordSaveCurrentAccountMenuAction(
            activeAccount: store.activeAccount,
            savedAccounts: store.accounts
        )
        let request = alertFactory.makeSaveCurrentAccountRequest(activeAccountEmail: store.activeAccount?.email)
        recordValidationEvent(
            "save_current_prompt_presented",
            step: "save_current_prompt",
            invariantIds: Self.saveCurrentNameDialogInvariantIDs
        )
        sealValidationRun?.recordSaveCurrentAccountNameDialogPresented(activeAccountEmail: store.activeAccount?.email)

        guard let name = alertPresenter.presentTextInput(request) else {
            recordValidationEvent(
                "save_current_prompt_cancelled",
                step: "save_current_prompt",
                invariantIds: Self.saveCurrentNameDialogInvariantIDs
            )
            sealValidationRun?.recordSaveCurrentAccountNameDialogCancelled(
                activeAccount: store.activeAccount,
                savedAccounts: store.accounts
            )
            return
        }
        recordValidationEvent(
            "save_current_prompt_confirmed",
            step: "save_current_prompt",
            invariantIds: Self.saveCurrentNameDialogInvariantIDs,
            payload: ["enteredName": name]
        )
        Task { await store.saveCurrentAccountSnapshot(named: name) }
    }

    @objc
    func addAccount() {
        recordMenuAction("addAccount")
        sealValidationRun?.recordAddAccountMenuAction(
            activeAccount: store.activeAccount,
            savedAccounts: store.accounts
        )
        menuBarCoordinatorLogger.log("addAccount action invoked")
        let runningCLISessions = cliProcessInspector.runningCLISessionCount()
        menuBarCoordinatorLogger.log("Running CLI sessions before add-account: \(runningCLISessions, privacy: .public)")

        let request = alertFactory.makeAddAccountRequest(runningCLISessions: runningCLISessions)
        recordValidationEvent(
            "add_account_prompt_presented",
            step: "add_account_prompt",
            invariantIds: Self.addAccountNameDialogInvariantIDs
        )
        sealValidationRun?.recordAddAccountNameDialogPresented(runningCLISessions: runningCLISessions)

        menuBarCoordinatorLogger.log("Presenting add-account confirmation alert")
        guard let name = alertPresenter.presentTextInput(request) else {
            menuBarCoordinatorLogger.log("Add-account flow cancelled from alert")
            recordValidationEvent(
                "add_account_prompt_cancelled",
                step: "add_account_prompt",
                invariantIds: Self.addAccountNameDialogInvariantIDs
            )
            sealValidationRun?.recordAddAccountNameDialogCancelled(
                activeAccount: store.activeAccount,
                savedAccounts: store.accounts
            )
            return
        }
        recordValidationEvent(
            "add_account_prompt_confirmed",
            step: "add_account_prompt",
            invariantIds: Self.addAccountNameDialogInvariantIDs,
            payload: ["enteredName": name]
        )

        menuBarCoordinatorLogger.log("Dispatching add-account task to store")
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
    func toggleNotificationsWhenBlocked(_ sender: NSMenuItem) {
        recordMenuAction("toggleNotificationsWhenBlocked")
        let hadAnyNotificationsEnabled = notificationStateStore.whenBlockedEnabled || notificationStateStore.whenOutEnabled
        notificationStateStore.whenBlockedEnabled.toggle()
        if !hadAnyNotificationsEnabled, notificationStateStore.whenBlockedEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.notificationDelivery.requestAuthorizationIfNeeded()
                self.refreshNotificationAuthorizationState()
            }
        }
    }

    @objc
    func toggleNotificationsWhenOut(_ sender: NSMenuItem) {
        recordMenuAction("toggleNotificationsWhenOut")
        let hadAnyNotificationsEnabled = notificationStateStore.whenBlockedEnabled || notificationStateStore.whenOutEnabled
        notificationStateStore.whenOutEnabled.toggle()
        if !hadAnyNotificationsEnabled, notificationStateStore.whenOutEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.notificationDelivery.requestAuthorizationIfNeeded()
                self.refreshNotificationAuthorizationState()
            }
        }
    }

    @objc
    func enableNotifications(_ sender: NSMenuItem) {
        recordMenuAction("enableNotifications")
        if !notificationStateStore.whenBlockedEnabled && !notificationStateStore.whenOutEnabled {
            notificationStateStore.whenBlockedEnabled = true
            notificationStateStore.whenOutEnabled = true
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            var state = await self.notificationDelivery.authorizationState()
            switch state {
            case .denied:
                self.notificationSettingsOpener.openNotificationSettings()
            case .notDetermined, .unknown:
                await self.notificationDelivery.requestAuthorizationIfNeeded()
                state = await self.notificationDelivery.authorizationState()
            case .authorized:
                break
            }
            self.cachedNotificationAuthorizationState = state
            self.rebuildMenu()
        }
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
        sealValidationRun?.recordSwitchAccountMenuAction(
            targetAccount: account,
            activeAccount: store.activeAccount,
            savedAccounts: store.accounts
        )
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
        sealValidationRun?.recordRemoteHostSwitchMenuAction(
            targetName: account.name,
            hostName: remoteHost.displayName
        )
        recordValidationEvent(
            "remote_host_switch_started",
            step: "remote_host_switch_start",
            invariantIds: Self.remoteHostSwitchInvariantIDs,
            payload: [
                "targetName": account.name,
                "hostName": remoteHost.displayName
            ]
        )
        sealValidationRun?.recordRemoteHostSwitchStarted(
            targetName: account.name,
            hostName: remoteHost.displayName
        )
        lastSwitchTargetName = account.name
        remoteHostRuntime.beginHostSwitch(to: account, on: remoteHost)
        rebuildMenu()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.store.switchToAccountOnHost(account, on: remoteHost)
            self.remoteHostRuntime.applySwitchOutcome(result, account: account, host: remoteHost)
            switch result {
            case .verified:
                self.recordValidationEvent(
                    "remote_host_active_account_changed",
                    step: "remote_host_switch_result",
                    invariantIds: Self.remoteHostSwitchInvariantIDs,
                    payload: [
                        "targetName": account.name,
                        "hostName": remoteHost.displayName
                    ]
                )
                self.sealValidationRun?.recordRemoteHostActiveAccountChanged(
                    targetName: account.name,
                    hostName: remoteHost.displayName
                )
            case .notVerified(let message, _):
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
        sealValidationRun?.recordAddHostMenuAction()
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
                        "add_host_setup_presented",
                        step: "add_host_setup",
                        invariantIds: Self.addHostPromptInvariantIDs
                    )
                    self?.sealValidationRun?.recordAddHostSetupPresented()
                },
                onCancelled: { [weak self] in
                    self?.recordValidationEvent(
                        "add_host_setup_cancelled",
                        step: "add_host_setup",
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
                    self?.sealValidationRun?.recordAddHostValidationStarted(hostName: host.destination)
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
                        self?.sealValidationRun?.recordAddHostValidationFailed(
                            hostName: host.destination,
                            message: error.localizedDescription
                        )
                    }
                }
            ) else {
                return
            }

            guard let activeAccount = self.store.activeAccount else {
                self.recordValidationEvent(
                    "add_host_account_setup_unavailable",
                    step: "add_host_account_setup",
                    invariantIds: Self.addHostPromptInvariantIDs,
                    payload: ["hostName": remoteHost.displayName]
                )
                self.rebuildMenu()
                return
            }

            let shouldInstallCurrentAccount = self.alertPresenter.presentConfirmation(
                self.alertFactory.makeInstallCurrentAccountOnHostRequest(
                    accountName: activeAccount.name,
                    hostName: remoteHost.displayName
                )
            )

            guard shouldInstallCurrentAccount else {
                self.recordValidationEvent(
                    "add_host_account_setup_cancelled",
                    step: "add_host_account_setup",
                    invariantIds: Self.addHostPromptInvariantIDs,
                    payload: ["hostName": remoteHost.displayName]
                )
                self.rebuildMenu()
                return
            }

            self.settings.updateRemoteHostState(for: remoteHost) { state in
                state.desiredAccountID = activeAccount.id
                state.verificationStatus = .verifying
                state.lastVerificationError = nil
            }
            self.remoteHostRuntime.beginHostSwitch(to: activeAccount, on: remoteHost)
            self.rebuildMenu()
            let result = await self.store.switchToAccountOnHost(activeAccount, on: remoteHost)
            self.remoteHostRuntime.applySwitchOutcome(
                result,
                account: activeAccount,
                host: remoteHost,
                recordsInstalledAccountOnFailure: true
            )
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

        remoteHostRuntime.removeHost(hostState)
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
        guard let baseAccount = remoteHostRuntime.beginReverification(hostState: hostState) else { return }
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

        rebuildMenu()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.remoteHostRuntime.refresh(
                host: hostState.host,
                baseAccount: baseAccount,
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
        guard let detectedAccount = remoteHostRuntime.beginAdoptingDetectedAccount(hostState: hostState, accountID: accountID) else { return }
        statusItemRuntime.menu?.cancelTracking()

        recordMenuAction("adoptDetectedRemoteAccount", payload: [
            "hostName": hostState.host.displayName,
            "accountName": detectedAccount.name
        ])
        rebuildMenu()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.remoteHostRuntime.refresh(
                host: hostState.host,
                baseAccount: detectedAccount,
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
            statusMessage: store.statusMessage,
            notificationsWhenBlockedEnabled: notificationStateStore.whenBlockedEnabled,
            notificationsWhenOutEnabled: notificationStateStore.whenOutEnabled,
            notificationAuthorizationState: cachedNotificationAuthorizationState
        )
    }

    private func requestSwitch(to account: CodexAccount) {
        lastConfirmationRequest = "switchAccount"
        recordValidationEvent(
            "switch_confirmation_presented",
            step: "switch_confirmation",
            payload: ["targetName": account.name]
        )
        sealValidationRun?.recordSwitchConfirmationPresented(targetAccount: account)
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
        sealValidationRun?.recordSwitchConfirmationAccepted(targetAccount: account)
        beginLocalSwitch(to: account)
    }

    private func beginLocalSwitch(to account: CodexAccount) {
        pendingSwitchValidationTargetID = account.id
        pendingSwitchValidationTargetName = account.name
        recordValidationEvent(
            "switch_workflow_started",
            step: "switch_workflow_start",
            invariantIds: Self.switchInvariantIDs,
            payload: ["targetName": account.name]
        )
        sealValidationRun?.recordSwitchWorkflowStarted(targetAccount: account)
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

    func handleNotificationResponse(actionIdentifier: String?, userInfo: [AnyHashable: Any]) async {
        let resolvedActionIdentifier = actionIdentifier ?? UNNotificationDefaultActionIdentifier
        guard resolvedActionIdentifier != UNNotificationDefaultActionIdentifier else {
            applicationForegrounder.activate()
            return
        }

        guard
            let accountIDString = userInfo["accountID"] as? String,
            let notifiedAccountID = UUID(uuidString: accountIDString)
        else {
            applicationForegrounder.activate()
            return
        }

        let requestedTarget = requestedNotificationTarget(
            actionIdentifier: resolvedActionIdentifier,
            userInfo: userInfo
        )

        let state = menuState()
        let resolution = notificationActionResolver.resolve(
            notifiedAccountID: notifiedAccountID,
            requestedTarget: requestedTarget,
            currentSnapshots: state.availabilitySnapshots,
            activeAccounts: activeNotificationContexts(from: state),
            settings: AccountAvailabilityNotificationSettings(
                whenBlockedEnabled: notificationStateStore.whenBlockedEnabled,
                whenOutEnabled: notificationStateStore.whenOutEnabled
            )
        )

        applicationForegrounder.activate()

        guard let resolution else {
            return
        }

        switch resolution.target {
        case .local:
            presentNotificationDrivenLocalSwitch(resolution: resolution)
        case .remote(let hostDestination):
            presentNotificationDrivenRemoteSwitch(
                resolution: resolution,
                hostDestination: hostDestination
            )
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
                let eventName: String
                let payload: [String: String]
                switch outcome {
                case .refreshed:
                    eventName = "scheduled_refresh_completed"
                    payload = ["accountName": activeAccount.name]
                case .failed(let message):
                    eventName = "scheduled_refresh_failed"
                    payload = [
                        "accountName": activeAccount.name,
                        "error": message
                    ]
                }
                self.recordValidationEvent(
                    eventName,
                    step: "scheduled_refresh_result",
                    invariantIds: Self.scheduledRefreshInvariantIDs,
                    payload: payload
                )
            }

            await store.refreshInactiveSavedAccountsMetadata()
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
        evaluateNotifications(using: state)
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
            notificationStateStore.markAccountActivated(currentActiveAccountID)
        }

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
        sealValidationRun?.recordActiveAccountChanged(
            fromName: lastObservedActiveAccountName,
            toName: currentActiveAccountName ?? pendingSwitchValidationTargetName ?? "",
            activeAccount: store.activeAccount,
            savedAccounts: store.accounts
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
        evaluateNotifications(using: state)
    }

    private func evaluateNotifications(using state: MenuBarMenuState, now: Date = .now) {
        let currentSnapshots = state.availabilitySnapshots
        defer {
            previousNotificationSnapshots = notificationSnapshotMap(for: state)
        }

        let decision = notificationPolicy.decision(
            previousSnapshots: Array(previousNotificationSnapshots.values),
            currentSnapshots: currentSnapshots,
            activeAccounts: activeNotificationContexts(from: state),
            settings: AccountAvailabilityNotificationSettings(
                whenBlockedEnabled: notificationStateStore.whenBlockedEnabled,
                whenOutEnabled: notificationStateStore.whenOutEnabled
            ),
            now: now
        )
        scheduleNotificationEvaluation(at: decision?.waitUntil)

        guard let decision, decision.shouldNotify else { return }
        guard notificationStateStore.shouldDeliverNotification(
            for: decision.account.id,
            reason: decision.reason,
            window: decision.window
        ) else {
            return
        }
        guard let payload = notificationPayload(for: decision, state: state) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let delivered = await self.notificationDelivery.deliver(payload)
            guard delivered else { return }
            self.notificationStateStore.recordNotification(
                for: decision.account.id,
                reason: decision.reason,
                window: decision.window,
                notifiedAt: now
            )
        }
    }

    private func notificationSnapshotMap(for state: MenuBarMenuState) -> [UUID: AccountAvailabilitySnapshot] {
        Dictionary(uniqueKeysWithValues: state.availabilitySnapshots.map { ($0.account.id, $0) })
    }

    private func activeNotificationContexts(from state: MenuBarMenuState) -> [ActiveAccountAvailabilityContext] {
        var contexts: [ActiveAccountAvailabilityContext] = []
        if let activeAccount = state.activeAccount {
            contexts.append(ActiveAccountAvailabilityContext(target: .local, accountID: activeAccount.id))
        }
        contexts.append(contentsOf: state.connectedRemoteHosts.compactMap { remoteHost in
            guard let remoteAccount = remoteHost.activeAccount else { return nil }
            return ActiveAccountAvailabilityContext(
                target: .remote(hostDestination: remoteHost.destination),
                accountID: remoteAccount.id
            )
        })
        return contexts
    }

    private func notificationPayload(
        for decision: AccountAvailabilityNotificationDecision,
        state: MenuBarMenuState
    ) -> AccountAvailabilityNotificationPayload? {
        let actions = decision.suggestedActions.compactMap { suggestion -> AccountAvailabilityNotificationAction? in
            switch suggestion {
            case .local:
                return AccountAvailabilityNotificationAction(
                    identifier: "use_local",
                    title: "Use on This Mac",
                    kind: .local
                )
            case .remote(let hostDestination):
                let hostName = state.resolvedRemoteHosts.first(where: { $0.destination == hostDestination })?.name ?? hostDestination
                return AccountAvailabilityNotificationAction(
                    identifier: "use_remote",
                    title: "Use on \(hostName)",
                    kind: .remote(hostDestination: hostDestination)
                )
            }
        }

        let renderedCopy = notificationCopyRenderer.render(
            decision: decision,
            remoteHosts: state.resolvedRemoteHosts
        )

        return AccountAvailabilityNotificationPayload(
            accountID: decision.account.id,
            title: renderedCopy.title,
            body: renderedCopy.body,
            actions: actions
        )
    }

    private func requestedNotificationTarget(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> AccountAvailabilityNotificationRequestedTarget {
        switch actionIdentifier {
        case "use_local":
            return .local
        case "use_remote":
            return .remote(preferredHostDestination: userInfo["remoteHostDestination"] as? String)
        case "use_best_option":
            return .bestOption
        default:
            return .bestOption
        }
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
        lastSwitchTargetName = resolution.account.name
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

    private func refreshNotificationAuthorizationState() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let state = await self.notificationDelivery.authorizationState()
            guard self.cachedNotificationAuthorizationState != state else { return }
            self.cachedNotificationAuthorizationState = state
            self.rebuildMenu()
        }
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
                    payload: sanitizedValidationPayload(payload)
                )
            )
        } catch {
            menuBarCoordinatorLogger.error("Failed to record validation event: \(error.localizedDescription, privacy: .public)")
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

    private func triggerValidationScenarioIfNeeded() {
        guard validationScenario == "live-save-current-account-name-dialog-cancelled"
            || validationScenario == "live-save-current-prompt"
        else { return }
        guard AppRuntimeEnvironment.shouldTriggerSaveCurrentPromptValidation() else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.addCurrentAccount()
        }
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
