import AppKit
import Foundation
import Testing
import UserNotifications

@testable import CodexPill

@MainActor
struct MenuBarCoordinatorTests {
    @Test
    func removeAccountSignsOutLocalAndRemoteTargetsBeforeDeletingSavedAccount() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let account = try harness.makeActiveAccount(named: "Business 4", email: "business-4@example.com")
        let hostState = PersistedRemoteHostState(
            host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
            installedAccountIDs: [account.id],
            desiredAccountID: account.id,
            verifiedAccount: account
        )
        harness.settings.remoteHostSettings.remoteHostStates = [hostState]
        harness.alertPresenter.confirmationResponse = true
        let coordinator = harness.makeCoordinator(
            accountsRemoteHostClient: ValidationRemoteHostClient(seedStates: [hostState]),
            remoteHostOperations: ValidationRemoteHostClient(seedStates: [hostState])
        )
        coordinator.start()
        await coordinator.waitForPendingWork()

        coordinator.removeAccount(harness.menuItem(representing: account.id.uuidString))
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.last?.messageText == "Business 4 is in use")
        #expect(harness.alertPresenter.confirmationRequests.last?.informativeText == "Sign out on This Mac and debian-vm before removing it?")
        #expect(harness.accountsController.accounts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: harness.repository.paths.codexAuthFile.path))
        #expect(harness.settings.remoteHostSettings.remoteHostStates.first?.verifiedAccount == nil)
        #expect(harness.settings.remoteHostSettings.remoteHostStates.first?.desiredAccountID == nil)
    }

    @Test
    func notificationResponseSubstitutesBetterRemoteAccountAndExplainsIt() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let now = Date()
        let notifiedAccount = makeAccount(
            name: "Business 4",
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(60 * 60),
                weeklyUsedPercent: 20,
                weeklyResetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                fetchedAt: now
            )
        )
        let betterAccount = makeAccount(
            name: "Business 2",
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 0,
                sessionResetsAt: now.addingTimeInterval(3 * 60 * 60),
                weeklyUsedPercent: 20,
                weeklyResetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                fetchedAt: now
            )
        )
        try harness.repository.saveAccounts([notifiedAccount, betterAccount])
        let hostState = PersistedRemoteHostState(
            host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
            installedAccountIDs: [notifiedAccount.id],
            desiredAccountID: notifiedAccount.id,
            verifiedAccount: notifiedAccount
        )
        harness.settings.notificationPreferences.notificationsWhenOutEnabled = true
        harness.settings.remoteHostSettings.remoteHostStates = [hostState]
        harness.alertPresenter.confirmationResponse = true
        let coordinator = harness.makeCoordinator(
            accountsRemoteHostClient: ValidationRemoteHostClient(seedStates: [hostState]),
            remoteHostOperations: ValidationRemoteHostClient(seedStates: [hostState])
        )
        coordinator.start()
        await coordinator.waitForPendingWork()

        await coordinator.handleNotificationResponse(AccountAvailabilityNotificationResponsePayload(
            actionIdentifier: "use_remote",
            userInfo: [
                "accountID": notifiedAccount.id.uuidString,
                "remoteHostDestination": "user@debian-vm"
            ]
        ))
        await coordinator.waitForPendingWork()

        #expect(harness.applicationActivator.activateCallCount == 1)
        let confirmation = try #require(harness.alertPresenter.confirmationRequests.last)
        #expect(confirmation.informativeText.contains("Business 4 is no longer the best option. Switching to Business 2 instead."))
        #expect(harness.settings.remoteHostSettings.remoteHostState(for: "user@debian-vm")?.verifiedAccount?.id == betterAccount.id)
    }

    @Test
    func notificationResponseFailureOpensAppAndShowsRealError() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let now = Date()
        let outAccount = makeAccount(
            name: "Business 4",
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(60 * 60),
                weeklyUsedPercent: 20,
                weeklyResetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                fetchedAt: now
            )
        )
        let notifiedAccount = makeAccount(
            name: "Business 2",
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 0,
                sessionResetsAt: now.addingTimeInterval(3 * 60 * 60),
                weeklyUsedPercent: 20,
                weeklyResetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                fetchedAt: now
            )
        )
        try harness.repository.saveAccounts([outAccount, notifiedAccount])
        harness.settings.notificationPreferences.notificationsWhenOutEnabled = true
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
                installedAccountIDs: [outAccount.id, notifiedAccount.id],
                desiredAccountID: outAccount.id,
                verifiedAccount: outAccount
            )
        ]
        harness.alertPresenter.confirmationResponse = true
        let failingHostClient = RemoteHostStub(
            status: CodexAccountStatus(
                email: outAccount.email,
                planType: outAccount.planType,
                usage: outAccount.usage
            ),
            switchError: RemoteHostClientError.commandFailed("ssh failure")
        )
        let coordinator = harness.makeCoordinator(
            accountsRemoteHostClient: failingHostClient,
            remoteHostOperations: failingHostClient
        )
        coordinator.start()
        await coordinator.waitForPendingWork()

        await coordinator.handleNotificationResponse(AccountAvailabilityNotificationResponsePayload(
            actionIdentifier: "use_remote",
            userInfo: [
                "accountID": notifiedAccount.id.uuidString,
                "remoteHostDestination": "user@debian-vm"
            ]
        ))
        await coordinator.waitForPendingWork()

        #expect(harness.applicationActivator.activateCallCount == 1)
        let infoRequest = try #require(harness.alertPresenter.infoRequests.last)
        #expect(infoRequest.informativeText == "ssh failure")
    }

    @Test
    func localNotificationResponseShowsOnlyNotificationConfirmation() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let now = Date()
        let account = makeAccount(
            name: "Business 3",
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 0,
                sessionResetsAt: now.addingTimeInterval(3 * 60 * 60),
                weeklyUsedPercent: 20,
                weeklyResetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                fetchedAt: now
            )
        )
        try harness.repository.writeSnapshot(data: Data("{}".utf8), for: account)
        try harness.repository.saveAccounts([account])
        harness.settings.notificationPreferences.notificationsWhenBlockedEnabled = true
        harness.alertPresenter.confirmationResponse = true
        let coordinator = harness.makeCoordinator()
        coordinator.start()
        await coordinator.waitForPendingWork()

        await coordinator.handleNotificationResponse(AccountAvailabilityNotificationResponsePayload(
            actionIdentifier: "use_local",
            userInfo: ["accountID": account.id.uuidString]
        ))
        await coordinator.waitForPendingWork()

        #expect(harness.applicationActivator.activateCallCount == 1)
        #expect(harness.alertPresenter.confirmationRequests.count == 1)
        #expect(harness.alertPresenter.confirmationRequests.last?.messageText == "Use Business 3 now?")
    }

    @Test
    func enableNotificationsDoesNotRequestAuthorizationWhenUndetermined() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let center = UserNotificationCenterProbe()
        center.authorizationStatus = .notDetermined
        let coordinator = harness.makeCoordinator(
            notificationDelivery: AccountAvailabilityNotificationCenter(center: center)
        )

        coordinator.enableNotifications(NSMenuItem())
        await coordinator.waitForPendingWork()

        #expect(!harness.settings.notificationPreferences.notificationsWhenBlockedEnabled)
        #expect(!harness.settings.notificationPreferences.notificationsWhenOutEnabled)
        #expect(center.requestAuthorizationCallCount == 0)
        #expect(harness.notificationSettingsLauncher.openCallCount == 0)
    }

    @Test
    func enableNotificationsOpensSystemSettingsWhenAuthorizationWasDenied() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.settings.notificationPreferences.notificationsWhenBlockedEnabled = true
        let center = UserNotificationCenterProbe()
        center.authorizationStatus = .denied
        let coordinator = harness.makeCoordinator(
            notificationDelivery: AccountAvailabilityNotificationCenter(center: center)
        )

        coordinator.enableNotifications(NSMenuItem())
        await coordinator.waitForPendingWork()

        #expect(harness.settings.notificationPreferences.notificationsWhenBlockedEnabled)
        #expect(!harness.settings.notificationPreferences.notificationsWhenOutEnabled)
        #expect(center.requestAuthorizationCallCount == 0)
        #expect(harness.notificationSettingsLauncher.openCallCount == 1)
    }

    @Test
    func enablingNotificationTogglesStoresIntentWithoutRequestingPermission() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let center = UserNotificationCenterProbe()
        let coordinator = harness.makeCoordinator(
            notificationDelivery: AccountAvailabilityNotificationCenter(center: center)
        )

        coordinator.toggleNotificationsWhenBlocked(NSMenuItem())
        coordinator.toggleNotificationsWhenOut(NSMenuItem())
        await coordinator.waitForPendingWork()

        #expect(center.requestAuthorizationCallCount == 0)
        #expect(harness.settings.notificationPreferences.notificationsWhenBlockedEnabled)
        #expect(harness.settings.notificationPreferences.notificationsWhenOutEnabled)
    }

    @Test
    func addHostCancellationAfterValidationDoesNotPersistPendingHost() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let activeAccount = try harness.makeActiveAccount(named: "Business 1", email: "business-1@example.com")
        harness.panelPresenter.hostSetupResponse = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        harness.alertPresenter.confirmationResponse = false
        let coordinator = harness.makeCoordinator(
            accountsRemoteHostClient: RemoteHostStub(
                status: CodexAccountStatus(email: activeAccount.email, planType: activeAccount.planType, usage: nil)
            ),
            remoteHostOperations: RemoteHostStub()
        )

        coordinator.addHost(NSMenuItem())
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.count == 1)
        #expect(harness.settings.remoteHostSettings.remoteHostStates.isEmpty)
    }

    @Test
    func addHostPersistsVerifiedHostOnlyAfterInstallConfirmation() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let activeAccount = try harness.makeActiveAccount(named: "Business 1", email: "business-1@example.com")
        let remoteHostClient = RemoteHostStub(
            status: CodexAccountStatus(email: activeAccount.email, planType: activeAccount.planType, usage: nil)
        )
        harness.panelPresenter.hostSetupResponse = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        harness.alertPresenter.confirmationResponse = true
        let coordinator = harness.makeCoordinator(
            accountsRemoteHostClient: remoteHostClient,
            remoteHostOperations: remoteHostClient
        )

        coordinator.addHost(NSMenuItem())
        await coordinator.waitForPendingWork()

        let hostState = try #require(harness.settings.remoteHostSettings.remoteHostState(for: "user@buildbox"))
        #expect(hostState.desiredAccountID == activeAccount.id)
        #expect(hostState.verifiedAccount?.id == activeAccount.id)
        #expect(hostState.verificationStatus == .verified)
        #expect(hostState.installedAccountIDs.contains(activeAccount.id))
    }

    @Test
    func coordinatorRestoresPersistedRemoteHostAccountOnStart() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.settings.remoteHostSettings.configuredRemoteHost = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        harness.settings.remoteHostSettings.remoteHostActiveAccount = makeAccount(
            name: "Business 2",
            email: "remote@example.com",
            planType: "team"
        )
        let coordinator = harness.makeCoordinator(
            remoteHostOperations: RemoteHostStub(
                status: CodexAccountStatus(
                    email: "remote@example.com",
                    planType: "team",
                    usage: makeUsage(
                        planType: "team",
                        sessionUsedPercent: 69,
                        sessionResetsAt: Date(timeIntervalSince1970: 2_000_000_000)
                    )
                )
            )
        )

        coordinator.start()
        await coordinator.waitForPendingWork()

        let state = coordinator.menuState()
        #expect(state.activeAccountCards.first?.account.email == "remote@example.com")
        #expect(state.connectedRemoteHosts.first?.activeAccount?.email == "remote@example.com")
    }

    @Test
    func coordinatorMarksPersistedRemoteHostDisconnectedWhenRefreshFails() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let persistedAccount = makeAccount(name: "Business 2", email: "fallback@example.com", planType: "team")
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                activeAccount: persistedAccount
            )
        ]
        let coordinator = harness.makeCoordinator(
            remoteHostOperations: RemoteHostStub(
                readError: RemoteHostClientError.commandFailed("ssh: connection refused")
            )
        )

        coordinator.start()
        await coordinator.waitForPendingWork()

        let persistedHostState = try #require(harness.settings.remoteHostSettings.remoteHostState(for: "user@buildbox"))
        #expect(persistedHostState.desiredAccountID == persistedAccount.id)
        #expect(persistedHostState.activeAccount == nil)
        #expect(persistedHostState.verificationStatus == .failed)
        #expect(coordinator.menuState().connectedRemoteHosts.isEmpty)
    }

    @Test
    func coordinatorMarksPersistedRemoteHostFailedWhenDesiredAccountIsMissingLocally() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: UUID(),
                verifiedAccount: nil,
                verificationStatus: .unverified
            )
        ]
        let coordinator = harness.makeCoordinator(remoteHostOperations: RemoteHostStub())

        coordinator.start()
        await coordinator.waitForPendingWork()

        let refreshedState = try #require(harness.settings.remoteHostSettings.remoteHostState(for: "user@buildbox"))
        #expect(refreshedState.verificationStatus == .failed)
        #expect(refreshedState.lastVerificationError == "Saved account for buildbox is no longer available on this Mac.")
        #expect(coordinator.menuState().connectedRemoteHosts.isEmpty)
    }

    @Test
    func coordinatorRestoresAllPersistedRemoteHostAccountsOnStart() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                activeAccount: makeAccount(name: "Business 2", email: "buildbox@example.com", planType: "team")
            ),
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
                activeAccount: makeAccount(name: "Business 3", email: "debian@example.com", planType: "team")
            )
        ]
        let coordinator = harness.makeCoordinator(
            remoteHostOperations: RemoteHostStub(
                statusesByDestination: [
                    "user@buildbox": CodexAccountStatus(email: "buildbox@example.com", planType: "team", usage: nil),
                    "user@debian-vm": CodexAccountStatus(email: "debian@example.com", planType: "team", usage: nil)
                ]
            )
        )

        coordinator.start()
        await coordinator.waitForPendingWork()

        let remoteHosts = coordinator.menuState().connectedRemoteHosts
        #expect(remoteHosts.count == 2)
        #expect(remoteHosts.contains(where: { $0.name == "buildbox" && $0.activeAccount?.email == "buildbox@example.com" }))
        #expect(remoteHosts.contains(where: { $0.name == "debian-vm" && $0.activeAccount?.email == "debian@example.com" }))
    }

    @Test
    func coordinatorShowsOnlyReachableRemoteHostsInPrimarySectionWhenRestoreIsMixed() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                activeAccount: makeAccount(name: "Business 2", email: "buildbox@example.com", planType: "team")
            ),
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
                activeAccount: makeAccount(name: "Business 3", email: "debian@example.com", planType: "team")
            )
        ]
        let coordinator = harness.makeCoordinator(
            remoteHostOperations: RemoteHostStub(
                statusesByDestination: [
                    "user@buildbox": CodexAccountStatus(email: "buildbox@example.com", planType: "team", usage: nil)
                ],
                readErrorsByDestination: [
                    "user@debian-vm": RemoteHostClientError.commandFailed("ssh: connection refused")
                ]
            )
        )

        coordinator.start()
        await coordinator.waitForPendingWork()

        let remoteHosts = coordinator.menuState().connectedRemoteHosts
        #expect(remoteHosts.count == 1)
        #expect(remoteHosts.first?.name == "buildbox")
        #expect(remoteHosts.first?.activeAccount?.email == "buildbox@example.com")
        let remoteHostSettings = harness.settings.remoteHostSettings
        #expect(remoteHostSettings.remoteHostStates.count == 2)
        #expect(remoteHostSettings.remoteHostState(for: "user@buildbox")?.activeAccount?.email == "buildbox@example.com")
        #expect(remoteHostSettings.remoteHostState(for: "user@debian-vm")?.desiredAccountID != nil)
        #expect(remoteHostSettings.remoteHostState(for: "user@debian-vm")?.activeAccount == nil)
        #expect(remoteHostSettings.remoteHostState(for: "user@debian-vm")?.verificationStatus == .failed)
    }

    @Test
    func reverifyHostActionPromotesFailedHostBackToVerified() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let persistedAccount = makeAccount(name: "Business 2", email: "business-2@example.com", planType: "team")
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: persistedAccount.id,
                verifiedAccount: persistedAccount,
                verificationStatus: .failed,
                lastVerificationError: "ssh: connection refused"
            )
        ]
        let coordinator = harness.makeCoordinator(
            remoteHostOperations: RemoteHostStub(
                status: CodexAccountStatus(email: "business-2@example.com", planType: "team", usage: nil)
            )
        )
        coordinator.start()
        await coordinator.waitForPendingWork()

        let item = NSMenuItem(title: "Re-verify Remote Account", action: nil, keyEquivalent: "")
        item.representedObject = HostSelectionMenuItemPayload(hostDestination: "user@buildbox")
        coordinator.reverifyHost(item)
        await coordinator.waitForPendingWork()

        let refreshedState = try #require(harness.settings.remoteHostSettings.remoteHostState(for: "user@buildbox"))
        #expect(refreshedState.verificationStatus == .verified)
        #expect(refreshedState.activeAccount?.email == "business-2@example.com")
    }

    @Test
    func adoptDetectedRemoteAccountPromotesMismatchToVerified() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let desiredAccount = makeAccount(
            name: "Business 2",
            email: "business-2@example.com",
            fingerprint: "snapshot-business-2",
            stableAccountID: "acct-business-2",
            planType: "team"
        )
        let detectedAccount = makeAccount(
            name: "Business 1",
            email: "business-1@example.com",
            fingerprint: "snapshot-business-1",
            stableAccountID: "acct-business-1",
            planType: "team"
        )
        try harness.repository.saveAccounts([desiredAccount, detectedAccount])
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: desiredAccount.id,
                verifiedAccount: nil,
                detectedAccountID: detectedAccount.id,
                verificationStatus: .failed,
                lastVerificationError: "buildbox is using Business 1, not Business 2."
            )
        ]
        let coordinator = harness.makeCoordinator(
            remoteHostOperations: RemoteHostStub(
                status: CodexAccountStatus(
                    email: "business-1@example.com",
                    planType: "team",
                    usage: nil,
                    stableAccountID: "acct-business-1",
                    snapshotFingerprint: "snapshot-business-1"
                )
            )
        )
        coordinator.start()
        await coordinator.waitForPendingWork()

        let item = NSMenuItem(title: "Use Detected Account", action: nil, keyEquivalent: "")
        item.representedObject = HostAccountMenuItemPayload(
            accountID: detectedAccount.id,
            hostDestination: "user@buildbox"
        )
        coordinator.adoptDetectedRemoteAccount(item)
        await coordinator.waitForPendingWork()

        let refreshedState = try #require(harness.settings.remoteHostSettings.remoteHostState(for: "user@buildbox"))
        #expect(refreshedState.desiredAccountID == detectedAccount.id)
        #expect(refreshedState.detectedAccountID == nil)
        #expect(refreshedState.verificationStatus == .verified)
        #expect(refreshedState.activeAccount?.id == detectedAccount.id)
        #expect(coordinator.menuState().connectedRemoteHosts.first?.activeAccount?.name == "Business 1")
    }

    @Test
    func coordinatorMarksRemoteHostFailedWhenStartupRefreshNoLongerMatchesDesiredAccount() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let persistedAccount = makeAccount(name: "Business 2", email: "business-2@example.com", planType: "team")
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                activeAccount: persistedAccount
            )
        ]
        let coordinator = harness.makeCoordinator(
            remoteHostOperations: RemoteHostStub(
                status: CodexAccountStatus(email: "different@example.com", planType: "team", usage: nil)
            )
        )

        coordinator.start()
        await coordinator.waitForPendingWork()

        let refreshedState = try #require(harness.settings.remoteHostSettings.remoteHostState(for: "user@buildbox"))
        #expect(refreshedState.desiredAccountID == persistedAccount.id)
        #expect(refreshedState.activeAccount == nil)
        #expect(refreshedState.verificationStatus == .failed)
        #expect(refreshedState.lastVerificationError?.contains("could not verify") == true)
        #expect(coordinator.menuState().connectedRemoteHosts.isEmpty)
    }

    @Test
    func coordinatorKeepsReachableRemoteHostConnectedWhenAuthVerificationReadFails() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let account = makeAccount(name: "Business 2", email: "business-2@example.com", planType: "team")
        try harness.repository.saveAccounts([account])
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: account.id,
                verifiedAccount: nil,
                verificationStatus: .unverified
            )
        ]
        let coordinator = harness.makeCoordinator(
            remoteHostOperations: RemoteHostStub(
                readError: RemoteHostClientError.authReadFailed("cat: .codex/auth.json: Permission denied")
            )
        )

        coordinator.start()
        await coordinator.waitForPendingWork()

        let remoteHost = try #require(coordinator.menuState().connectedRemoteHosts.first)
        #expect(remoteHost.connectionState == .connected)
        #expect(remoteHost.verificationStatus == .failed)
        #expect(remoteHost.lastVerificationError == "cat: .codex/auth.json: Permission denied")
        #expect(harness.alertPresenter.infoRequests.isEmpty)
    }

    @Test
    func switchAccountOnHostKeepsReachableRemoteHostConnectedWhenAuthVerificationReadFails() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let account = makeAccount(name: "Business 2", email: "business-2@example.com", planType: "team")
        try harness.repository.saveAccounts([account])
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: nil,
                verifiedAccount: nil,
                verificationStatus: .unverified
            )
        ]
        let remoteHostClient = RemoteHostStub(
            readError: RemoteHostClientError.authReadFailed("cat: .codex/auth.json: Permission denied")
        )
        let coordinator = harness.makeCoordinator(
            accountsRemoteHostClient: remoteHostClient,
            remoteHostOperations: remoteHostClient
        )
        coordinator.start()
        await coordinator.waitForPendingWork()

        coordinator.switchAccountOnHost(harness.menuItem(representing: HostAccountMenuItemPayload(
            accountID: account.id,
            hostDestination: "user@buildbox"
        )))
        await coordinator.waitForPendingWork()

        let persistedState = try #require(harness.settings.remoteHostSettings.remoteHostState(for: "user@buildbox"))
        #expect(persistedState.desiredAccountID == account.id)
        #expect(persistedState.activeAccount == nil)
        #expect(persistedState.verificationStatus == .failed)
        #expect(persistedState.lastVerificationError == "cat: .codex/auth.json: Permission denied")
        let remoteHost = try #require(coordinator.menuState().connectedRemoteHosts.first)
        #expect(remoteHost.connectionState == .connected)
        #expect(remoteHost.verificationStatus == .failed)
        #expect(remoteHost.lastVerificationError == "cat: .codex/auth.json: Permission denied")
    }

    @Test
    func switchAccountOnHostPersistsPreviousVerifiedRemoteLimitsBackIntoCatalog() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let now = Date()
        let previousSaved = makeAccount(
            name: "Business 4",
            email: "business-4@example.com",
            fingerprint: "business-4",
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 0,
                sessionResetsAt: now.addingTimeInterval(2 * 60 * 60),
                weeklyUsedPercent: 0,
                weeklyResetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                fetchedAt: now
            )
        )
        var previousVerified = previousSaved
        previousVerified.applyRemoteMetadata(
            email: previousSaved.email,
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(3 * 60 * 60),
                weeklyUsedPercent: 16,
                weeklyResetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                fetchedAt: now
            )
        )
        let nextAccount = makeAccount(
            name: "Business 5",
            email: "business-5@example.com",
            fingerprint: "business-5",
            planType: "team"
        )
        try harness.repository.saveAccounts([previousSaved, nextAccount])
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: previousSaved.id,
                verifiedAccount: previousVerified,
                verificationStatus: .verified
            )
        ]
        let remoteHostClient = RemoteHostStub(
            status: CodexAccountStatus(
                email: nextAccount.email,
                planType: "team",
                usage: makeUsage(
                    planType: "team",
                    sessionUsedPercent: 92,
                    sessionResetsAt: now.addingTimeInterval(4 * 60 * 60),
                    weeklyUsedPercent: 14,
                    weeklyResetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    fetchedAt: now
                )
            )
        )
        let coordinator = harness.makeCoordinator(
            accountsRemoteHostClient: remoteHostClient,
            remoteHostOperations: remoteHostClient
        )
        coordinator.start()
        await coordinator.waitForPendingWork()

        coordinator.switchAccountOnHost(harness.menuItem(representing: HostAccountMenuItemPayload(
            accountID: nextAccount.id,
            hostDestination: "user@buildbox"
        )))
        await coordinator.waitForPendingWork()

        let persistedAccounts = try harness.repository.loadAccounts()
        let persistedPrevious = try #require(persistedAccounts.first(where: { $0.id == previousSaved.id }))
        #expect(persistedPrevious.usage?.window(.session)?.displayedUsedPercent(at: now) == 100)
        #expect(persistedPrevious.usage?.window(.weekly)?.displayedUsedPercent(at: now) == 16)
        let hostState = try #require(harness.settings.remoteHostSettings.remoteHostState(for: "user@buildbox"))
        #expect(hostState.verifiedAccount?.id == nextAccount.id)
    }

    @Test
    func switchAccountOnHostRearmsNotificationStateForActivatedRemoteAccount() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let account = makeAccount(
            name: "Business 5",
            email: "business-5@example.com",
            fingerprint: "business-5",
            planType: "team"
        )
        try harness.repository.saveAccounts([account])
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"))
        ]
        harness.settings.notificationPreferences.notificationsWhenBlockedEnabled = true
        harness.settings.notificationState.updateAccountNotificationState(for: account.id) { state in
            state.isArmed = false
            state.lastNotification = PersistedAccountNotificationRecord(
                reason: .whenBlocked,
                window: PersistedAccountNotificationWindow(
                    sessionResetAt: Date().addingTimeInterval(1800),
                    weeklyResetAt: Date().addingTimeInterval(86_400)
                ),
                notifiedAt: .now
            )
        }
        let remoteHostClient = RemoteHostStub(
            status: CodexAccountStatus(email: account.email, planType: account.planType, usage: account.usage)
        )
        let coordinator = harness.makeCoordinator(
            accountsRemoteHostClient: remoteHostClient,
            remoteHostOperations: remoteHostClient
        )
        coordinator.start()
        await coordinator.waitForPendingWork()

        coordinator.switchAccountOnHost(harness.menuItem(representing: HostAccountMenuItemPayload(
            accountID: account.id,
            hostDestination: "user@buildbox"
        )))
        await coordinator.waitForPendingWork()

        let persisted = try #require(harness.settings.notificationState.accountNotificationState(for: account.id))
        #expect(persisted.isArmed)
        #expect(persisted.lastNotification == nil)
    }

    @Test
    func coordinatorPreservesMeaningfulSavedLimitsWhenRemoteRefreshReturnsZeroedWindows() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.settings.remoteHostSettings.configuredRemoteHost = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        harness.settings.remoteHostSettings.remoteHostActiveAccount = makeAccount(
            name: "Business 2",
            email: "remote@example.com",
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 97,
                sessionResetsAt: Date().addingTimeInterval(3600),
                weeklyUsedPercent: 15,
                weeklyResetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60)
            )
        )
        let coordinator = harness.makeCoordinator(
            remoteHostOperations: RemoteHostStub(
                status: CodexAccountStatus(
                    email: "remote@example.com",
                    planType: "team",
                    usage: makeUsage(planType: "team", sessionUsedPercent: 0, weeklyUsedPercent: 0)
                )
            )
        )

        coordinator.start()
        await coordinator.waitForPendingWork()

        let remoteLimits = try #require(coordinator.menuState().activeAccountCards.first?.account.usage)
        #expect(remoteLimits.window(.session)?.displayedUsedPercent() == 97)
        #expect(remoteLimits.window(.weekly)?.displayedUsedPercent() == 15)
    }

    @Test
    func coordinatorUsesMatchingInactiveSavedAccountLimitsWhenRemoteRefreshReturnsZeroedWindows() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let matchingSavedAccount = makeAccount(
            name: "Business 2",
            email: "user@example.com",
            stableAccountID: "acct-team",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-2",
                workspaceLabel: "Personal"
            ),
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 100,
                sessionResetsAt: Date().addingTimeInterval(3600),
                weeklyUsedPercent: 16,
                weeklyResetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60)
            )
        )
        try harness.repository.saveAccounts([matchingSavedAccount])
        var zeroedRemoteAccount = matchingSavedAccount
        zeroedRemoteAccount.usage = makeUsage(planType: "team", sessionUsedPercent: 0, weeklyUsedPercent: 0)
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: matchingSavedAccount.id,
                verifiedAccount: zeroedRemoteAccount
            )
        ]
        let coordinator = harness.makeCoordinator(
            remoteHostOperations: RemoteHostStub(
                status: CodexAccountStatus(
                    email: "user@example.com",
                    planType: "team",
                    usage: makeUsage(planType: "team", sessionUsedPercent: 0, weeklyUsedPercent: 0)
                )
            )
        )

        coordinator.start()
        await coordinator.waitForPendingWork()

        let remoteLimits = try #require(coordinator.menuState().activeAccountCards.first?.account.usage)
        #expect(remoteLimits.window(.session)?.displayedUsedPercent() == 100)
        #expect(remoteLimits.window(.weekly)?.displayedUsedPercent() == 16)
    }

    @Test
    func coordinatorRelinksStaleRemoteHostAccountIDsToCurrentSavedCatalogOnStartup() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let now = Date.now
        let currentSavedAccount = makeAccount(
            name: "Business 2",
            email: "user@example.com",
            stableAccountID: "acct-team",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-2",
                workspaceLabel: "Personal"
            ),
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(21 * 60),
                weeklyUsedPercent: 16,
                weeklyResetsAt: now.addingTimeInterval(5 * 24 * 60 * 60),
                fetchedAt: now
            ),
            updatedAt: now
        )
        try harness.repository.saveAccounts([currentSavedAccount])
        let staleRemoteAccount = makeAccount(
            name: "Business 2",
            email: "user@example.com",
            stableAccountID: "acct-stale-business-2",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|stale-business-2",
                chatGPTUserID: "user-stale-business-2"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-stale-business-2",
                workspaceLabel: "Personal"
            ),
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(-45 * 60),
                weeklyUsedPercent: 16,
                weeklyResetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                fetchedAt: now.addingTimeInterval(-3600)
            ),
            updatedAt: now.addingTimeInterval(-3600)
        )
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "debian-vm", displayName: "debian-vm"),
                desiredAccountID: staleRemoteAccount.id,
                verifiedAccount: staleRemoteAccount,
                verificationStatus: .verified
            )
        ]
        let coordinator = harness.makeCoordinator(
            remoteHostOperations: RemoteHostStub(
                status: CodexAccountStatus(email: "user@example.com", planType: "team", usage: nil)
            )
        )

        coordinator.start()
        await coordinator.waitForPendingWork()

        let refreshedHostState = try #require(harness.settings.remoteHostSettings.remoteHostState(for: "debian-vm"))
        #expect(refreshedHostState.desiredAccountID == currentSavedAccount.id)
        #expect(refreshedHostState.activeAccount?.id == currentSavedAccount.id)
        #expect(refreshedHostState.activeAccount?.usage?.window(.session)?.displayedUsedPercent(at: now) == 100)
        let actualPrimaryReset = try #require(refreshedHostState.activeAccount?.usage?.window(.session)?.resetsAt)
        let expectedPrimaryReset = try #require(currentSavedAccount.usage?.window(.session)?.resetsAt)
        #expect(abs(actualPrimaryReset.timeIntervalSince(expectedPrimaryReset)) < 1)
        let remoteLimits = try #require(coordinator.menuState().activeAccountCards.first?.account.usage)
        #expect(remoteLimits.window(.session)?.displayedUsedPercent() == 100)
        #expect(remoteLimits.window(.weekly)?.displayedUsedPercent() == 16)
    }

    @Test
    func scheduledRefreshUpdatesVerifiedRemoteHostUsage() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let now = Date.now
        let account = makeAccount(
            name: "Business 4",
            email: "team@example.com",
            stableAccountID: "acct-business-4",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-4",
                chatGPTUserID: "user-business-4"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-4",
                workspaceLabel: "Team"
            ),
            planType: "team",
            usage: makeUsage(
                planType: "team",
                sessionUsedPercent: 0,
                sessionResetsAt: now.addingTimeInterval(5 * 60 * 60),
                weeklyUsedPercent: 0,
                weeklyResetsAt: now.addingTimeInterval(7 * 24 * 60 * 60),
                fetchedAt: now
            ),
            updatedAt: now
        )
        try harness.repository.saveAccounts([account])
        harness.settings.remoteHostSettings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
                desiredAccountID: account.id,
                verifiedAccount: account
            )
        ]
        let remoteHostClient = RemoteHostSequenceProbe(statusesByDestination: [
            "user@debian-vm": [
                remoteStatus(for: account, usage: account.usage),
                remoteStatus(
                    for: account,
                    usage: makeUsage(
                        planType: "team",
                        sessionUsedPercent: 39,
                        sessionResetsAt: now.addingTimeInterval(4 * 60 * 60),
                        weeklyUsedPercent: 6,
                        weeklyResetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                        fetchedAt: now.addingTimeInterval(60)
                    )
                )
            ]
        ])
        let coordinator = harness.makeCoordinator(remoteHostOperations: remoteHostClient)
        coordinator.start()
        await coordinator.waitForPendingWork()

        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()

        let remoteLimits = try #require(coordinator.menuState().activeAccountCards.first?.account.usage)
        #expect(remoteLimits.window(.session)?.displayedUsedPercent() == 39)
        #expect(remoteLimits.window(.weekly)?.displayedUsedPercent() == 6)
        #expect(await remoteHostClient.readCount(for: "user@debian-vm") == 2)
    }

    private func remoteStatus(for account: CodexAccount, usage: UsageSnapshot?) -> CodexAccountStatus {
        CodexAccountStatus(
            email: account.email,
            planType: account.planType,
            usage: usage,
            stableAccountID: account.identity.stableAccountID,
            authPrincipalIdentity: account.identity.authPrincipalIdentity,
            workspaceIdentity: account.identity.workspaceIdentity,
            snapshotFingerprint: account.identity.snapshotFingerprint
        )
    }
}

