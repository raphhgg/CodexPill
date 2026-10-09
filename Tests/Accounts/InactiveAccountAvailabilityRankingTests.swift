import Foundation
import Testing

@testable import CodexPill

struct AccountAvailabilityTests {
    @Test
    func availabilityServiceMarksAccountAvailableWhenBothWindowsHaveHeadroom() {
        let service = AccountAvailabilityService()
        let account = makeAccount(name: "Ready", rateLimits: makeRateLimits(sessionUsedPercent: 35, weeklyUsedPercent: 40))

        let availability = service.availability(for: account)

        #expect(availability.target == .local)
        #expect(availability.status == .availableNow)
    }

    @Test
    func availabilityServiceTreatsWeeklyOnlyAccountAsAvailableWhenWeeklyHasHeadroom() {
        let service = AccountAvailabilityService()
        let account = CodexAccount(
            id: UUID(),
            name: "Free",
            snapshotFileName: "free.json",
            createdAt: .now,
            updatedAt: .now,
            email: "free@example.com",
            planType: "free",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "free",
                primary: CodexRateLimitWindow(
                    usedPercent: 0,
                    resetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                secondary: nil,
                fetchedAt: .now
            )
        )

        let availability = service.availability(for: account)

        #expect(availability.status == .availableNow)
        #expect(availability.sessionUsedPercent == 0)
        #expect(availability.weeklyUsedPercent == 0)
    }

    @Test
    func availabilityServiceMarksAccountBlockedBySessionWhenSessionIsExhausted() {
        let service = AccountAvailabilityService()
        let now = Date()
        let resetAt = now.addingTimeInterval(1800)
        let account = makeAccount(
            name: "Session Blocked",
            rateLimits: makeRateLimits(sessionUsedPercent: 100, sessionResetsAt: resetAt, weeklyUsedPercent: 10)
        )

        let availability = service.availability(for: account, now: now)

        #expect(availability.status == .blocked(until: resetAt, reason: .session))
    }

    @Test
    func availabilityServiceMarksAccountBlockedByBothWindowsWhenBothAreExhausted() {
        let service = AccountAvailabilityService()
        let now = Date()
        let sessionResetAt = now.addingTimeInterval(3600)
        let weeklyResetAt = now.addingTimeInterval(7200)
        let account = makeAccount(
            name: "Fully Blocked",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 100,
                sessionResetsAt: sessionResetAt,
                weeklyUsedPercent: 100,
                weeklyResetsAt: weeklyResetAt
            )
        )

        let availability = service.availability(for: account, now: now)

