import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarNotificationWorkflowTests {
    @Test
    func evaluationRendersAndDeliversAvailableAccountPayload() async throws {
        let now = Date()
        let fallback = makeAccount(name: "Business 2", rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 10, weeklyUsedPercent: 20))
        let harness = makeHarness()
        harness.workflow.whenBlockedEnabled = true

        harness.workflow.start(with: makeState(inactiveAccounts: [
            makeAccount(name: "Blocked", rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 100, weeklyUsedPercent: 100))
        ]))
        await harness.workflow.evaluate(using: makeState(inactiveAccounts: [fallback]), now: now)

        let payload = try #require(harness.delivery.payloads.first)
        #expect(payload.accountID == fallback.id)
        #expect(payload.title == "CodexPill")
        #expect(payload.body == "Business 2 is available again")
        #expect(payload.actions.isEmpty)
        #expect(harness.settings.notificationState.accountNotificationState(for: fallback.id)?.isArmed == false)
    }

    @Test
    func toggleOnlyStoresNotificationIntentWithoutRequestingMacPermission() {
        let harness = makeHarness()

        harness.workflow.handleNotificationToggle(enabled: \.whenBlockedEnabled)

        #expect(harness.workflow.whenBlockedEnabled)
        #expect(harness.delivery.requestAuthorizationCount == 0)
        #expect(harness.rebuildCount == 1)
    }

    @Test
    func firstRealNotificationRequestsMacPermissionWhenUndetermined() async throws {
        let now = Date()
        let fallback = makeAccount(name: "Business 2", rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 10, weeklyUsedPercent: 20))
        let harness = makeHarness()
        harness.workflow.whenBlockedEnabled = true
        harness.delivery.authorizationStateValue = .notDetermined
        harness.delivery.authorizationStateAfterRequest = .authorized

        harness.workflow.start(with: makeState(inactiveAccounts: [
            makeAccount(name: "Blocked", rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 100, weeklyUsedPercent: 100))
        ]))
        await harness.workflow.evaluate(using: makeState(inactiveAccounts: [fallback]), now: now)

        #expect(harness.delivery.requestAuthorizationCount == 1)
        #expect(harness.delivery.payloads.count == 1)
        #expect(harness.settings.notificationState.accountNotificationState(for: fallback.id)?.isArmed == false)
    }

    @Test
    func deniedMacPermissionSuppressesDeliveryWithoutClearingSavedIntent() async throws {
        let now = Date()
        let fallback = makeAccount(name: "Business 2", rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 10, weeklyUsedPercent: 20))
        let harness = makeHarness()
        harness.workflow.whenBlockedEnabled = true
        harness.delivery.authorizationStateValue = .denied

        harness.workflow.start(with: makeState(inactiveAccounts: [
            makeAccount(name: "Blocked", rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 100, weeklyUsedPercent: 100))
        ]))
        await harness.workflow.evaluate(using: makeState(inactiveAccounts: [fallback]), now: now)

        #expect(harness.workflow.whenBlockedEnabled)
        #expect(harness.delivery.requestAuthorizationCount == 0)
        #expect(harness.delivery.payloads.isEmpty)
        #expect(harness.settings.notificationState.accountNotificationState(for: fallback.id) == nil)
    }

    @Test
    func staleLocalNotificationClickResolvesCurrentBestAccount() throws {
        let now = Date()
        let stale = makeAccount(name: "Business 1", rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 95, weeklyUsedPercent: 95))
        let currentBest = makeAccount(name: "Business 2", rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 5, weeklyUsedPercent: 5))
        let active = makeAccount(name: "Personal", rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 100, weeklyUsedPercent: 100))
        let harness = makeHarness()
        harness.workflow.whenOutEnabled = true

        harness.workflow.handleResponse(
            payload: AccountAvailabilityNotificationResponsePayload(
                actionIdentifier: "use_local",
                userInfo: ["accountID": stale.id.uuidString]
            ),
            state: makeState(activeAccount: active, inactiveAccounts: [stale, currentBest]),
            now: now
        )

        #expect(harness.activator.activateCount == 1)
        let resolution = try #require(harness.localSwitchResolutions.first)
        #expect(resolution.account.id == currentBest.id)
        #expect(resolution.target == .local)
        #expect(resolution.substitutionMessage == "Business 1 is no longer the best option. Switching to Business 2 instead.")
    }

    @Test
    func staleRemoteNotificationClickDropsWhenRequestedHostIsNoLongerActionable() throws {
        let now = Date()
        let stale = makeAccount(name: "Business 1", rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 5, weeklyUsedPercent: 5))
        let active = makeAccount(name: "Personal", rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 100, weeklyUsedPercent: 100))
        let harness = makeHarness()
        harness.workflow.whenOutEnabled = true

        harness.workflow.handleResponse(
            payload: AccountAvailabilityNotificationResponsePayload(
                actionIdentifier: "use_remote",
                userInfo: [
                    "accountID": stale.id.uuidString,
                    "remoteHostDestination": "user@buildbox"
                ]
            ),
            state: makeState(activeAccount: active, inactiveAccounts: [stale]),
            now: now
        )

        #expect(harness.activator.activateCount == 1)
        #expect(harness.localSwitchResolutions.isEmpty)
        #expect(harness.remoteSwitchResolutions.isEmpty)
    }

    private func makeHarness() -> MenuBarNotificationWorkflowHarness {
        MenuBarNotificationWorkflowHarness()
    }

    private func makeState(
        activeAccount: CodexAccount? = nil,
        inactiveAccounts: [CodexAccount]
    ) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: inactiveAccounts,
            remoteHosts: [],
            visibleInactiveAccountCount: 5,
            visibleInactiveAccountCountOptions: [5],
            refreshIntervalMinutes: 1,
            refreshIntervalOptions: [1],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .twinPills,
            statusBarDisplayMode: .iconOnly,
            isBusy: false,
            statusMessage: ""
        )
    }
}

