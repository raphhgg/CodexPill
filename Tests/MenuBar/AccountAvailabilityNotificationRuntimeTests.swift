import AppKit
import Foundation
import Testing
import UserNotifications

@testable import CodexPill

@MainActor
struct AccountAvailabilityNotificationRuntimeTests {
    @Test
    func payloadRendererBuildsCopyAndDirectActionsFromMenuState() throws {
        let account = makeAccount(name: "Business 2")
        let renderer = AccountAvailabilityNotificationPayloadRenderer()
        let decision = AccountAvailabilityNotificationDecision(
            shouldNotify: true,
            account: account,
            reason: .whenOut,
            window: AccountAvailabilityNotificationWindow(sessionResetAt: nil, weeklyResetAt: nil),
            waitUntil: nil,
            suggestedActions: [.local, .remote(hostDestination: "user@debian-vm")],
            triggerContext: AccountAvailabilityNotificationTriggerContext(
                accountID: UUID(),
                accountName: "Business 4",
                target: .remote(hostDestination: "user@debian-vm"),
                sessionRemainingPercent: 0,
                weeklyRemainingPercent: 48
            )
        )
        let state = MenuBarMenuState(
            activeAccount: nil,
            inactiveAccounts: [account],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "debian-vm",
                    destination: "user@debian-vm",
                    connectionState: .connected,
                    activeAccount: nil
                )
            ],
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

        let payload = try #require(renderer.payload(for: decision, state: state))