        #expect(availability.status == .blocked(until: sessionResetAt, reason: .sessionAndWeekly))
    }

    @Test
    func availabilityServiceMarksRemoteTargetDisconnectedWhenHostIsDisconnected() {
        let service = AccountAvailabilityService()
        let account = makeAccount(name: "Remote", rateLimits: makeRateLimits(sessionUsedPercent: 10, weeklyUsedPercent: 20))

        let availability = service.availability(
            for: RemoteAccountTargetContext(
                hostDestination: "user@buildbox",
                connectionState: .disconnected,
                verificationState: .failed,
                activeAccount: nil,
                displayAccount: account
            )
        )

        #expect(availability.target == .remote(hostDestination: "user@buildbox"))
        #expect(availability.status == .unavailable(reason: .disconnected))
    }

    @Test
    func availabilityServiceMarksRemoteTargetVerificationFailureWhenHostIsReachableButUnverified() {
        let service = AccountAvailabilityService()
        let account = makeAccount(name: "Remote", rateLimits: makeRateLimits(sessionUsedPercent: 10, weeklyUsedPercent: 20))

        let availability = service.availability(
            for: RemoteAccountTargetContext(
                hostDestination: "user@buildbox",
                connectionState: .connected,
                verificationState: .failed,
                activeAccount: nil,
                displayAccount: account
            )
        )

        #expect(availability.status == .unavailable(reason: .verificationFailed))
    }

    @Test
    func availabilityServiceKeepsDisplayAccountUsageWhenRemoteTargetIsUnverified() {
        let service = AccountAvailabilityService()
        let account = makeAccount(
            name: "Remote",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 35,
                sessionResetsAt: Date(timeIntervalSince1970: 1_800_001_800),
                weeklyUsedPercent: 60,
                weeklyResetsAt: Date(timeIntervalSince1970: 1_800_100_000)
            )
        )

        let availability = service.availability(
            for: RemoteAccountTargetContext(
                hostDestination: "user@buildbox",
                connectionState: .connected,
                verificationState: .unverified,
                activeAccount: nil,
                displayAccount: account
            ),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(availability == AccountTargetAvailability(
            target: .remote(hostDestination: "user@buildbox"),
            status: .unavailable(reason: .unverified),
            sessionUsedPercent: 35,
            weeklyUsedPercent: 60,
            sessionResetAt: Date(timeIntervalSince1970: 1_800_001_800),
            weeklyResetAt: Date(timeIntervalSince1970: 1_800_100_000)
        ))
    }

    @Test
    func availabilityServiceUsesVerifiedRemoteAccountRateLimitsWhenHostIsVerified() {
        let service = AccountAvailabilityService()
        let account = makeAccount(
            name: "Remote",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 100,
                sessionResetsAt: Date().addingTimeInterval(1800),
                weeklyUsedPercent: 20
            )
        )

        let availability = service.availability(
            for: RemoteAccountTargetContext(
                hostDestination: "user@buildbox",
                connectionState: .connected,
                verificationState: .verified,
                activeAccount: account,
                displayAccount: account
            )
        )

        #expect(availability.status != .unavailable(reason: .verificationFailed))
        #expect(availability.target == .remote(hostDestination: "user@buildbox"))
        #expect(availability.sessionUsedPercent == 100)
    }

    @Test
    func availabilitySnapshotExposesLocalAndRemoteTargets() {
        let service = AccountAvailabilityService()
        let now = Date()
        let localResetAt = now.addingTimeInterval(3600)
        let remoteResetAt = now.addingTimeInterval(1800)
        let account = makeAccount(
            name: "Snapshot",
            rateLimits: makeRateLimits(sessionUsedPercent: 100, sessionResetsAt: localResetAt, weeklyUsedPercent: 20)
        )
        let remoteAccount = makeAccount(
            name: "Snapshot",
            rateLimits: makeRateLimits(sessionUsedPercent: 100, sessionResetsAt: remoteResetAt, weeklyUsedPercent: 20)
        )

        let snapshot = service.snapshot(
            for: account,
            remoteTargets: [
                RemoteAccountTargetContext(
                    hostDestination: "user@buildbox",
                    connectionState: .connected,
                    verificationState: .verified,
                    activeAccount: remoteAccount,
                    displayAccount: remoteAccount
                )
            ],
            now: now
        )

        #expect(snapshot.localAvailability.target == .local)
        #expect(snapshot.remoteAvailabilities.count == 1)
        #expect(snapshot.availability(for: .remote(hostDestination: "user@buildbox"))?.status == .blocked(until: remoteResetAt, reason: .session))
    }
}

struct AccountAvailabilityNotificationPolicyTests {
    @Test
    func notificationPolicyNotifiesWithSingleBestAccountWhenBlockedUserBecomesUnblocked() {
        let service = AccountAvailabilityService()
        let policy = AccountAvailabilityNotificationPolicy()
        let now = Date()
        let previouslyBlocked = [
            service.snapshot(
                for: makeAccount(
                    name: "Business 2",
                    rateLimits: makeRateLimits(
                        sessionUsedPercent: 100,
                        sessionResetsAt: now.addingTimeInterval(1800),
                        weeklyUsedPercent: 100,
                        weeklyResetsAt: now.addingTimeInterval(7200)
                    )
                ),
                now: now
            ),
            service.snapshot(
                for: makeAccount(
                    name: "Business 4",
                    rateLimits: makeRateLimits(
                        sessionUsedPercent: 100,
                        sessionResetsAt: now.addingTimeInterval(1200),
                        weeklyUsedPercent: 20
                    )
                ),
                now: now
            )
        ]
        let current = [
            service.snapshot(for: makeAccount(name: "Business 2", rateLimits: makeRateLimits(sessionUsedPercent: 80, weeklyUsedPercent: 20)), now: now),
            service.snapshot(for: makeAccount(name: "Business 4", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 20)), now: now)
        ]

        let decision = policy.decision(
            previousSnapshots: previouslyBlocked,
            currentSnapshots: current,
            activeAccounts: [],
            settings: AccountAvailabilityNotificationSettings(whenBlockedEnabled: true),
            now: now
        )