@MainActor
private final class MenuBarCoordinatorHarness {
    let repository: AccountRepository
    let settings: SettingsStores
    let alertPresenter = AlertPresenterProbe()
    let panelPresenter = PanelPresenterProbe()
    let applicationActivator = ApplicationActivatorProbe()
    let notificationSettingsLauncher = NotificationSettingsLauncherProbe()
    private(set) var accountsController: AccountsController!
    private var coordinator: MenuBarCoordinator?
    private let repositoryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MenuBarCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
    private let suiteName = "MenuBarCoordinatorTests-\(UUID().uuidString)"
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init() throws {
        repository = try AccountRepository(isolatedRootDirectory: repositoryDirectory)
        try repository.bootstrapStorage()
        settings = SettingsStores(userDefaults: UserDefaults(suiteName: suiteName)!)
    }

    func makeCoordinator(
        accountsRemoteHostClient: RemoteHostSwitchWorkflowOperations = UnavailableRemoteHostClient(),
        remoteHostOperations: MenuBarRemoteHostOperations = UnavailableRemoteHostClient(),
        notificationDelivery: AccountAvailabilityNotifier = DisabledAccountAvailabilityNotifier()
    ) -> MenuBarCoordinator {
        accountsController = AccountsFeatureFactory(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: CodexAppProcessProbe(),
            accountStatusClient: DisabledAccountStatusClient(),
            remoteHostSwitchOperations: accountsRemoteHostClient,
            postSwitchRefreshDelay: .zero
        ).makeController()
        accountsController.load()
        let coordinator = MenuBarCoordinator.makeForTesting(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            accountsController: accountsController,
            settings: settings,
            remoteHostOperations: remoteHostOperations,
            alertPresenter: alertPresenter,
            panelPresenter: panelPresenter,
            notificationDelivery: notificationDelivery,
            applicationActivator: applicationActivator,
            notificationSettingsLauncher: notificationSettingsLauncher,
            allowsEmptyStatePrompt: false
        )
        self.coordinator = coordinator
        return coordinator
    }

