import Foundation
import UserNotifications

@MainActor
final class MenuBarNotificationWorkflow {
    typealias ScheduleRefresh = (Date?) -> Void
    typealias PresentLocalSwitch = (AccountAvailabilityNotificationActionResolution) -> Void
    typealias PresentRemoteSwitch = (AccountAvailabilityNotificationActionResolution, String) -> Void
    typealias RebuildMenu = () -> Void

    private let stateStore: AccountAvailabilityNotificationStore
    private let delivery: AccountAvailabilityNotifier
    private let applicationActivator: ApplicationActivator
    private let settingsLauncher: NotificationSettingsLauncher
    private let scheduleRefresh: ScheduleRefresh
    private let presentLocalSwitch: PresentLocalSwitch
    private let presentRemoteSwitch: PresentRemoteSwitch
    private let rebuildMenu: RebuildMenu
    private let policy = AccountAvailabilityNotificationPolicy()
    private let actionResolver = AccountAvailabilityNotificationActionResolver()
    private let payloadRenderer = AccountAvailabilityNotificationPayloadRenderer()

    private var previousSnapshots: [UUID: AccountAvailabilitySnapshot] = [:]
    private(set) var authorizationState: NotificationAuthorizationState = .unknown

    init(
        stateStore: AccountAvailabilityNotificationStore,
        delivery: AccountAvailabilityNotifier,
        applicationActivator: ApplicationActivator,
        settingsLauncher: NotificationSettingsLauncher,
        scheduleRefresh: @escaping ScheduleRefresh,
        presentLocalSwitch: @escaping PresentLocalSwitch,
        presentRemoteSwitch: @escaping PresentRemoteSwitch,
        rebuildMenu: @escaping RebuildMenu
    ) {
        self.stateStore = stateStore
        self.delivery = delivery
        self.applicationActivator = applicationActivator
        self.settingsLauncher = settingsLauncher
        self.scheduleRefresh = scheduleRefresh
        self.presentLocalSwitch = presentLocalSwitch
        self.presentRemoteSwitch = presentRemoteSwitch
        self.rebuildMenu = rebuildMenu
    }

    var whenBlockedEnabled: Bool {
        get { stateStore.whenBlockedEnabled }
        set { stateStore.whenBlockedEnabled = newValue }
    }

    var whenOutEnabled: Bool {
        get { stateStore.whenOutEnabled }
        set { stateStore.whenOutEnabled = newValue }
    }

    func start(with state: MenuBarMenuState) {
        previousSnapshots = snapshotMap(for: state)
        refreshAuthorizationState()
    }

    func markAccountActivated(_ accountID: UUID) {
        stateStore.markAccountActivated(accountID)
    }

    func handleNotificationToggle(enabled keyPath: ReferenceWritableKeyPath<AccountAvailabilityNotificationStore, Bool>) {
        let hadAnyNotificationsEnabled = stateStore.whenBlockedEnabled || stateStore.whenOutEnabled
        stateStore[keyPath: keyPath].toggle()
        if !hadAnyNotificationsEnabled, stateStore[keyPath: keyPath] {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.delivery.requestAuthorizationIfNeeded()
                self.refreshAuthorizationState()
            }
        }
    }

    func enableNotifications() {
        if !stateStore.whenBlockedEnabled && !stateStore.whenOutEnabled {
            stateStore.whenBlockedEnabled = true
            stateStore.whenOutEnabled = true
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            var state = await self.delivery.authorizationState()
            switch state {
            case .denied:
                self.settingsLauncher.openNotificationSettings()
            case .notDetermined, .unknown:
                await self.delivery.requestAuthorizationIfNeeded()
                state = await self.delivery.authorizationState()
            case .authorized:
                break
            }
            self.authorizationState = state
            self.rebuildMenu()
        }
    }

    func evaluate(using state: MenuBarMenuState, now: Date = .now) {
        let currentSnapshots = state.availabilitySnapshots
        defer {
            previousSnapshots = snapshotMap(for: state)
        }

        let decision = policy.decision(
            previousSnapshots: Array(previousSnapshots.values),
            currentSnapshots: currentSnapshots,
            activeAccounts: activeContexts(from: state),
            settings: settings,
            now: now
        )
        scheduleRefresh(decision?.waitUntil)

        guard let decision, decision.shouldNotify else { return }
        guard stateStore.shouldDeliverNotification(
            for: decision.account.id,
            reason: decision.reason,
            window: decision.window
        ) else {
            return
        }
        guard let payload = payloadRenderer.payload(for: decision, state: state) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let delivered = await self.delivery.deliver(payload)
            guard delivered else { return }
            self.stateStore.recordNotification(
                for: decision.account.id,
                reason: decision.reason,
                window: decision.window,
                notifiedAt: now
            )
        }
    }

    func handleResponse(
        actionIdentifier: String?,
        userInfo: [AnyHashable: Any],
        state: MenuBarMenuState,
        now: Date = .now
    ) {
        let resolvedActionIdentifier = actionIdentifier ?? UNNotificationDefaultActionIdentifier
        guard resolvedActionIdentifier != UNNotificationDefaultActionIdentifier else {
            applicationActivator.activate()
            return
        }

        guard
            let accountIDString = userInfo["accountID"] as? String,
            let notifiedAccountID = UUID(uuidString: accountIDString)
        else {
            applicationActivator.activate()
            return
        }

        let resolution = actionResolver.resolve(
            notifiedAccountID: notifiedAccountID,
            requestedTarget: requestedTarget(
                actionIdentifier: resolvedActionIdentifier,
                userInfo: userInfo
            ),
            currentSnapshots: state.availabilitySnapshots,
            activeAccounts: activeContexts(from: state),
            settings: settings,
            now: now
        )

        applicationActivator.activate()

        guard let resolution else { return }

        switch resolution.target {
        case .local:
            presentLocalSwitch(resolution)
        case .remote(let hostDestination):
            presentRemoteSwitch(resolution, hostDestination)
        }
    }

    func refreshAuthorizationState() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let state = await self.delivery.authorizationState()
            guard self.authorizationState != state else { return }
            self.authorizationState = state
            self.rebuildMenu()
        }
    }

    private var settings: AccountAvailabilityNotificationSettings {
        AccountAvailabilityNotificationSettings(
            whenBlockedEnabled: stateStore.whenBlockedEnabled,
            whenOutEnabled: stateStore.whenOutEnabled
        )
    }

    private func snapshotMap(for state: MenuBarMenuState) -> [UUID: AccountAvailabilitySnapshot] {
        Dictionary(uniqueKeysWithValues: state.availabilitySnapshots.map { ($0.account.id, $0) })
    }

    private func activeContexts(from state: MenuBarMenuState) -> [ActiveAccountAvailabilityContext] {
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

    private func requestedTarget(
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
}