        #expect(decision?.shouldNotify == true)
        #expect(decision?.reason == .whenBlocked)
        #expect(decision?.account.name == "Business 4")
        #expect(decision?.waitUntil == nil)
    }

    @Test
    func notificationPolicyDoesNotAnnounceFirstSavedAccountAsAvailableAgain() {
        let service = AccountAvailabilityService()
        let policy = AccountAvailabilityNotificationPolicy()
        let now = Date()
        let personal = makeAccount(name: "Personal", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 20))

        let decision = policy.decision(
            previousSnapshots: [],
            currentSnapshots: [
                service.snapshot(for: personal, now: now)
            ],
            activeAccounts: [],
            settings: AccountAvailabilityNotificationSettings(whenBlockedEnabled: true),
            now: now
        )

        #expect(decision == nil)
    }

    @Test
    func notificationPolicyDoesNotAnnounceCurrentAccountAsFallback() {
        let service = AccountAvailabilityService()
        let policy = AccountAvailabilityNotificationPolicy()
        let now = Date()
        let active = makeAccount(name: "Personal", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 20))
        let previous = [
            service.snapshot(
                for: makeAccount(
                    id: active.id,
                    name: "Personal",
                    rateLimits: makeRateLimits(
                        sessionUsedPercent: 100,
                        sessionResetsAt: now.addingTimeInterval(1800),
                        weeklyUsedPercent: 20
                    )
                ),
                now: now
            )
        ]

        let decision = policy.decision(
            previousSnapshots: previous,
            currentSnapshots: [
                service.snapshot(for: active, now: now)
            ],
            activeAccounts: [ActiveAccountAvailabilityContext(target: .local, accountID: active.id)],
            settings: AccountAvailabilityNotificationSettings(whenBlockedEnabled: true),
            now: now
        )

        #expect(decision == nil)
    }

    @Test
    func notificationPolicyIgnoresBarelyUsableAccountsWhenBlockedModeIsEnabled() {
        let service = AccountAvailabilityService()
        let policy = AccountAvailabilityNotificationPolicy()
        let now = Date()
        let previous = [
            service.snapshot(
                for: makeAccount(
                    name: "Blocked",
                    rateLimits: makeRateLimits(
                        sessionUsedPercent: 100,
                        sessionResetsAt: now.addingTimeInterval(1800),
                        weeklyUsedPercent: 100,
                        weeklyResetsAt: now.addingTimeInterval(7200)
                    )
                ),
                now: now
            )
        ]
        let current = [
            service.snapshot(for: makeAccount(name: "Weak", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 97)), now: now)
        ]

        let decision = policy.decision(
            previousSnapshots: previous,
            currentSnapshots: current,
            activeAccounts: [],
            settings: AccountAvailabilityNotificationSettings(whenBlockedEnabled: true),
            now: now
        )

        #expect(decision == nil)
    }

    @Test
    func notificationPolicyDoesNotWaitForBetterFutureAccount() {
        let service = AccountAvailabilityService()
        let policy = AccountAvailabilityNotificationPolicy()
        let now = Date()
        let betterResetAt = now.addingTimeInterval(8 * 60)
        let previous = [
            service.snapshot(
                for: makeAccount(
                    name: "Business 2",
                    rateLimits: makeRateLimits(
                        sessionUsedPercent: 100,
                        sessionResetsAt: now.addingTimeInterval(3600),
                        weeklyUsedPercent: 20
                    )
                ),
                now: now
            ),
            service.snapshot(
                for: makeAccount(
                    name: "Business 4",
                    rateLimits: makeRateLimits(
                        sessionUsedPercent: 100,
                        sessionResetsAt: betterResetAt,
                        weeklyUsedPercent: 20
                    )
                ),
                now: now
            )
        ]
        let current = [
            service.snapshot(for: makeAccount(name: "Business 2", rateLimits: makeRateLimits(sessionUsedPercent: 80, weeklyUsedPercent: 20)), now: now),
            service.snapshot(
                for: makeAccount(
                    name: "Business 4",
                    rateLimits: makeRateLimits(
                        sessionUsedPercent: 100,
                        sessionResetsAt: betterResetAt,
                        weeklyUsedPercent: 20
                    )
                ),
                now: now
            )
        ]

        let decision = policy.decision(
            previousSnapshots: previous,
            currentSnapshots: current,
            activeAccounts: [],
            settings: AccountAvailabilityNotificationSettings(whenBlockedEnabled: true),
            now: now
        )

        #expect(decision?.shouldNotify == true)
        #expect(decision?.account.name == "Business 2")
        #expect(decision?.waitUntil == nil)
    }

    @Test
    func notificationPolicyTriggersWhenOutForLocalActiveAccount() {
        let service = AccountAvailabilityService()
        let policy = AccountAvailabilityNotificationPolicy()
        let now = Date()
        let active = makeAccount(
            name: "Active",
            fingerprint: "active",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(1800),
                weeklyUsedPercent: 20
            )
        )
        let previousAlternative = makeAccount(
            name: "Business 4",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(1800),
                weeklyUsedPercent: 20
            )
        )
        let currentAlternative = makeAccount(name: "Business 4", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 20))

        let decision = policy.decision(
            previousSnapshots: [
                service.snapshot(for: active, now: now),
                service.snapshot(for: previousAlternative, now: now)
            ],
            currentSnapshots: [
                service.snapshot(for: active, now: now),
                service.snapshot(for: currentAlternative, now: now)
            ],
            activeAccounts: [ActiveAccountAvailabilityContext(target: .local, accountID: active.id)],
            settings: AccountAvailabilityNotificationSettings(whenOutEnabled: true),
            now: now
        )

        #expect(decision?.shouldNotify == true)
        #expect(decision?.reason == .whenOut)
        #expect(decision?.account.name == "Business 4")
        #expect(decision?.suggestedActions == [.local])
        #expect(
            decision?.triggerContext == AccountAvailabilityNotificationTriggerContext(
                accountID: active.id,
                accountName: "Active",
                target: .local,
                sessionRemainingPercent: 0,
                weeklyRemainingPercent: 80
            )
        )
    }

    @Test
    func notificationPolicyDoesNotTriggerWhenActiveAccountIsOnlyLow() {
        let service = AccountAvailabilityService()
        let policy = AccountAvailabilityNotificationPolicy()
        let now = Date()
        let active = makeAccount(name: "Active", fingerprint: "active", rateLimits: makeRateLimits(sessionUsedPercent: 95, weeklyUsedPercent: 20))
        let alreadyAvailableAlternative = makeAccount(name: "Business 4", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 20))

        let decision = policy.decision(
            previousSnapshots: [
                service.snapshot(for: active, now: now),
                service.snapshot(for: alreadyAvailableAlternative, now: now)
            ],
            currentSnapshots: [
                service.snapshot(for: active, now: now),
                service.snapshot(for: alreadyAvailableAlternative, now: now)
            ],
            activeAccounts: [ActiveAccountAvailabilityContext(target: .local, accountID: active.id)],
            settings: AccountAvailabilityNotificationSettings(whenOutEnabled: true),
            now: now
        )

        #expect(decision == nil)
    }

    @Test
    func notificationPolicyTriggersWhenOutForVerifiedRemoteActiveAccount() {
        let service = AccountAvailabilityService()
        let policy = AccountAvailabilityNotificationPolicy()
        let now = Date()
        let active = makeAccount(name: "Active Remote", rateLimits: makeRateLimits(sessionUsedPercent: 20, weeklyUsedPercent: 20))
        let outRemote = makeAccount(
            name: "Active Remote",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(1800),
                weeklyUsedPercent: 20
            )
        )
        let previousAlternative = makeAccount(
            name: "Business 5",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(1800),
                weeklyUsedPercent: 20
            )
        )
        let currentAlternative = makeAccount(name: "Business 5", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 20))

        let previous = [
            service.snapshot(
                for: active,
                remoteTargets: [
                    RemoteAccountTargetContext(
                        hostDestination: "debian-vm",
                        connectionState: .connected,
                        verificationState: .verified,
                        activeAccount: outRemote,
                        displayAccount: outRemote
                    )
                ],
                now: now
            ),
            service.snapshot(for: previousAlternative, now: now)
        ]
        let current = [
            service.snapshot(
                for: active,
                remoteTargets: [
                    RemoteAccountTargetContext(
                        hostDestination: "debian-vm",
                        connectionState: .connected,
                        verificationState: .verified,
                        activeAccount: outRemote,
                        displayAccount: outRemote
                    )
                ],
                now: now
            ),
            service.snapshot(for: currentAlternative, now: now)
        ]

        let decision = policy.decision(
            previousSnapshots: previous,
            currentSnapshots: current,
            activeAccounts: [
                ActiveAccountAvailabilityContext(
                    target: .remote(hostDestination: "debian-vm"),
                    accountID: active.id
                )
            ],
            settings: AccountAvailabilityNotificationSettings(whenOutEnabled: true),
            now: now
        )

        #expect(decision?.shouldNotify == true)
        #expect(decision?.reason == .whenOut)
        #expect(decision?.account.name == "Business 5")
        #expect(decision?.suggestedActions == [.remote(hostDestination: "debian-vm")])
        #expect(
            decision?.triggerContext == AccountAvailabilityNotificationTriggerContext(
                accountID: active.id,
                accountName: "Active Remote",
                target: .remote(hostDestination: "debian-vm"),
                sessionRemainingPercent: 0,
                weeklyRemainingPercent: 80
            )
        )
    }

    @Test
    func notificationPolicyTriggersWhenOutWhenLocalActiveAccountBecomesOutAndAlternativeWasAlreadyAvailable() {
        let service = AccountAvailabilityService()
        let policy = AccountAvailabilityNotificationPolicy()
        let now = Date()
        let activeID = UUID()
        let previouslyHealthyActive = makeAccount(id: activeID, name: "Active", fingerprint: "active", rateLimits: makeRateLimits(sessionUsedPercent: 70, weeklyUsedPercent: 20))
        let currentlyBlockedActive = makeAccount(
            id: activeID,
            name: "Active",
            fingerprint: "active",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(90 * 60),
                weeklyUsedPercent: 20
            )
        )
        let alreadyAvailableAlternative = makeAccount(name: "Business 4", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 20))

        let decision = policy.decision(
            previousSnapshots: [
                service.snapshot(for: previouslyHealthyActive, now: now),
                service.snapshot(for: alreadyAvailableAlternative, now: now)
            ],
            currentSnapshots: [
                service.snapshot(for: currentlyBlockedActive, now: now),
                service.snapshot(for: alreadyAvailableAlternative, now: now)
            ],
            activeAccounts: [ActiveAccountAvailabilityContext(target: .local, accountID: currentlyBlockedActive.id)],
            settings: AccountAvailabilityNotificationSettings(whenOutEnabled: true),
            now: now
        )

        #expect(decision?.shouldNotify == true)
        #expect(decision?.reason == .whenOut)
        #expect(decision?.account.name == "Business 4")
        #expect(decision?.suggestedActions == [.local])
    }

    @Test
    func notificationPolicyTriggersWhenOutWhenRemoteActiveAccountBecomesOutAndAlternativeWasAlreadyAvailable() {
        let service = AccountAvailabilityService()
        let policy = AccountAvailabilityNotificationPolicy()
        let now = Date()
        let activeID = UUID()
        let previousRemote = makeAccount(id: activeID, name: "Business 4", rateLimits: makeRateLimits(sessionUsedPercent: 70, weeklyUsedPercent: 20))
        let blockedRemote = makeAccount(
            id: activeID,
            name: "Business 4",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(3 * 60 * 60),
                weeklyUsedPercent: 20
            )
        )
        let alreadyAvailableAlternative = makeAccount(name: "Business 2", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 20))

        let previous = [
            service.snapshot(
                for: previousRemote,
                remoteTargets: [
                    RemoteAccountTargetContext(
                        hostDestination: "debian-vm",
                        connectionState: .connected,
                        verificationState: .verified,
                        activeAccount: previousRemote,
                        displayAccount: previousRemote
                    )
                ],
                now: now
            ),
            service.snapshot(for: alreadyAvailableAlternative, now: now)
        ]
        let current = [
            service.snapshot(
                for: blockedRemote,
                remoteTargets: [
                    RemoteAccountTargetContext(
                        hostDestination: "debian-vm",
                        connectionState: .connected,
                        verificationState: .verified,
                        activeAccount: blockedRemote,
                        displayAccount: blockedRemote
                    )
                ],
                now: now
            ),
            service.snapshot(for: alreadyAvailableAlternative, now: now)
        ]

        let decision = policy.decision(
            previousSnapshots: previous,
            currentSnapshots: current,
            activeAccounts: [
                ActiveAccountAvailabilityContext(
                    target: .remote(hostDestination: "debian-vm"),
                    accountID: blockedRemote.id
                )
            ],
            settings: AccountAvailabilityNotificationSettings(whenOutEnabled: true),
            now: now
        )

        #expect(decision?.shouldNotify == true)
        #expect(decision?.reason == .whenOut)
        #expect(decision?.account.name == "Business 2")
        #expect(decision?.suggestedActions == [.remote(hostDestination: "debian-vm")])
    }

    @Test
    func notificationActionResolverSubstitutesCurrentBestAccount() {
        let service = AccountAvailabilityService()
        let resolver = AccountAvailabilityNotificationActionResolver()
        let now = Date()
        let staleBest = makeAccount(name: "Business 4", rateLimits: makeRateLimits(sessionUsedPercent: 95, weeklyUsedPercent: 20))
        let betterCurrent = makeAccount(name: "Business 2", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 20))

        let resolution = resolver.resolve(
            notifiedAccountID: staleBest.id,
            requestedTarget: .local,
            currentSnapshots: [
                service.snapshot(for: staleBest, now: now),
                service.snapshot(for: betterCurrent, now: now)
            ],
            activeAccounts: [ActiveAccountAvailabilityContext(target: .local, accountID: staleBest.id)],
            settings: AccountAvailabilityNotificationSettings(whenOutEnabled: true),
            now: now
        )

        #expect(resolution?.account.name == "Business 2")
        #expect(resolution?.target == .local)
        #expect(resolution?.substitutionMessage == "Business 4 is no longer the best option. Switching to Business 2 instead.")
    }

    @Test
    func notificationActionResolverUsesPreferredRemoteHostWhenStillSuggested() {
        let service = AccountAvailabilityService()
        let resolver = AccountAvailabilityNotificationActionResolver()
        let now = Date()
        let outAccount = makeAccount(
            name: "Business 4",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(1800),
                weeklyUsedPercent: 20
            )
        )
        let ready = makeAccount(name: "Business 2", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 20))

        let resolution = resolver.resolve(
            notifiedAccountID: ready.id,
            requestedTarget: .remote(preferredHostDestination: "debian-vm"),
            currentSnapshots: [
                service.snapshot(
                    for: outAccount,
                    remoteTargets: [
                        RemoteAccountTargetContext(
                            hostDestination: "debian-vm",
                            connectionState: .connected,
                            verificationState: .verified,
                            activeAccount: outAccount,
                            displayAccount: outAccount
                        )
                    ],
                    now: now
                ),
                service.snapshot(for: ready, now: now)
            ],
            activeAccounts: [
                ActiveAccountAvailabilityContext(
                    target: .remote(hostDestination: "debian-vm"),
                    accountID: outAccount.id
                )
            ],
            settings: AccountAvailabilityNotificationSettings(whenOutEnabled: true),
            now: now
        )

        #expect(resolution?.account.name == "Business 2")
        #expect(resolution?.target == .remote(hostDestination: "debian-vm"))
    }

    @Test
    func notificationActionResolverRejectsPreferredRemoteHostWhenNoLongerSuggested() {
        let service = AccountAvailabilityService()
        let resolver = AccountAvailabilityNotificationActionResolver()
        let now = Date()
        let noLongerOut = makeAccount(
            name: "Business 4",
            rateLimits: makeRateLimits(sessionUsedPercent: 20, weeklyUsedPercent: 20)
        )
        let ready = makeAccount(name: "Business 2", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 20))

        let resolution = resolver.resolve(
            notifiedAccountID: ready.id,
            requestedTarget: .remote(preferredHostDestination: "debian-vm"),
            currentSnapshots: [
                service.snapshot(
                    for: noLongerOut,
                    remoteTargets: [
                        RemoteAccountTargetContext(
                            hostDestination: "debian-vm",
                            connectionState: .connected,
                            verificationState: .verified,
                            activeAccount: noLongerOut,
                            displayAccount: noLongerOut
                        )
                    ],
                    now: now
                ),
                service.snapshot(for: ready, now: now)
            ],
            activeAccounts: [
                ActiveAccountAvailabilityContext(
                    target: .remote(hostDestination: "debian-vm"),
                    accountID: noLongerOut.id
                )
            ],
            settings: AccountAvailabilityNotificationSettings(whenOutEnabled: true),
            now: now
        )

        #expect(resolution == nil)
    }

    @Test
    func notificationActionResolverReturnsNilWhenNoValidAccountRemains() {
        let service = AccountAvailabilityService()
        let resolver = AccountAvailabilityNotificationActionResolver()
        let now = Date()
        let blocked = makeAccount(
            name: "Business 4",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(1800),
                weeklyUsedPercent: 20
            )
        )

        let resolution = resolver.resolve(
            notifiedAccountID: blocked.id,
            requestedTarget: .bestOption,
            currentSnapshots: [service.snapshot(for: blocked, now: now)],
            activeAccounts: [],
            settings: AccountAvailabilityNotificationSettings(whenBlockedEnabled: true),
            now: now
        )

        #expect(resolution == nil)
    }

    @MainActor
    @Test
    func notificationStateStoreSuppressesDisabledReasons() {
        let settings = makeNotificationSettings()
        let store = AccountAvailabilityNotificationStore(
            preferences: settings.notificationPreferences,
            stateStore: settings.notificationState
        )
        let accountID = UUID()

        #expect(
            !store.shouldDeliverNotification(
                for: accountID,
                reason: .whenBlocked,
                window: .init(sessionResetAt: .distantFuture, weeklyResetAt: .distantFuture)
            )
        )
    }

    @MainActor
    @Test
    func notificationStateStoreDoesNotRepeatUntilAccountIsActivated() {
        let settings = makeNotificationSettings()
        let store = AccountAvailabilityNotificationStore(
            preferences: settings.notificationPreferences,
            stateStore: settings.notificationState
        )
        let accountID = UUID()
        let firstWindow = AccountAvailabilityNotificationWindow(
            sessionResetAt: Date().addingTimeInterval(1800),
            weeklyResetAt: Date().addingTimeInterval(86_400)
        )
        let laterWindow = AccountAvailabilityNotificationWindow(
            sessionResetAt: Date().addingTimeInterval(5400),
            weeklyResetAt: Date().addingTimeInterval(172_800)
        )

        store.whenBlockedEnabled = true

        #expect(store.shouldDeliverNotification(for: accountID, reason: .whenBlocked, window: firstWindow))

        store.recordNotification(for: accountID, reason: .whenBlocked, window: firstWindow)

        #expect(!store.shouldDeliverNotification(for: accountID, reason: .whenBlocked, window: firstWindow))
        #expect(!store.shouldDeliverNotification(for: accountID, reason: .whenBlocked, window: laterWindow))

        store.markAccountActivated(accountID)

        #expect(store.shouldDeliverNotification(for: accountID, reason: .whenBlocked, window: laterWindow))
    }

    @MainActor
    @Test
    func notificationStateStorePersistsRecordedWindowAndReason() throws {
        let settings = makeNotificationSettings()
        let store = AccountAvailabilityNotificationStore(
            preferences: settings.notificationPreferences,
            stateStore: settings.notificationState
        )
        let accountID = UUID()
        let now = Date()
        let window = AccountAvailabilityNotificationWindow(
            sessionResetAt: now.addingTimeInterval(1200),
            weeklyResetAt: now.addingTimeInterval(86_400)
        )

        store.whenOutEnabled = true
        store.recordNotification(
            for: accountID,
            reason: .whenOut,
            window: window,
            notifiedAt: now
        )

        let persisted = try #require(settings.accountNotificationState(for: accountID))
        #expect(!persisted.isArmed)
        #expect(persisted.lastNotification?.reason == .whenOut)
        #expect(persisted.lastNotification?.window == PersistedAccountNotificationWindow(
            sessionResetAt: window.sessionResetAt,
            weeklyResetAt: window.weeklyResetAt
        ))
    }
}