@MainActor
private final class MenuBarNotificationWorkflowHarness {
    let settings: SettingsStores
    let delivery = AccountAvailabilityNotifierProbe()
    let activator = ApplicationActivatorProbe()
    let settingsLauncher = NotificationSettingsLauncherProbe()
    var workflow: MenuBarNotificationWorkflow!

    private(set) var scheduledRefreshDates: [Date?] = []
    private(set) var localSwitchResolutions: [AccountAvailabilityNotificationActionResolution] = []
    private(set) var remoteSwitchResolutions: [(AccountAvailabilityNotificationActionResolution, String)] = []
    private(set) var rebuildCount = 0

    private let suiteName = "MenuBarNotificationWorkflowTests-\(UUID().uuidString)"

    init() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = SettingsStores(userDefaults: defaults)
        let stateStore = AccountAvailabilityNotificationStore(
            preferences: settings.notificationPreferences,
            stateStore: settings.notificationState
        )
        workflow = MenuBarNotificationWorkflow(
            stateStore: stateStore,
            delivery: delivery,
            applicationActivator: activator,
            settingsLauncher: settingsLauncher,
            scheduleRefresh: { [weak self] date in
                self?.scheduledRefreshDates.append(date)
            },
            presentLocalSwitch: { [weak self] resolution in
                self?.localSwitchResolutions.append(resolution)
            },
            presentRemoteSwitch: { [weak self] resolution, hostDestination in
                self?.remoteSwitchResolutions.append((resolution, hostDestination))
            },
            rebuildMenu: { [weak self] in
                self?.rebuildCount += 1
            }
        )
    }
}

@MainActor
private final class AccountAvailabilityNotifierProbe: AccountAvailabilityNotifier {
    private(set) var payloads: [AccountAvailabilityNotificationPayload] = []
    var authorizationStateValue: NotificationAuthorizationState = .authorized
    var authorizationStateAfterRequest: NotificationAuthorizationState?
    private(set) var requestAuthorizationCount = 0

    func authorizationState() async -> NotificationAuthorizationState {
        authorizationStateValue
    }

    func requestAuthorizationIfNeeded() async {
        requestAuthorizationCount += 1
        if let authorizationStateAfterRequest {
            authorizationStateValue = authorizationStateAfterRequest
        }
    }

    func deliver(_ payload: AccountAvailabilityNotificationPayload) async -> Bool {
        payloads.append(payload)
        return true
    }
}

private final class ApplicationActivatorProbe: ApplicationActivator {
    private(set) var activateCount = 0

    func activate() {
        activateCount += 1
    }
}

private final class NotificationSettingsLauncherProbe: NotificationSettingsLauncher {
    private(set) var openCount = 0

    func openNotificationSettings() {
        openCount += 1
    }
}
