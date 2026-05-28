import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarNotificationWorkflowTests {
    @Test
    func evaluationRendersAndDeliversAvailableAccountPayload() async throws {
        let now = Date()
        let fallback = makeAccount(name: "Business 2", sessionUsed: 10, weeklyUsed: 20, now: now)
        let harness = makeHarness()
        harness.workflow.whenBlockedEnabled = true

        harness.workflow.start(with: makeState(inactiveAccounts: [
            makeAccount(name: "Blocked", sessionUsed: 100, weeklyUsed: 100, now: now)
        ]))
        harness.workflow.evaluate(using: makeState(inactiveAccounts: [fallback]), now: now)
        await harness.delivery.waitForPayloadCount(1)

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
        let fallback = makeAccount(name: "Business 2", sessionUsed: 10, weeklyUsed: 20, now: now)
        let harness = makeHarness()
        harness.workflow.whenBlockedEnabled = true
        harness.delivery.authorizationStateValue = .notDetermined
        harness.delivery.authorizationStateAfterRequest = .authorized

        harness.workflow.start(with: makeState(inactiveAccounts: [
            makeAccount(name: "Blocked", sessionUsed: 100, weeklyUsed: 100, now: now)
        ]))
        harness.workflow.evaluate(using: makeState(inactiveAccounts: [fallback]), now: now)
        await harness.delivery.waitForPayloadCount(1)

        #expect(harness.delivery.requestAuthorizationCount == 1)
        #expect(harness.delivery.payloads.count == 1)
        #expect(harness.settings.notificationState.accountNotificationState(for: fallback.id)?.isArmed == false)
    }

    @Test
    func deniedMacPermissionSuppressesDeliveryWithoutClearingSavedIntent() async throws {
        let now = Date()
        let fallback = makeAccount(name: "Business 2", sessionUsed: 10, weeklyUsed: 20, now: now)
        let harness = makeHarness()
        harness.workflow.whenBlockedEnabled = true
        harness.delivery.authorizationStateValue = .denied

        harness.workflow.start(with: makeState(inactiveAccounts: [
            makeAccount(name: "Blocked", sessionUsed: 100, weeklyUsed: 100, now: now)
        ]))
        harness.workflow.evaluate(using: makeState(inactiveAccounts: [fallback]), now: now)
        await harness.delivery.waitForAuthorizationChecks(2)

        #expect(harness.workflow.whenBlockedEnabled)
        #expect(harness.delivery.requestAuthorizationCount == 0)
        #expect(harness.delivery.payloads.isEmpty)
        #expect(harness.settings.notificationState.accountNotificationState(for: fallback.id) == nil)
    }

    @Test
    func staleLocalNotificationClickResolvesCurrentBestAccount() throws {
        let now = Date()
        let stale = makeAccount(name: "Business 1", sessionUsed: 95, weeklyUsed: 95, now: now)
        let currentBest = makeAccount(name: "Business 2", sessionUsed: 5, weeklyUsed: 5, now: now)
        let active = makeAccount(name: "Personal", sessionUsed: 100, weeklyUsed: 100, now: now)
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
        let stale = makeAccount(name: "Business 1", sessionUsed: 5, weeklyUsed: 5, now: now)
        let active = makeAccount(name: "Personal", sessionUsed: 100, weeklyUsed: 100, now: now)
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

    private func makeAccount(
        name: String,
        sessionUsed: Int,
        weeklyUsed: Int,
        now: Date
    ) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(name.lowercased().replacingOccurrences(of: " ", with: "-")).json",
            createdAt: now,
            updatedAt: now,
            email: "\(name.lowercased().replacingOccurrences(of: " ", with: "-"))@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: sessionUsed,
                    resetsAt: now.addingTimeInterval(3_600),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: weeklyUsed,
                    resetsAt: now.addingTimeInterval(86_400),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ),
            identity: .empty
        )
    }
}

@MainActor
private final class MenuBarNotificationWorkflowHarness {
    let settings: CodexPillSettingsStore
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
        settings = CodexPillSettingsStore(userDefaults: defaults)
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
    private(set) var authorizationStateCount = 0

    func authorizationState() async -> NotificationAuthorizationState {
        authorizationStateCount += 1
        return authorizationStateValue
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

    func waitForPayloadCount(_ count: Int) async {
        for _ in 0..<50 {
            let hasPayloads = payloads.count >= count
            if hasPayloads {
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func waitForAuthorizationChecks(_ count: Int) async {
        for _ in 0..<50 {
            if authorizationStateCount >= count {
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
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