    func makeActiveAccount(named name: String, email: String) throws -> CodexAccount {
        let authData = Data("auth-\(UUID().uuidString)".utf8)
        var account = try CodexAuthSnapshotService(repository: repository).saveAuthSnapshot(authData, named: name)
        account.email = email
        account.planType = "team"
        account.identity.remoteIdentity = CodexRemoteAccountIdentity(emailAddress: email)
        try repository.saveAccounts([account])
        try authData.write(to: repository.paths.codexAuthFile, options: .atomic)
        return account
    }

    func menuItem(representing payload: Any) -> NSMenuItem {
        let item = NSMenuItem()
        item.representedObject = payload
        return item
    }

    func tearDown() {
        coordinator?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: repositoryDirectory)
    }
}

private final class ApplicationActivatorProbe: ApplicationActivator {
    private(set) var activateCallCount = 0

    func activate() {
        activateCallCount += 1
    }
}

private final class NotificationSettingsLauncherProbe: NotificationSettingsLauncher {
    private(set) var openCallCount = 0

    func openNotificationSettings() {
        openCallCount += 1
    }
}

private actor RemoteHostSequenceProbe:
    RemoteHostConnectionChecking,
    RemoteHostAccountStatusReading,
    RemoteHostAccountSigningOut,
    RemoteHostCodexAppServerRefreshing
{
    private var statusesByDestination: [String: [CodexAccountStatus]]
    private var readCounts: [String: Int] = [:]

    init(statusesByDestination: [String: [CodexAccountStatus]]) {
        self.statusesByDestination = statusesByDestination
    }

    func testConnection(to host: RemoteHost) async throws {}
    func signOut(on host: RemoteHost) async throws {}
    func refreshCodexAppServer(on host: RemoteHost) async throws {}

    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        readCounts[host.destination, default: 0] += 1
        guard var statuses = statusesByDestination[host.destination], let first = statuses.first else {
            return CodexAccountStatus(email: nil, planType: nil, usage: nil)
        }
        if statuses.count > 1 {
            statuses.removeFirst()
            statusesByDestination[host.destination] = statuses
        }
        return first
    }

    func readCount(for destination: String) -> Int {
        readCounts[destination, default: 0]
    }
}