        #expect(payload.accountID == account.id)
        #expect(payload.title == "Business 4 is out on debian-vm")
        #expect(payload.body == "Session limit reached. Business 2 is ready.")
        #expect(payload.actions == [
            AccountAvailabilityNotificationAction(
                identifier: "use_local",
                title: "Use on This Mac",
                kind: .local
            ),
            AccountAvailabilityNotificationAction(
                identifier: "use_remote",
                title: "Use on debian-vm",
                kind: .remote(hostDestination: "user@debian-vm")
            )
        ])
    }

    @Test
    func notificationCenterRequestsAuthorizationOnlyOnce() async {
        let center = UserNotificationCenterProbe()
        let delivery = AccountAvailabilityNotificationCenter(center: center)

        await delivery.requestAuthorizationIfNeeded()
        await delivery.requestAuthorizationIfNeeded()

        #expect(center.requestAuthorizationCallCount == 1)
    }

    @Test
    func notificationCopyRendererExplainsWhenOutForRemoteTarget() {
        let renderer = AccountAvailabilityNotificationCopyRenderer()
        let drainingAccountID = UUID()
        let fallbackAccountID = UUID()

        let rendered = renderer.render(
            decision: AccountAvailabilityNotificationDecision(
                shouldNotify: true,
                account: CodexAccount(
                    id: fallbackAccountID,
                    name: "Business 5",
                    snapshotFileName: "business-5.json",
                    createdAt: .distantPast,
                    updatedAt: .distantPast,
                    email: "business-5@example.com",
                    planType: "team",
                    usage: nil,
                    identity: .empty
                ),
                reason: .whenOut,
                window: AccountAvailabilityNotificationWindow(sessionResetAt: nil, weeklyResetAt: nil),
                waitUntil: nil,
                suggestedActions: [.remote(hostDestination: "user@debian-vm")],
                triggerContext: AccountAvailabilityNotificationTriggerContext(
                    accountID: drainingAccountID,
                    accountName: "Business 1",
                    target: .remote(hostDestination: "user@debian-vm"),
                    sessionRemainingPercent: 0,
                    weeklyRemainingPercent: 42
                )
            ),
            remoteHosts: [
                RemoteHostMenuState(
                    name: "debian-vm",
                    destination: "user@debian-vm",
                    connectionState: .connected,
                    desiredAccount: nil,
                    activeAccount: nil,
                    detectedAccount: nil,
                    verificationStatus: .verified
                )
            ]
        )

        #expect(rendered.title == "Business 1 is out on debian-vm")
        #expect(rendered.body == "Session limit reached. Business 5 is ready.")
    }

    @Test
    func notificationCopyRendererExplainsWhenOutForLocalTargetAndBothWindows() {
        let renderer = AccountAvailabilityNotificationCopyRenderer()

        let rendered = renderer.render(
            decision: AccountAvailabilityNotificationDecision(
                shouldNotify: true,
                account: CodexAccount(
                    id: UUID(),
                    name: "Business 5",
                    snapshotFileName: "business-5.json",
                    createdAt: .distantPast,
                    updatedAt: .distantPast,
                    email: "business-5@example.com",
                    planType: "team",
                    usage: nil,
                    identity: .empty
                ),
                reason: .whenOut,
                window: AccountAvailabilityNotificationWindow(sessionResetAt: nil, weeklyResetAt: nil),
                waitUntil: nil,
                suggestedActions: [.local],
                triggerContext: AccountAvailabilityNotificationTriggerContext(
                    accountID: UUID(),
                    accountName: "Business 1",
                    target: .local,
                    sessionRemainingPercent: 0,
                    weeklyRemainingPercent: 0
                )
            ),
            remoteHosts: []
        )

        #expect(rendered.title == "Business 1 is out on This Mac")
        #expect(rendered.body == "Session and weekly limits reached. Business 5 is ready.")
    }

    @Test
    func notificationCenterDeliversDirectTargetActionsWhenWithinLimit() async throws {
        let center = UserNotificationCenterProbe()
        let delivery = AccountAvailabilityNotificationCenter(center: center)
        let payload = AccountAvailabilityNotificationPayload(
            accountID: UUID(),
            title: "CodexPill",
            body: "Business 4 is available again",
            actions: [
                AccountAvailabilityNotificationAction(
                    identifier: "use_local",
                    title: "Use on This Mac",
                    kind: .local
                ),
                AccountAvailabilityNotificationAction(
                    identifier: "use_remote",
                    title: "Use on debian-vm",
                    kind: .remote(hostDestination: "user@debian-vm")
                )
            ]
        )

        let delivered = await delivery.deliver(payload)

        #expect(delivered)
        let request = try #require(center.addedRequests.first)
        #expect(request.content.body == "Business 4 is available again")
        #expect(request.content.categoryIdentifier.contains("use_local"))
        #expect(request.content.categoryIdentifier.contains("use_remote"))
        #expect(request.content.userInfo["accountID"] as? String == payload.accountID.uuidString)
        #expect(request.content.userInfo["remoteHostDestination"] as? String == "user@debian-vm")
        let category = try #require(center.notificationCategories.first)
        #expect(category.actions.count == 2)
        #expect(category.actions.map(\.title) == ["Use on This Mac", "Use on debian-vm"])
    }

    @Test
    func notificationCenterFallsBackToBestOptionActionWhenDirectActionsExceedLimit() async throws {
        let center = UserNotificationCenterProbe()
        let delivery = AccountAvailabilityNotificationCenter(center: center)
        let payload = AccountAvailabilityNotificationPayload(
            accountID: UUID(),
            title: "CodexPill",
            body: "Business 4 is available again",
            actions: [
                AccountAvailabilityNotificationAction(
                    identifier: "use_local",
                    title: "Use on This Mac",
                    kind: .local
                ),
                AccountAvailabilityNotificationAction(
                    identifier: "use_remote",
                    title: "Use on debian-vm",
                    kind: .remote(hostDestination: "user@debian-vm")
                ),
                AccountAvailabilityNotificationAction(
                    identifier: "use_remote_2",
                    title: "Use on buildbox",
                    kind: .remote(hostDestination: "user@buildbox")
                )
            ]
        )

        let delivered = await delivery.deliver(payload)

        #expect(delivered)
        let category = try #require(center.notificationCategories.first)
        #expect(category.actions.count == 1)
        #expect(category.actions.first?.identifier == "use_best_option")
        #expect(category.actions.first?.title == "Use Best Option")
    }
}