struct InactiveAccountAvailabilityRankingTests {
    @Test
    func prefersWeeklyHeadroomBeforeSessionReadiness() {
        let ranking = InactiveAccountAvailabilityRanking()
        let weeklyHealthy = makeAccount(
            name: "Weekly Healthy",
            rateLimits: makeRateLimits(sessionUsedPercent: 35, weeklyUsedPercent: 40)
        )
        let weeklyConstrained = makeAccount(
            name: "Weekly Constrained",
            rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 96)
        )

        let sorted = ranking.sort([weeklyConstrained, weeklyHealthy])

        #expect(sorted.map(\.name) == ["Weekly Healthy", "Weekly Constrained"])
    }

    @Test
    func breaksTiesByNextAvailabilityThenUsageThenName() {
        let ranking = InactiveAccountAvailabilityRanking()
        let now = Date()
        let laterReset = now.addingTimeInterval(7_200)
        let earlierReset = now.addingTimeInterval(3_600)
        let earlierAvailable = makeAccount(
            name: "Earlier",
            rateLimits: makeRateLimits(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 60)
        )
        let laterAvailable = makeAccount(
            name: "Later",
            rateLimits: makeRateLimits(sessionUsedPercent: 60, sessionResetsAt: laterReset, weeklyUsedPercent: 60)
        )
        let sameAvailabilityHigherUsage = makeAccount(
            name: "Higher Usage",
            rateLimits: makeRateLimits(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 90)
        )
        let sameMetricsNameB = makeAccount(
            name: "Zulu",
            rateLimits: makeRateLimits(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 80)
        )
        let sameMetricsNameA = makeAccount(
            name: "Alpha",
            rateLimits: makeRateLimits(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 80)
        )

        let sorted = ranking.sort([
            laterAvailable,
            sameMetricsNameB,
            sameAvailabilityHigherUsage,
            sameMetricsNameA,
            earlierAvailable
        ])

        #expect(sorted.map(\.name) == ["Earlier", "Alpha", "Zulu", "Later", "Higher Usage"])
    }

    @MainActor
    @Test
    func accountsControllerDelegatesInactiveSortingToRankingPolicy() async {
        let preferred = makeAccount(name: "Preferred", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 10))
        let constrained = makeAccount(name: "Constrained", rateLimits: makeRateLimits(sessionUsedPercent: 90, weeklyUsedPercent: 100))
        let active = makeAccount(name: "Active", fingerprint: "active", rateLimits: makeRateLimits(sessionUsedPercent: 20, weeklyUsedPercent: 20))
        let repository = RankingLoadingPersistingAccountCatalogProbe(accountsToLoad: [constrained, active, preferred])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: LiveIdentityStub(fingerprint: "active"),
            storedAccountReconciler: PassthroughIdentityReconciler()
        )
        let controller = AccountsController(
            identityResolver: identityResolver,
            inactiveAccountAvailabilityRanking: InactiveAccountAvailabilityRanking(),
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                accountStatusClient: StubAccountStatusClient(error: RankingTestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: RankingNullAuthService(),
                accountStatusClient: StubAccountStatusClient(error: RankingTestFailure.backgroundRefreshFailed),
                savedAccountStatusClient: DisabledAccountStatusClient(),
                identityResolver: identityResolver,
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            accountCatalogStore: repository,
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: RankingNullAuthService(),
                repository: repository,
                codexAppProcessClient: CodexAppProcessProbe(),
                identityResolver: identityResolver
            ),
            addAccountWorkflow: AddAccountWorkflow(
                authService: RankingNullAuthService(),
                repository: repository,
                identityResolver: identityResolver
            )
        )

        controller.load()

        #expect(controller.activeAccount?.name == "Active")
        #expect(controller.sortedInactiveAccounts.map(\.name) == ["Preferred", "Constrained"])
    }
}

