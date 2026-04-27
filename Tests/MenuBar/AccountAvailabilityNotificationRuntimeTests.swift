import AppKit
import Foundation
import Testing

@testable import CodexPill

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

    private func makeAccount(name: String) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(name.lowercased().replacingOccurrences(of: " ", with: "-")).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "\(name.lowercased().replacingOccurrences(of: " ", with: "-"))@example.com",
            planType: "team",
            rateLimits: nil,
            identity: .empty
        )
    }
}