@MainActor
private func makeNotificationSettings() -> CodexPillSettingsStore {
    let suiteName = "NotificationStateStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return CodexPillSettingsStore(userDefaults: defaults)
}

private enum RankingTestFailure: LocalizedError {
    case backgroundRefreshFailed

    var errorDescription: String? {
        switch self {
        case .backgroundRefreshFailed:
            "Background refresh failed."
        }
    }
}

private final class RankingLoadingPersistingAccountCatalogProbe: AccountCatalogLoader, AccountSnapshotRemover {
    let accountsToLoad: [CodexAccount]

    init(accountsToLoad: [CodexAccount]) {
        self.accountsToLoad = accountsToLoad
    }

    func bootstrapStorage() throws {}

    func loadAccounts() throws -> [CodexAccount] {
        accountsToLoad
    }

    func saveAccounts(_: [CodexAccount]) throws {}

    func deleteSnapshot(for _: CodexAccount) throws {}
}

private struct RankingNullAuthService: CodexAuthSessionStore, CodexSignInAuthStore {
    func activate(_ account: CodexAccount) throws {}
    func readCurrentAuthData() throws -> Data { Data() }
    func readAuthSnapshot(for account: CodexAccount) throws -> Data { Data() }
    func currentAuthFingerprint() -> String? { nil }
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity { .empty }
    func restoreCurrentAuthData(_ data: Data) throws {}

    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
        existing ?? CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: .empty
        )
    }

    func deleteAuthSnapshot(for account: CodexAccount) throws {}
}
