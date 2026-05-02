import AppKit
import Foundation
import Testing
import UserNotifications

@testable import CodexPill

@MainActor
struct MenuBarLiveValidationTests {
    @Test
    func removeAccountSignsOutLocalAndRemoteTargetsBeforeDeletingSavedAccount() async throws {
        let repository = try makeIsolatedRepository()
        let account = try makeActiveAccount(
            named: "Business 4",
            email: "business-4@example.com",
            in: repository
        )
        let host = RemoteHost(destination: "user@debian-vm", displayName: "debian-vm")

        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient(),
            remoteHostSwitchOperations: ValidationRemoteHostClient(
                seedStates: [
                    PersistedRemoteHostState(
                        host: host,
                        installedAccountIDs: [account.id],
                        desiredAccountID: account.id,
                        verifiedAccount: account
                    )
                ]
            )
        )
        store.load()

        let suiteName = "MenuBarLiveValidationRemoveAccount-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: host,
                installedAccountIDs: [account.id],
                desiredAccountID: account.id,
                verifiedAccount: account
            )
        ]
        let alertPresenter = AlertPresenterProbe()
        alertPresenter.confirmationResponse = true
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: ValidationRemoteHostClient(seedStates: settings.remoteHostStates),
            alertPresenter: alertPresenter,
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try await Task.sleep(for: .milliseconds(120))
        let item = NSMenuItem()
        item.representedObject = account.id.uuidString
        coordinator.removeAccount(item)
        try await Task.sleep(for: .milliseconds(180))

        #expect(alertPresenter.confirmationRequests.last?.messageText == "Business 4 is in use")
        #expect(alertPresenter.confirmationRequests.last?.informativeText == "Sign out on This Mac and debian-vm before removing it?")
        #expect(store.accounts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: repository.paths.codexAuthFile.path))
        #expect(settings.remoteHostStates.first?.verifiedAccount == nil)
        #expect(settings.remoteHostStates.first?.desiredAccountID == nil)
    }

    @Test
    func notificationResponseSubstitutesBetterRemoteAccountAndExplainsIt() async throws {
        let repository = try makeIsolatedRepository()
        let now = Date()
        let notifiedAccount = CodexAccount(
            id: UUID(),
            name: "Business 4",
            snapshotFileName: "business-4.json",
            createdAt: now,
            updatedAt: now,
            email: "business-4@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval(60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 20,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ),
            identity: .empty
        )
        let betterAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: "business-2@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 0,
                    resetsAt: now.addingTimeInterval(3 * 60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 20,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ),
            identity: .empty
        )
        try repository.bootstrapStorage()
        try repository.saveAccounts([notifiedAccount, betterAccount])

        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient(),
            remoteHostSwitchOperations: ValidationRemoteHostClient(
                seedStates: [
                    PersistedRemoteHostState(
                        host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
                        installedAccountIDs: [notifiedAccount.id],
                        desiredAccountID: notifiedAccount.id,
                        verifiedAccount: notifiedAccount
                    )
                ]
            )
        )
        store.load()

        let suiteName = "MenuBarLiveValidationNotificationSwitch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.notificationsWhenOutEnabled = true
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
                installedAccountIDs: [notifiedAccount.id],
                desiredAccountID: notifiedAccount.id,
                verifiedAccount: notifiedAccount
            )
        ]
        let alertPresenter = AlertPresenterProbe()
        alertPresenter.confirmationResponse = true
        let foregrounder = ApplicationActivatorProbe()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: ValidationRemoteHostClient(seedStates: settings.remoteHostStates),
            alertPresenter: alertPresenter,
            applicationActivator: foregrounder,
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try await Task.sleep(for: .milliseconds(120))
        await coordinator.handleNotificationResponse(
            actionIdentifier: "use_remote",
            userInfo: [
                "accountID": notifiedAccount.id.uuidString,
                "remoteHostDestination": "user@debian-vm"
            ]
        )
        try await Task.sleep(for: .milliseconds(120))

        #expect(foregrounder.activateCallCount == 1)
        let confirmation = try #require(alertPresenter.confirmationRequests.last)
        #expect(confirmation.informativeText.contains("Business 4 is no longer the best option. Switching to Business 2 instead."))
        #expect(settings.remoteHostState(for: "user@debian-vm")?.verifiedAccount?.id == betterAccount.id)
    }

    @Test
    func notificationResponseFailureOpensAppAndShowsRealError() async throws {
        let repository = try makeIsolatedRepository()
        let now = Date()
        let outAccount = CodexAccount(
            id: UUID(),
            name: "Business 4",
            snapshotFileName: "business-4.json",
            createdAt: now,
            updatedAt: now,
            email: "business-4@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval(60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 20,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ),
            identity: .empty
        )
        let notifiedAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: "business-2@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 0,
                    resetsAt: now.addingTimeInterval(3 * 60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 20,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ),
            identity: .empty
        )
        try repository.bootstrapStorage()
        try repository.saveAccounts([outAccount, notifiedAccount])

        let failingHostClient = RemoteHostStatusProbe(
            status: CodexAccountStatus(
                email: outAccount.email,
                planType: outAccount.planType,
                rateLimits: outAccount.rateLimits
            ),
            switchError: RemoteHostClientError.commandFailed("ssh failure")
        )
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient(),
            remoteHostSwitchOperations: failingHostClient
        )
        store.load()

        let suiteName = "MenuBarLiveValidationNotificationFailure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.notificationsWhenOutEnabled = true
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
                installedAccountIDs: [outAccount.id, notifiedAccount.id],
                desiredAccountID: outAccount.id,
                verifiedAccount: outAccount
            )
        ]
        let alertPresenter = AlertPresenterProbe()
        alertPresenter.confirmationResponse = true
        let foregrounder = ApplicationActivatorProbe()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: failingHostClient,
            alertPresenter: alertPresenter,
            applicationActivator: foregrounder,
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try await Task.sleep(for: .milliseconds(120))
        await coordinator.handleNotificationResponse(
            actionIdentifier: "use_remote",
            userInfo: [
                "accountID": notifiedAccount.id.uuidString,
                "remoteHostDestination": "user@debian-vm"
            ]
        )
        try await Task.sleep(for: .milliseconds(120))

        #expect(foregrounder.activateCallCount == 1)
        let infoRequest = try #require(alertPresenter.infoRequests.last)
        #expect(infoRequest.informativeText == "ssh failure")
    }

    @Test
    func localNotificationResponseShowsOnlyNotificationConfirmation() async throws {
        let repository = try makeIsolatedRepository()
        let now = Date()
        let account = CodexAccount(
            id: UUID(),
            name: "Business 3",
            snapshotFileName: "business-3.json",
            createdAt: now,
            updatedAt: now,
            email: "business-3@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 0,
                    resetsAt: now.addingTimeInterval(3 * 60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 20,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ),
            identity: .empty
        )
        try repository.bootstrapStorage()
        try repository.writeSnapshot(data: Data("{}".utf8), for: account)
        try repository.saveAccounts([account])

        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        store.load()

        let suiteName = "MenuBarLiveValidationLocalNotificationSwitch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.notificationsWhenBlockedEnabled = true
        let alertPresenter = AlertPresenterProbe()
        alertPresenter.confirmationResponse = true
        let foregrounder = ApplicationActivatorProbe()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            alertPresenter: alertPresenter,
            applicationActivator: foregrounder,
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        await coordinator.handleNotificationResponse(
            actionIdentifier: "use_local",
            userInfo: [
                "accountID": account.id.uuidString
            ]
        )
        try await Task.sleep(for: .milliseconds(120))

        #expect(foregrounder.activateCallCount == 1)
        #expect(alertPresenter.confirmationRequests.count == 1)
        #expect(alertPresenter.confirmationRequests.last?.messageText == "Use Business 3 now?")
    }

    @Test
    func snapshotShowsRemoteAccountsSectionForDesiredUnverifiedRemoteState() throws {
        let localAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-2@example.com",
            planType: "team",
            rateLimits: nil,
            identity: .empty
        )
        let state = MenuBarMenuState(
            activeAccount: nil,
            inactiveAccounts: [localAccount],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "buildbox",
                    destination: "user@buildbox",
                    connectionState: .syncing,
                    desiredAccount: localAccount,
                    activeAccount: nil,
                    verificationStatus: .verifying,
                    deployedAccountIDs: [localAccount.id]
                )
            ],
            visibleInactiveAccountCount: 2,
            visibleInactiveAccountCountOptions: [2, 3, 5, 0],
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [1, 5, 10],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .dualArcBadge,
            statusBarDisplayMode: .iconOnly,
            isBusy: false,
            statusMessage: ""
        )

        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state)

        #expect(snapshot.sections.contains(where: { $0.title == "Remote Accounts" }) == false)
        #expect(snapshot.remoteHosts.count == 1)
        #expect(snapshot.remoteHosts.first?.desiredAccount?.name == "Business 2")
        #expect(snapshot.remoteHosts.first?.activeAccount == nil)
        #expect(snapshot.remoteHosts.first?.verificationStatus == "verifying")
    }

    @Test
    func fileSinkWritesSnapshotJSON() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outputURL = temporaryDirectory.appendingPathComponent("live-menu-snapshot.json")
        let eventsOutputURL = temporaryDirectory.appendingPathComponent("validation-events.jsonl")
        let snapshot = MenuBarValidationSnapshot(
            sections: [
                .init(title: "Active Account", items: ["Primary • Pro • primary@example.com"])
            ],
            statusMessage: "Refreshing account data...",
            currentAccount: .init(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                identityDigest: "digest-primary"
            ),
            remoteHosts: [],
            hasStatusItemContentData: true,
            effectiveStatusBarDisplayMode: "iconAndText",
            statusItem: nil,
            actionTrace: nil,
            menuItems: [
                .init(
                    title: "Preferences",
                    isEnabled: true,
                    state: "off",
                    hasAction: false,
                    actionSelector: nil,
                    isSeparator: false,
                    viewFrameWidth: nil,
                    children: []
                )
            ]
        )

        try FileMenuBarValidationSink(outputURL: outputURL, eventsOutputURL: eventsOutputURL).record(snapshot)

        let data = try Data(contentsOf: outputURL)
        let decoded = try JSONDecoder().decode(MenuBarValidationSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }

    @Test
    func fileSinkAppendsValidationEventsJSONL() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outputURL = temporaryDirectory.appendingPathComponent("live-menu-snapshot.json")
        let eventsOutputURL = temporaryDirectory.appendingPathComponent("validation-events.jsonl")
        let sink = FileMenuBarValidationSink(outputURL: outputURL, eventsOutputURL: eventsOutputURL)
        let firstEvent = MenuBarValidationEvent(
            timestamp: Date(timeIntervalSince1970: 1_744_200_000),
            scenario: "live-status-item-hover",
            proofLayer: "live_ui",
            invariantIds: ["menubar.text_on_hover.stays_visible_inside_resized_bounds"],
            event: "status_item_hover_entered",
            step: "hover_enter",
            payload: ["displayedTitle": "S 42% W 68%"]
        )
        let secondEvent = MenuBarValidationEvent(
            timestamp: Date(timeIntervalSince1970: 1_744_200_001),
            scenario: "live-status-item-hover",
            proofLayer: "live_ui",
            invariantIds: ["menubar.text_on_hover.stays_visible_inside_resized_bounds"],
            event: "status_item_title_hidden",
            step: "hover_title_hidden"
        )

        try sink.record(firstEvent)
        try sink.record(secondEvent)

        let lines = try String(contentsOf: eventsOutputURL)
            .split(separator: "\n")
            .map(String.init)
        let decoded = try lines.map { line in
            try JSONDecoder().decode(MenuBarValidationEvent.self, from: Data(line.utf8))
        }

        #expect(decoded == [firstEvent, secondEvent])
    }

    @Test
    func validationPayloadSanitizerRedactsSecretsAndUserPaths() {
        let payload = sanitizedValidationPayload([
            "error": "Authorization: Bearer sk-secret failed for /Users/raphh/.codex/auth.json",
            "query": "access_token=abc123&refresh_token=def456",
            "safe": "failed to fetch codex rate limits"
        ])

        #expect(payload["error"] == "Authorization: Bearer <redacted> failed for /Users/<redacted>/.codex/auth.json")
        #expect(payload["query"] == "access_token=<redacted>&refresh_token=<redacted>")
        #expect(payload["safe"] == "failed to fetch codex rate limits")
    }

    @Test
    func configurationReturnsSinkOnlyWhenOutputPathIsPresent() {
        #expect(MenuBarValidationConfiguration.makeSink(environment: [:]) == nil)
        #expect(
            MenuBarValidationConfiguration.makeSink(
                environment: [
                    MenuBarValidationConfiguration.outputPathEnvironmentKey: "/tmp/codexpill-live-menu.json",
                    MenuBarValidationConfiguration.eventsOutputPathEnvironmentKey: "/tmp/validation-events.jsonl"
                ]
            ) is FileMenuBarValidationSink
        )
        #expect(MenuBarValidationConfiguration.scenario(environment: [:]) == nil)
        #expect(
            MenuBarValidationConfiguration.scenario(
                environment: [MenuBarValidationConfiguration.scenarioEnvironmentKey: "live-status-item-hover"]
            ) == "live-status-item-hover"
        )
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
    func enableNotificationsRequestsAuthorizationAndTurnsOnDefaultModesWhenUndetermined() async throws {
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationEnableNotifications-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        let center = UserNotificationCenterProbe()
        center.authorizationStatus = .notDetermined
        let opener = NotificationSettingsLauncherProbe()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            alertPresenter: AlertPresenterProbe(),
            notificationDelivery: AccountAvailabilityNotificationCenter(center: center),
            notificationSettingsLauncher: opener,
            allowsEmptyStatePrompt: false
        )

        coordinator.enableNotifications(NSMenuItem())
        try await Task.sleep(for: .milliseconds(50))

        #expect(settings.notificationsWhenBlockedEnabled)
        #expect(settings.notificationsWhenOutEnabled)
        #expect(center.requestAuthorizationCallCount == 1)
        #expect(opener.openCallCount == 0)
    }

    @Test
    func enableNotificationsOpensSystemSettingsWhenAuthorizationWasDenied() async throws {
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationDeniedNotifications-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.notificationsWhenBlockedEnabled = true
        let center = UserNotificationCenterProbe()
        center.authorizationStatus = .denied
        let opener = NotificationSettingsLauncherProbe()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            alertPresenter: AlertPresenterProbe(),
            notificationDelivery: AccountAvailabilityNotificationCenter(center: center),
            notificationSettingsLauncher: opener,
            allowsEmptyStatePrompt: false
        )

        coordinator.enableNotifications(NSMenuItem())
        try await Task.sleep(for: .milliseconds(50))

        #expect(settings.notificationsWhenBlockedEnabled)
        #expect(!settings.notificationsWhenOutEnabled)
        #expect(center.requestAuthorizationCallCount == 0)
        #expect(opener.openCallCount == 1)
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
                    rateLimits: nil,
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
                    rateLimits: nil,
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

    @Test
    func enablingFirstNotificationToggleRequestsPermission() async throws {
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationNotificationPermission-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        let center = UserNotificationCenterProbe()
        let delivery = AccountAvailabilityNotificationCenter(center: center)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            alertPresenter: AlertPresenterProbe(),
            notificationDelivery: delivery,
            allowsEmptyStatePrompt: false
        )

        coordinator.toggleNotificationsWhenBlocked(NSMenuItem())
        try await Task.sleep(for: .milliseconds(25))
        coordinator.toggleNotificationsWhenOut(NSMenuItem())
        try await Task.sleep(for: .milliseconds(25))

        #expect(center.requestAuthorizationCallCount == 1)
        #expect(settings.notificationsWhenBlockedEnabled)
        #expect(settings.notificationsWhenOutEnabled)
    }

    @Test
    func addHostCancellationAfterValidationDoesNotPersistPendingHost() async throws {
        let repository = try makeIsolatedRepository()
        let activeAccount = try makeActiveAccount(named: "Business 1", email: "business-1@example.com", in: repository)
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient(),
            remoteHostSwitchOperations: RemoteHostStatusProbe(
                status: CodexAccountStatus(email: activeAccount.email, planType: activeAccount.planType, rateLimits: nil)
            )
        )
        store.load()

        let suiteName = "MenuBarLiveValidationAddHostCancel-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        let alertPresenter = AlertPresenterProbe()
        let panelPresenter = PanelPresenterProbe()
        panelPresenter.hostSetupResponse = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        alertPresenter.confirmationResponse = false
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(),
            alertPresenter: alertPresenter,
            panelPresenter: panelPresenter,
            allowsEmptyStatePrompt: false
        )

        coordinator.addHost(NSMenuItem())
        try await Task.sleep(for: .milliseconds(80))

        #expect(alertPresenter.confirmationRequests.count == 1)
        #expect(settings.remoteHostStates.isEmpty)
    }

    @Test
    func addHostPersistsVerifiedHostOnlyAfterInstallConfirmation() async throws {
        let repository = try makeIsolatedRepository()
        let activeAccount = try makeActiveAccount(named: "Business 1", email: "business-1@example.com", in: repository)
        let remoteHostClient = RemoteHostStatusProbe(
            status: CodexAccountStatus(email: activeAccount.email, planType: activeAccount.planType, rateLimits: nil)
        )
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient(),
            remoteHostSwitchOperations: remoteHostClient
        )
        store.load()

        let suiteName = "MenuBarLiveValidationAddHostConfirmed-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        let alertPresenter = AlertPresenterProbe()
        let panelPresenter = PanelPresenterProbe()
        panelPresenter.hostSetupResponse = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        alertPresenter.confirmationResponse = true
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: remoteHostClient,
            alertPresenter: alertPresenter,
            panelPresenter: panelPresenter,
            allowsEmptyStatePrompt: false
        )

        coordinator.addHost(NSMenuItem())
        try await Task.sleep(for: .milliseconds(120))

        let hostState = try #require(settings.remoteHostState(for: "user@buildbox"))
        #expect(hostState.desiredAccountID == activeAccount.id)
        #expect(hostState.verifiedAccount?.id == activeAccount.id)
        #expect(hostState.verificationStatus == .verified)
        #expect(hostState.installedAccountIDs.contains(activeAccount.id))
    }

    @Test
    func coordinatorRefreshesLiveSnapshotWhenStatusItemRuntimeStateChanges() throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.statusBarDisplayMode = .textOnHover
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let runtime = StatusItemRuntime(
            statusItem: statusItem,
            hoverActivationDelay: 0,
            hoverExitDelay: 0,
            hoverPollingInterval: 60
        )
        let coordinator = MenuBarCoordinator(
            statusItemRuntime: runtime,
            store: store,
            settings: settings,
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-status-item-hover",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        let initialSnapshotCount = sink.snapshots.count

        runtime.handleHoverChanged(true)

        #expect(sink.events.contains(where: { $0.event == "status_item_hover_entered" }))
        #expect(sink.snapshots.count > initialSnapshotCount)
        #expect(sink.snapshots.last?.statusItem?.isHovered == true)
    }

    @Test
    func sealValidationRunEmitsAddAccountNameDialogProof() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealValidation-\(UUID().uuidString)", isDirectory: true)
        let now = Date()
        let account = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "personal.json",
            createdAt: now,
            updatedAt: now,
            email: "personal@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: .empty
        )
        let run = try #require(CodexPillSealValidationConfiguration.makeRun(environment: [
            CodexPillSealValidationConfiguration.proofOutputPathEnvironmentKey: proofDirectory.path,
            MenuBarValidationConfiguration.scenarioEnvironmentKey: "live-add-account-name-dialog-cancelled",
        ]))

        run.recordAddAccountMenuAction(activeAccount: account, savedAccounts: [account])
        run.recordAddAccountNameDialogPresented(runningCLISessions: 1)
        run.recordAddAccountNameDialogCancelled(activeAccount: account, savedAccounts: [account])

        let manifestURL = proofDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let runMetadata = manifest?["run"] as? [String: Any]
        let evidence = manifest?["evidence"] as? [[String: Any]]

        #expect(runMetadata?["feature"] as? String == "accounts")
        #expect(runMetadata?["scenario"] as? String == "add-account-name-dialog-cancelled")
        #expect(evidence?.compactMap { $0["path"] as? String } == [
            "evidence/events.jsonl",
            "evidence/account-before.json",
            "evidence/name-dialog-snapshot.json",
            "evidence/account-after.json",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))
    }

    @Test
    func sealValidationRunEmitsAccountSwitchProof() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealValidation-\(UUID().uuidString)", isDirectory: true)
        let now = Date()
        let personal = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "personal.json",
            createdAt: now,
            updatedAt: now,
            email: "personal@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: .empty
        )
        let business = CodexAccount(
            id: UUID(),
            name: "Business",
            snapshotFileName: "business.json",
            createdAt: now,
            updatedAt: now,
            email: "business@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: .empty
        )
        let run = try #require(CodexPillSealValidationConfiguration.makeRun(environment: [
            CodexPillSealValidationConfiguration.proofOutputPathEnvironmentKey: proofDirectory.path,
            MenuBarValidationConfiguration.scenarioEnvironmentKey: "live-account-switch",
        ]))

        run.recordSwitchAccountMenuAction(targetAccount: business, activeAccount: personal, savedAccounts: [personal, business])
        run.recordSwitchConfirmationPresented(targetAccount: business)
        run.recordSwitchConfirmationAccepted(targetAccount: business)
        run.recordSwitchWorkflowStarted(targetAccount: business)
        run.recordActiveAccountChanged(fromName: personal.name, toName: business.name, activeAccount: business, savedAccounts: [personal, business])

        let manifestURL = proofDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let runMetadata = manifest?["run"] as? [String: Any]
        let evidence = manifest?["evidence"] as? [[String: Any]]

        #expect(runMetadata?["feature"] as? String == "accounts")
        #expect(runMetadata?["scenario"] as? String == "switch-account-changes-active-account")
        #expect(evidence?.compactMap { $0["path"] as? String } == [
            "evidence/events.jsonl",
            "evidence/account-before.json",
            "evidence/account-after.json",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))
        let expectations = manifest?["targetedExpectations"] as? [[String: Any]]
        let invariants = expectations?.first?["invariants"] as? [[String: Any]]
        let rule = invariants?.first?["rule"] as? [String: Any]
        let rules = rule?["rules"] as? [[String: Any]]
        let eventSequence = rules?.first { $0["type"] as? String == "event_sequence" }
        let snapshotDiff = rules?.first { $0["type"] as? String == "snapshots_differ" }

        #expect(rule?["type"] as? String == "all")
        #expect((eventSequence?["events"] as? [[String: Any]])?.compactMap { $0["name"] as? String } == [
            "menu_action_dispatched",
            "switch_confirmation_presented",
            "switch_confirmation_accepted",
            "switch_workflow_started",
            "active_account_changed",
        ])
        #expect(snapshotDiff?["before"] as? String == "account_before")
        #expect(snapshotDiff?["after"] as? String == "account_after")
        #expect(snapshotDiff?["paths"] as? [String] == ["activeAccountId"])
    }

    @Test
    func sealValidationRunEmitsAddHostDestinationValidationProof() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealValidation-\(UUID().uuidString)", isDirectory: true)
        let run = try #require(CodexPillSealValidationConfiguration.makeRun(environment: [
            CodexPillSealValidationConfiguration.proofOutputPathEnvironmentKey: proofDirectory.path,
            MenuBarValidationConfiguration.scenarioEnvironmentKey: "live-add-host-destination-validation-failed",
        ]))

        run.recordAddHostMenuAction()
        run.recordAddHostSetupPresented()
        run.recordAddHostValidationStarted(hostName: "codexpill-validation.invalid")
        run.recordAddHostValidationFailed(hostName: "codexpill-validation.invalid", message: "Host unavailable")

        let manifestURL = proofDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let runMetadata = manifest?["run"] as? [String: Any]
        let evidence = manifest?["evidence"] as? [[String: Any]]

        #expect(runMetadata?["feature"] as? String == "hosts")
        #expect(runMetadata?["scenario"] as? String == "add-host-destination-validation-failed")
        #expect(evidence?.compactMap { $0["path"] as? String } == [
            "evidence/events.jsonl",
            "evidence/host-validation-snapshot.json",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/host-validation-snapshot.json").path))
        let expectations = manifest?["targetedExpectations"] as? [[String: Any]]
        let invariants = expectations?.first?["invariants"] as? [[String: Any]]
        let invariant = invariants?.first
        let rule = invariant?["rule"] as? [String: Any]
        let rules = rule?["rules"] as? [[String: Any]]
        let eventSequence = rules?.first { $0["type"] as? String == "event_sequence" }
        let snapshotEquals = rules?.first { $0["type"] as? String == "snapshot_equals" }

        #expect(invariant?["requiredEvidence"] as? [String] == [
            "events",
            "host_validation_snapshot",
        ])
        #expect(rule?["type"] as? String == "all")
        #expect((eventSequence?["events"] as? [[String: Any]])?.compactMap { $0["name"] as? String } == [
            "menu_action_dispatched",
            "add_host_setup_presented",
            "add_host_validation_started",
            "add_host_validation_failed",
        ])
        #expect(snapshotEquals?["evidence"] as? String == "host_validation_snapshot")
        #expect(snapshotEquals?["path"] as? String == "validationResult")
        #expect(snapshotEquals?["value"] as? String == "failed")
    }

    @Test
    func sealValidationRunEmitsRemoteHostSwitchProof() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealValidation-\(UUID().uuidString)", isDirectory: true)
        let run = try #require(CodexPillSealValidationConfiguration.makeRun(environment: [
            CodexPillSealValidationConfiguration.proofOutputPathEnvironmentKey: proofDirectory.path,
            MenuBarValidationConfiguration.scenarioEnvironmentKey: "live-remote-host-switch",
        ]))

        run.recordRemoteHostSwitchMenuAction(targetName: "Validation Local", hostName: "buildbox")
        run.recordRemoteHostSwitchStarted(targetName: "Validation Local", hostName: "buildbox")
        run.recordRemoteHostActiveAccountChanged(targetName: "Validation Local", hostName: "buildbox")

        let manifestURL = proofDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let runMetadata = manifest?["run"] as? [String: Any]
        let evidence = manifest?["evidence"] as? [[String: Any]]

        #expect(runMetadata?["feature"] as? String == "hosts")
        #expect(runMetadata?["scenario"] as? String == "switch-account-on-host-changes-remote-active-account")
        #expect(evidence?.compactMap { $0["path"] as? String } == [
            "evidence/events.jsonl",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))
        let expectations = manifest?["targetedExpectations"] as? [[String: Any]]
        let invariants = expectations?.first?["invariants"] as? [[String: Any]]
        let rule = invariants?.first?["rule"] as? [String: Any]
        let ruleEvents = rule?["events"] as? [[String: Any]]
        #expect(ruleEvents?.allSatisfy { event in
            let payload = event["payload"] as? [String: Any]
            return payload?["hostName"] as? String == "buildbox"
                && payload?["targetName"] == nil
        } == true)

        let eventsURL = proofDirectory.appendingPathComponent("evidence/events.jsonl")
        let events = try String(contentsOf: eventsURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(events.compactMap { $0["event"] as? String } == [
            "menu_action_dispatched",
            "remote_host_switch_started",
            "remote_host_active_account_changed",
        ])
        #expect(events.allSatisfy { event in
            let payload = event["payload"] as? [String: Any]
            return payload?["targetName"] as? String == "Validation Local"
                && payload?["hostName"] as? String == "buildbox"
        })
    }

    @Test
    func sealValidationRunEmitsScheduledRefreshProof() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealValidation-\(UUID().uuidString)", isDirectory: true)
        let now = Date()
        let account = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "personal.json",
            createdAt: now,
            updatedAt: now,
            email: "personal@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: .empty
        )
        let run = try #require(CodexPillSealValidationConfiguration.makeRun(environment: [
            CodexPillSealValidationConfiguration.proofOutputPathEnvironmentKey: proofDirectory.path,
            MenuBarValidationConfiguration.scenarioEnvironmentKey: "live-scheduled-refresh",
        ]))

        run.recordScheduledRefreshRequested(
            accountName: account.name,
            activeAccount: account,
            savedAccounts: [account]
        )
        run.recordScheduledRefreshResult(
            accountName: account.name,
            error: nil,
            activeAccount: account,
            savedAccounts: [account],
            menuSnapshot: MenuBarValidationSupport.makeSnapshot(
                state: makeMenuState(activeAccount: account),
                actionTrace: .init(
                    lastMenuAction: nil,
                    lastSwitchTargetName: nil,
                    lastConfirmationRequest: nil,
                    lastConfirmationAccepted: nil
                )
            )
        )

        let manifestURL = proofDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let runMetadata = manifest?["run"] as? [String: Any]
        let evidence = manifest?["evidence"] as? [[String: Any]]

        #expect(runMetadata?["feature"] as? String == "accounts")
        #expect(runMetadata?["scenario"] as? String == "scheduled-refresh-preserves-account-catalog")
        #expect(evidence?.compactMap { $0["path"] as? String } == [
            "evidence/events.jsonl",
            "evidence/account-before.json",
            "evidence/account-after.json",
            "evidence/ui-after-refresh.json",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/account-before.json").path))
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/account-after.json").path))
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/ui-after-refresh.json").path))

        let expectations = manifest?["targetedExpectations"] as? [[String: Any]]
        let invariants = expectations?.first?["invariants"] as? [[String: Any]]
        #expect(invariants?.compactMap { $0["id"] as? String } == [
            "accounts.scheduled_refresh.requested_and_completed",
            "accounts.scheduled_refresh.preserves_account_catalog_identity",
            "accounts.scheduled_refresh.no_blocking_alert_visible",
        ])

        let eventsURL = proofDirectory.appendingPathComponent("evidence/events.jsonl")
        let events = try String(contentsOf: eventsURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(events.compactMap { $0["event"] as? String } == [
            "scheduled_refresh_requested",
            "scheduled_refresh_completed",
        ])

        let uiAfterRefreshURL = proofDirectory.appendingPathComponent("evidence/ui-after-refresh.json")
        let uiAfterRefresh = try JSONSerialization.jsonObject(with: Data(contentsOf: uiAfterRefreshURL)) as? [String: Any]
        #expect(uiAfterRefresh?["hasBlockingAlert"] as? Bool == false)
        #expect(uiAfterRefresh?["lastConfirmationRequest"] == nil || uiAfterRefresh?["lastConfirmationRequest"] is NSNull)

        let accountBeforeURL = proofDirectory.appendingPathComponent("evidence/account-before.json")
        let accountBefore = try JSONSerialization.jsonObject(with: Data(contentsOf: accountBeforeURL)) as? [String: Any]
        #expect(accountBefore?["activeAccountId"] as? String == account.id.uuidString)
        #expect(accountBefore?["savedAccountIds"] as? [String] == [account.id.uuidString])
        #expect(accountBefore?["savedAccountNames"] as? [String] == [account.name])
        #expect(accountBefore?["savedAccountCount"] as? Int == 1)

        let noBlockingAlertRule = invariants?
            .first { $0["id"] as? String == "accounts.scheduled_refresh.no_blocking_alert_visible" }?["rule"] as? [String: Any]
        let childRules = noBlockingAlertRule?["rules"] as? [[String: Any]]
        #expect(noBlockingAlertRule?["type"] as? String == "all")
        #expect(childRules?.contains { rule in
            rule["type"] as? String == "snapshot_equals"
                && rule["evidence"] as? String == "ui_after_refresh"
                && rule["path"] as? String == "hasBlockingAlert"
                && rule["value"] as? Bool == false
        } == true)
    }

    @Test
    func sealValidationRunDoesNotFinishPassingScheduledRefreshProofOnFailure() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealValidation-\(UUID().uuidString)", isDirectory: true)
        let now = Date()
        let account = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "personal.json",
            createdAt: now,
            updatedAt: now,
            email: "personal@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: .empty
        )
        let run = try #require(CodexPillSealValidationConfiguration.makeRun(environment: [
            CodexPillSealValidationConfiguration.proofOutputPathEnvironmentKey: proofDirectory.path,
            MenuBarValidationConfiguration.scenarioEnvironmentKey: "live-scheduled-refresh",
        ]))

        run.recordScheduledRefreshRequested(
            accountName: account.name,
            activeAccount: account,
            savedAccounts: [account]
        )
        run.recordScheduledRefreshResult(
            accountName: account.name,
            error: "Refresh failed",
            activeAccount: account,
            savedAccounts: [account],
            menuSnapshot: MenuBarValidationSupport.makeSnapshot(state: makeMenuState(activeAccount: account))
        )

        #expect(!FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("manifest.json").path))
        let eventsURL = proofDirectory.appendingPathComponent("evidence/events.jsonl")
        let events = try String(contentsOf: eventsURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(events.compactMap { $0["event"] as? String } == [
            "scheduled_refresh_requested",
            "scheduled_refresh_failed",
        ])
    }

    private func makeMenuState(activeAccount: CodexAccount? = nil) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: [],
            visibleInactiveAccountCount: 3,
            visibleInactiveAccountCountOptions: [1, 3, 5],
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [5, 15, 30],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .dualArcBadge,
            statusBarDisplayMode: .iconAndText,
            isBusy: false,
            statusMessage: ""
        )
    }

    @Test
    func coordinatorRestoresPersistedRemoteHostAccountOnStart() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationRemoteRestore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.configuredRemoteHost = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        settings.remoteHostActiveAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "remote@example.com",
            planType: "team",
            rateLimits: nil,
            identity: .empty
        )
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(
                status: CodexAccountStatus(
                    email: "remote@example.com",
                    planType: "team",
                    rateLimits: CodexRateLimitSnapshot(
                        limitID: nil,
                        limitName: nil,
                        planType: "team",
                        primary: CodexRateLimitWindow(
                            usedPercent: 69,
                            resetsAt: Date(timeIntervalSince1970: 2_000_000_000),
                            windowDurationMinutes: 300
                        ),
                        secondary: nil,
                        fetchedAt: .now
                    )
                )
            ),
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(sink.snapshots.contains(where: { $0.sections.contains(where: { $0.title == "Active Account" }) }))
        #expect(sink.snapshots.last?.remoteHosts.first?.activeAccount?.email == "remote@example.com")
    }

    @Test
    func coordinatorMarksPersistedRemoteHostDisconnectedWhenRefreshFails() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationRemoteFailure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        let persistedAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "fallback@example.com",
            planType: "team",
            rateLimits: nil,
            identity: .empty
        )
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                activeAccount: persistedAccount
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(
                readError: RemoteHostClientError.commandFailed("ssh: connection refused")
            ),
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        let persistedHostState = try #require(settings.remoteHostState(for: "user@buildbox"))
        #expect(persistedHostState.desiredAccountID == persistedAccount.id)
        #expect(persistedHostState.activeAccount == nil)
        #expect(persistedHostState.verificationStatus == .failed)
        #expect(sink.snapshots.last?.sections.contains(where: { $0.title == "Remote Accounts" }) == false)
        #expect(sink.snapshots.last?.remoteHosts.isEmpty == true)
    }

    @Test
    func coordinatorMarksPersistedRemoteHostFailedWhenDesiredAccountIsMissingLocally() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationMissingDesiredRemote-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: UUID(),
                verifiedAccount: nil,
                verificationStatus: .unverified
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(),
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        let refreshedState = try #require(settings.remoteHostState(for: "user@buildbox"))
        #expect(refreshedState.verificationStatus == .failed)
        #expect(refreshedState.lastVerificationError == "Saved account for buildbox is no longer available on this Mac.")
        #expect(sink.snapshots.last?.remoteHosts.isEmpty == true)
    }

    @Test
    func coordinatorRestoresAllPersistedRemoteHostAccountsOnStart() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationMultipleRemoteRestore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                activeAccount: CodexAccount(
                    id: UUID(),
                    name: "Business 2",
                    snapshotFileName: "business-2.json",
                    createdAt: .distantPast,
                    updatedAt: .distantPast,
                    email: "buildbox@example.com",
                    planType: "team",
                    rateLimits: nil,
                    identity: .empty
                )
            ),
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
                activeAccount: CodexAccount(
                    id: UUID(),
                    name: "Business 3",
                    snapshotFileName: "business-3.json",
                    createdAt: .distantPast,
                    updatedAt: .distantPast,
                    email: "debian@example.com",
                    planType: "team",
                    rateLimits: nil,
                    identity: .empty
                )
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(
                statusesByDestination: [
                    "user@buildbox": CodexAccountStatus(email: "buildbox@example.com", planType: "team", rateLimits: nil),
                    "user@debian-vm": CodexAccountStatus(email: "debian@example.com", planType: "team", rateLimits: nil)
                ]
            ),
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        let remoteHosts = try #require(sink.snapshots.last?.remoteHosts)
        #expect(remoteHosts.count == 2)
        #expect(remoteHosts.contains(where: { $0.name == "buildbox" && $0.activeAccount?.email == "buildbox@example.com" }))
        #expect(remoteHosts.contains(where: { $0.name == "debian-vm" && $0.activeAccount?.email == "debian@example.com" }))
    }

    @Test
    func coordinatorShowsOnlyReachableRemoteHostsInPrimarySectionWhenRestoreIsMixed() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationMixedRemoteRestore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                activeAccount: CodexAccount(
                    id: UUID(),
                    name: "Business 2",
                    snapshotFileName: "business-2.json",
                    createdAt: .distantPast,
                    updatedAt: .distantPast,
                    email: "buildbox@example.com",
                    planType: "team",
                    rateLimits: nil,
                    identity: .empty
                )
            ),
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
                activeAccount: CodexAccount(
                    id: UUID(),
                    name: "Business 3",
                    snapshotFileName: "business-3.json",
                    createdAt: .distantPast,
                    updatedAt: .distantPast,
                    email: "debian@example.com",
                    planType: "team",
                    rateLimits: nil,
                    identity: .empty
                )
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(
                statusesByDestination: [
                    "user@buildbox": CodexAccountStatus(email: "buildbox@example.com", planType: "team", rateLimits: nil)
                ],
                readErrorsByDestination: [
                    "user@debian-vm": RemoteHostClientError.commandFailed("ssh: connection refused")
                ]
            ),
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        let remoteHosts = try #require(sink.snapshots.last?.remoteHosts)
        #expect(remoteHosts.count == 1)
        #expect(remoteHosts.first?.name == "buildbox")
        #expect(remoteHosts.first?.activeAccount?.email == "buildbox@example.com")
        #expect(settings.remoteHostStates.count == 2)
        #expect(settings.remoteHostState(for: "user@buildbox")?.activeAccount?.email == "buildbox@example.com")
        #expect(settings.remoteHostState(for: "user@debian-vm")?.desiredAccountID != nil)
        #expect(settings.remoteHostState(for: "user@debian-vm")?.activeAccount == nil)
        #expect(settings.remoteHostState(for: "user@debian-vm")?.verificationStatus == .failed)
    }

    @Test
    func reverifyHostActionPromotesFailedHostBackToVerified() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationReverifyRemote-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        let persistedAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-2@example.com",
            planType: "team",
            rateLimits: nil,
            identity: .empty
        )
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: persistedAccount.id,
                verifiedAccount: persistedAccount,
                verificationStatus: .failed,
                lastVerificationError: "ssh: connection refused"
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(
                status: CodexAccountStatus(email: "business-2@example.com", planType: "team", rateLimits: nil)
            ),
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        let item = NSMenuItem(title: "Re-verify Remote Account", action: nil, keyEquivalent: "")
        item.representedObject = HostSelectionMenuItemPayload(hostDestination: "user@buildbox")
        coordinator.reverifyHost(item)
        try? await Task.sleep(for: .milliseconds(50))

        let refreshedState = try #require(settings.remoteHostState(for: "user@buildbox"))
        #expect(refreshedState.verificationStatus == .verified)
        #expect(refreshedState.activeAccount?.email == "business-2@example.com")
        #expect(sink.events.contains(where: { $0.event == "remote_host_reverify_started" }))
        #expect(sink.events.contains(where: { $0.event == "remote_host_reverify_succeeded" }))
    }

    @Test
    func adoptDetectedRemoteAccountPromotesMismatchToVerified() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        try repository.bootstrapStorage()

        let desiredAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-2@example.com",
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: "acct-business-2",
                snapshotFingerprint: "snapshot-business-2",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "business-2@example.com")
            )
        )
        let detectedAccount = CodexAccount(
            id: UUID(),
            name: "Business 1",
            snapshotFileName: "business-1.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-1@example.com",
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: "acct-business-1",
                snapshotFingerprint: "snapshot-business-1",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "business-1@example.com")
            )
        )
        try repository.saveAccounts([desiredAccount, detectedAccount])

        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        store.load()

        let suiteName = "MenuBarLiveValidationAdoptDetectedRemote-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: desiredAccount.id,
                verifiedAccount: nil,
                detectedAccountID: detectedAccount.id,
                verificationStatus: .failed,
                lastVerificationError: "buildbox is using Business 1, not Business 2."
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(
                status: CodexAccountStatus(
                    email: "business-1@example.com",
                    planType: "team",
                    rateLimits: nil,
                    stableAccountID: "acct-business-1",
                    snapshotFingerprint: "snapshot-business-1"
                )
            ),
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        let item = NSMenuItem(title: "Use Detected Account", action: nil, keyEquivalent: "")
        item.representedObject = HostAccountMenuItemPayload(
            accountID: detectedAccount.id,
            hostDestination: "user@buildbox"
        )
        coordinator.adoptDetectedRemoteAccount(item)
        try? await Task.sleep(for: .milliseconds(50))

        let refreshedState = try #require(settings.remoteHostState(for: "user@buildbox"))
        #expect(refreshedState.desiredAccountID == detectedAccount.id)
        #expect(refreshedState.detectedAccountID == nil)
        #expect(refreshedState.verificationStatus == .verified)
        #expect(refreshedState.activeAccount?.id == detectedAccount.id)
        #expect(sink.snapshots.last?.remoteHosts.first?.activeAccount?.name == "Business 1")
    }

    @Test
    func coordinatorMarksRemoteHostFailedWhenStartupRefreshNoLongerMatchesDesiredAccount() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationRemoteMismatch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        let persistedAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-2@example.com",
            planType: "team",
            rateLimits: nil,
            identity: .empty
        )
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                activeAccount: persistedAccount
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(
                status: CodexAccountStatus(
                    email: "different@example.com",
                    planType: "team",
                    rateLimits: nil
                )
            ),
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        let refreshedState = try #require(settings.remoteHostState(for: "user@buildbox"))
        #expect(refreshedState.desiredAccountID == persistedAccount.id)
        #expect(refreshedState.activeAccount == nil)
        #expect(refreshedState.verificationStatus == .failed)
        #expect(refreshedState.lastVerificationError?.contains("could not verify") == true)
        #expect(sink.snapshots.last?.remoteHosts.isEmpty == true)
    }

    @Test
    func coordinatorKeepsReachableRemoteHostConnectedWhenAuthVerificationReadFails() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        try repository.bootstrapStorage()
        let alertPresenter = AlertPresenterProbe()
        let account = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-2@example.com",
            planType: "team",
            rateLimits: nil,
            identity: .empty
        )
        try repository.saveAccounts([account])

        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        store.load()

        let suiteName = "MenuBarLiveValidationReachableRemoteFailure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: account.id,
                verifiedAccount: nil,
                verificationStatus: .unverified
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(
                readError: RemoteHostClientError.authReadFailed("cat: .codex/auth.json: Permission denied")
            ),
            alertPresenter: alertPresenter,
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        let snapshot = try #require(sink.snapshots.last)
        let remoteHost = try #require(snapshot.remoteHosts.first)
        #expect(remoteHost.connectionState == "connected")
        #expect(remoteHost.verificationStatus == "failed")
        #expect(remoteHost.lastVerificationError == "cat: .codex/auth.json: Permission denied")
        #expect(alertPresenter.infoRequests.isEmpty)
    }

    @Test
    func switchAccountOnHostKeepsReachableRemoteHostConnectedWhenAuthVerificationReadFails() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        try repository.bootstrapStorage()
        let account = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-2@example.com",
            planType: "team",
            rateLimits: nil,
            identity: .empty
        )
        try repository.saveAccounts([account])

        let suiteName = "MenuBarLiveValidationReachableRemoteSwitchFailure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: nil,
                verifiedAccount: nil,
                verificationStatus: .unverified
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let remoteHostClient = RemoteHostStatusProbe(
            readError: RemoteHostClientError.authReadFailed("cat: .codex/auth.json: Permission denied")
        )
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient(),
            remoteHostSwitchOperations: remoteHostClient
        )
        store.load()

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: remoteHostClient,
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        let item = NSMenuItem(title: "Switch on buildbox", action: nil, keyEquivalent: "")
        item.representedObject = HostAccountMenuItemPayload(
            accountID: account.id,
            hostDestination: "user@buildbox"
        )
        coordinator.switchAccountOnHost(item)
        try? await Task.sleep(for: .milliseconds(50))

        let persistedState = try #require(settings.remoteHostState(for: "user@buildbox"))
        #expect(persistedState.desiredAccountID == account.id)
        #expect(persistedState.activeAccount == nil)
        #expect(persistedState.verificationStatus == .failed)
        #expect(persistedState.lastVerificationError == "cat: .codex/auth.json: Permission denied")

        let snapshot = try #require(sink.snapshots.last)
        let remoteHost = try #require(snapshot.remoteHosts.first)
        #expect(remoteHost.connectionState == "connected")
        #expect(remoteHost.verificationStatus == "failed")
        #expect(remoteHost.lastVerificationError == "cat: .codex/auth.json: Permission denied")
        #expect(sink.events.contains(where: { $0.event == "remote_host_switch_started" }))
        #expect(sink.events.contains(where: { $0.event == "remote_host_switch_failed" }))
    }

    @Test
    func switchAccountOnHostPersistsPreviousVerifiedRemoteLimitsBackIntoCatalog() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        try repository.bootstrapStorage()
        let now = Date()
        let previousSaved = CodexAccount(
            id: UUID(),
            name: "Business 4",
            snapshotFileName: "business-4.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-4@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(usedPercent: 0, resetsAt: now.addingTimeInterval(2 * 60 * 60), windowDurationMinutes: 300),
                secondary: CodexRateLimitWindow(usedPercent: 0, resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60), windowDurationMinutes: 10_080),
                fetchedAt: now
            ),
            identity: CodexAccountIdentity(
                snapshotFingerprint: "business-4",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "business-4@example.com")
            )
        )
        var previousVerified = previousSaved
        previousVerified.applyRemoteMetadata(
            email: previousSaved.email,
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(usedPercent: 100, resetsAt: now.addingTimeInterval(3 * 60 * 60), windowDurationMinutes: 300),
                secondary: CodexRateLimitWindow(usedPercent: 16, resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60), windowDurationMinutes: 10_080),
                fetchedAt: now
            )
        )
        let nextAccount = CodexAccount(
            id: UUID(),
            name: "Business 5",
            snapshotFileName: "business-5.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-5@example.com",
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: "business-5",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "business-5@example.com")
            )
        )
        try repository.saveAccounts([previousSaved, nextAccount])

        let suiteName = "MenuBarLiveValidationRemoteCatalogBackfill-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: previousSaved.id,
                verifiedAccount: previousVerified,
                verificationStatus: .verified
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let remoteHostClient = RemoteHostStatusProbe(
            status: CodexAccountStatus(
                email: nextAccount.email,
                planType: "team",
                rateLimits: CodexRateLimitSnapshot(
                    limitID: nil,
                    limitName: nil,
                    planType: "team",
                    primary: CodexRateLimitWindow(usedPercent: 92, resetsAt: now.addingTimeInterval(4 * 60 * 60), windowDurationMinutes: 300),
                    secondary: CodexRateLimitWindow(usedPercent: 14, resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60), windowDurationMinutes: 10_080),
                    fetchedAt: now
                )
            )
        )
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient(),
            remoteHostSwitchOperations: remoteHostClient
        )
        store.load()

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: remoteHostClient,
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        let item = NSMenuItem(title: "Switch on buildbox", action: nil, keyEquivalent: "")
        item.representedObject = HostAccountMenuItemPayload(
            accountID: nextAccount.id,
            hostDestination: "user@buildbox"
        )
        coordinator.switchAccountOnHost(item)
        try? await Task.sleep(for: .milliseconds(50))

        let persistedAccounts = try repository.loadAccounts()
        let persistedPrevious = try #require(persistedAccounts.first(where: { $0.id == previousSaved.id }))
        #expect(persistedPrevious.rateLimits?.primary?.displayedUsedPercent(at: now) == 100)
        #expect(persistedPrevious.rateLimits?.secondary?.displayedUsedPercent(at: now) == 16)

        let hostState = try #require(settings.remoteHostState(for: "user@buildbox"))
        #expect(hostState.verifiedAccount?.id == nextAccount.id)
    }

    @Test
    func switchAccountOnHostRearmsNotificationStateForActivatedRemoteAccount() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        try repository.bootstrapStorage()
        let account = CodexAccount(
            id: UUID(),
            name: "Business 5",
            snapshotFileName: "business-5.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business-5@example.com",
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: "business-5",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "business-5@example.com")
            )
        )
        try repository.saveAccounts([account])

        let suiteName = "MenuBarLiveValidationNotificationRearm-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.remoteHostStates = [
            PersistedRemoteHostState(host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"))
        ]
        settings.notificationsWhenBlockedEnabled = true
        settings.updateAccountNotificationState(for: account.id) { state in
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
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let remoteHostClient = RemoteHostStatusProbe(
            status: CodexAccountStatus(
                email: account.email,
                planType: account.planType,
                rateLimits: account.rateLimits
            )
        )
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient(),
            remoteHostSwitchOperations: remoteHostClient
        )
        store.load()

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: remoteHostClient,
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        let item = NSMenuItem(title: "Switch on buildbox", action: nil, keyEquivalent: "")
        item.representedObject = HostAccountMenuItemPayload(
            accountID: account.id,
            hostDestination: "user@buildbox"
        )
        coordinator.switchAccountOnHost(item)
        try? await Task.sleep(for: .milliseconds(50))

        let persisted = try #require(settings.accountNotificationState(for: account.id))
        #expect(persisted.isArmed)
        #expect(persisted.lastNotification == nil)
    }

    @Test
    func coordinatorPreservesMeaningfulSavedLimitsWhenRemoteRefreshReturnsZeroedWindows() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarLiveValidationRemoteLimitsFallback-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.configuredRemoteHost = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        settings.remoteHostActiveAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "remote@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 97,
                    resetsAt: Date().addingTimeInterval(3600),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 15,
                    resetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: .now
            ),
            identity: .empty
        )
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(
                status: CodexAccountStatus(
                    email: "remote@example.com",
                    planType: "team",
                    rateLimits: CodexRateLimitSnapshot(
                        limitID: nil,
                        limitName: nil,
                        planType: "team",
                        primary: CodexRateLimitWindow(
                            usedPercent: 0,
                            resetsAt: nil,
                            windowDurationMinutes: 300
                        ),
                        secondary: CodexRateLimitWindow(
                            usedPercent: 0,
                            resetsAt: nil,
                            windowDurationMinutes: 10_080
                        ),
                        fetchedAt: .now
                    )
                )
            ),
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        let remoteSummary = try #require(
            sink.snapshots.last?.sections.first(where: { $0.title == "Active Account" })?.items.first
        )
        #expect(remoteSummary.contains("Session: 97% used"))
        #expect(remoteSummary.contains("Weekly: 15% used"))
    }

    @Test
    func coordinatorUsesMatchingInactiveSavedAccountLimitsWhenRemoteRefreshReturnsZeroedWindows() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let matchingSavedAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: Date().addingTimeInterval(3600),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 16,
                    resetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: .now
            ),
            identity: CodexAccountIdentity(
                stableAccountID: "acct-team",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|business-2",
                    chatGPTUserID: "user-business-2"
                ),
                workspaceIdentity: CodexWorkspaceIdentity(
                    workspaceAccountID: "org-business-2",
                    workspaceLabel: "Personal"
                ),
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@gmail.com")
            )
        )
        try repository.bootstrapStorage()
        try repository.saveAccounts([matchingSavedAccount])
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        store.load()

        let suiteName = "MenuBarLiveValidationRemoteInactiveFallback-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                desiredAccountID: matchingSavedAccount.id,
                verifiedAccount: CodexAccount(
                    id: matchingSavedAccount.id,
                    name: matchingSavedAccount.name,
                    snapshotFileName: matchingSavedAccount.snapshotFileName,
                    createdAt: matchingSavedAccount.createdAt,
                    updatedAt: matchingSavedAccount.updatedAt,
                    email: matchingSavedAccount.email,
                    planType: matchingSavedAccount.planType,
                    rateLimits: CodexRateLimitSnapshot(
                        limitID: nil,
                        limitName: nil,
                        planType: "team",
                        primary: CodexRateLimitWindow(
                            usedPercent: 0,
                            resetsAt: nil,
                            windowDurationMinutes: 300
                        ),
                        secondary: CodexRateLimitWindow(
                            usedPercent: 0,
                            resetsAt: nil,
                            windowDurationMinutes: 10_080
                        ),
                        fetchedAt: .now
                    ),
                    identity: matchingSavedAccount.identity
                )
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(
                status: CodexAccountStatus(
                    email: "raphaelgrau@gmail.com",
                    planType: "team",
                    rateLimits: CodexRateLimitSnapshot(
                        limitID: nil,
                        limitName: nil,
                        planType: "team",
                        primary: CodexRateLimitWindow(
                            usedPercent: 0,
                            resetsAt: nil,
                            windowDurationMinutes: 300
                        ),
                        secondary: CodexRateLimitWindow(
                            usedPercent: 0,
                            resetsAt: nil,
                            windowDurationMinutes: 10_080
                        ),
                        fetchedAt: .now
                    )
                )
            ),
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        let remoteSummary = try #require(
            sink.snapshots.last?.sections.first(where: { $0.title == "Active Account" })?.items.first
        )
        #expect(remoteSummary.contains("Session: 100% used"))
        #expect(remoteSummary.contains("Weekly: 16% used"))
    }

    @Test
    func coordinatorRelinksStaleRemoteHostAccountIDsToCurrentSavedCatalogOnStartup() async throws {
        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let now = Date.now
        let currentSavedAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval(21 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 16,
                    resetsAt: now.addingTimeInterval(5 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ),
            identity: CodexAccountIdentity(
                stableAccountID: "acct-team",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|business-2",
                    chatGPTUserID: "user-business-2"
                ),
                workspaceIdentity: CodexWorkspaceIdentity(
                    workspaceAccountID: "org-business-2",
                    workspaceLabel: "Personal"
                ),
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@gmail.com")
            )
        )
        try repository.bootstrapStorage()
        try repository.saveAccounts([currentSavedAccount])
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        store.load()

        let suiteName = "MenuBarLiveValidationRelinkedRemoteHost-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        let staleRemoteAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "stale-business-2.json",
            createdAt: now.addingTimeInterval(-3600),
            updatedAt: now.addingTimeInterval(-3600),
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval(-45 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 16,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now.addingTimeInterval(-3600)
            ),
            identity: CodexAccountIdentity(
                stableAccountID: "d8422eb7-1cdf-4c9f-af05-736ffb0ec845",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|63892cb90f565d7364529cd1",
                    chatGPTUserID: "user-v1Xnksr7Nc6WNNVd8Z9HkaSL"
                ),
                workspaceIdentity: CodexWorkspaceIdentity(
                    workspaceAccountID: "org-dE46tuoTzGzCaGdw0YP0CZpz",
                    workspaceLabel: "Personal"
                ),
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@gmail.com")
            )
        )
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "debian-vm", displayName: "debian-vm"),
                desiredAccountID: staleRemoteAccount.id,
                verifiedAccount: staleRemoteAccount,
                verificationStatus: .verified
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: RemoteHostStatusProbe(
                status: CodexAccountStatus(
                    email: "raphaelgrau@gmail.com",
                    planType: "team",
                    rateLimits: nil
                )
            ),
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        let refreshedHostState = try #require(settings.remoteHostState(for: "debian-vm"))
        #expect(refreshedHostState.desiredAccountID == currentSavedAccount.id)
        #expect(refreshedHostState.activeAccount?.id == currentSavedAccount.id)
        #expect(refreshedHostState.activeAccount?.rateLimits?.primary?.displayedUsedPercent(at: now) == 100)
        let actualPrimaryReset = try #require(refreshedHostState.activeAccount?.rateLimits?.primary?.resetsAt)
        let expectedPrimaryReset = try #require(currentSavedAccount.rateLimits?.primary?.resetsAt)
        #expect(abs(actualPrimaryReset.timeIntervalSince(expectedPrimaryReset)) < 1)

        let remoteSummary = try #require(
            sink.snapshots.last?.sections.first(where: { $0.title == "Active Account" })?.items.first
        )
        #expect(remoteSummary.contains("Session: 100% used"))
        #expect(remoteSummary.contains("Weekly: 16% used"))
    }

    @Test
    func scheduledRefreshUpdatesVerifiedRemoteHostUsage() async throws {
        setenv(AppRuntimeEnvironment.validationAutoRefreshIntervalSecondsEnvironmentKey, "0.05", 1)
        defer { unsetenv(AppRuntimeEnvironment.validationAutoRefreshIntervalSecondsEnvironmentKey) }

        let sink = ValidationSinkProbe()
        let repository = try makeIsolatedRepository()
        let now = Date.now
        let account = CodexAccount(
            id: UUID(),
            name: "Business 4",
            snapshotFileName: "business-4.json",
            createdAt: now,
            updatedAt: now,
            email: "raphaelgrau@icloud.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 0,
                    resetsAt: now.addingTimeInterval(5 * 60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 0,
                    resetsAt: now.addingTimeInterval(7 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ),
            identity: CodexAccountIdentity(
                stableAccountID: "acct-business-4",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|business-4",
                    chatGPTUserID: "user-business-4"
                ),
                workspaceIdentity: CodexWorkspaceIdentity(
                    workspaceAccountID: "org-business-4",
                    workspaceLabel: "Team"
                ),
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@icloud.com")
            )
        )
        try repository.bootstrapStorage()
        try repository.saveAccounts([account])

        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        store.load()

        let suiteName = "MenuBarLiveValidationScheduledRemoteRefresh-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@debian-vm", displayName: "debian-vm"),
                desiredAccountID: account.id,
                verifiedAccount: account
            )
        ]
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let remoteHostClient = RemoteHostSequenceProbe(statusesByDestination: [
            "user@debian-vm": [
                CodexAccountStatus(
                    email: "raphaelgrau@icloud.com",
                    planType: "team",
                    rateLimits: CodexRateLimitSnapshot(
                        limitID: "codex",
                        limitName: nil,
                        planType: "team",
                        primary: CodexRateLimitWindow(
                            usedPercent: 0,
                            resetsAt: now.addingTimeInterval(5 * 60 * 60),
                            windowDurationMinutes: 300
                        ),
                        secondary: CodexRateLimitWindow(
                            usedPercent: 0,
                            resetsAt: now.addingTimeInterval(7 * 24 * 60 * 60),
                            windowDurationMinutes: 10_080
                        ),
                        fetchedAt: now
                    ),
                    stableAccountID: account.identity.stableAccountID,
                    authPrincipalIdentity: account.identity.authPrincipalIdentity,
                    workspaceIdentity: account.identity.workspaceIdentity,
                    snapshotFingerprint: account.identity.snapshotFingerprint
                ),
                CodexAccountStatus(
                    email: "raphaelgrau@icloud.com",
                    planType: "team",
                    rateLimits: CodexRateLimitSnapshot(
                        limitID: "codex",
                        limitName: nil,
                        planType: "team",
                        primary: CodexRateLimitWindow(
                            usedPercent: 39,
                            resetsAt: now.addingTimeInterval(4 * 60 * 60),
                            windowDurationMinutes: 300
                        ),
                        secondary: CodexRateLimitWindow(
                            usedPercent: 6,
                            resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                            windowDurationMinutes: 10_080
                        ),
                        fetchedAt: now.addingTimeInterval(60)
                    ),
                    stableAccountID: account.identity.stableAccountID,
                    authPrincipalIdentity: account.identity.authPrincipalIdentity,
                    workspaceIdentity: account.identity.workspaceIdentity,
                    snapshotFingerprint: account.identity.snapshotFingerprint
                )
            ]
        ])

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostMenuOperations: remoteHostClient,
            alertPresenter: AlertPresenterProbe(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(220))

        let remoteSummary = try #require(
            sink.snapshots.last?.sections.first(where: { $0.title == "Active Account" })?.items.first
        )
        #expect(remoteSummary.contains("Session: 39% used"))
        #expect(remoteSummary.contains("Weekly: 6% used"))
        #expect(await remoteHostClient.readCount(for: "user@debian-vm") >= 2)
    }

    private func makeIsolatedRepository() throws -> AccountRepository {
        let appSupportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarLiveValidationTests-\(UUID().uuidString)", isDirectory: true)
        return try AccountRepository(
            environment: [AppRuntimeEnvironment.validationAppSupportDirectoryEnvironmentKey: appSupportDirectory.path]
        )
    }

    private func makeActiveAccount(
        named name: String,
        email: String,
        in repository: AccountRepository
    ) throws -> CodexAccount {
        try repository.bootstrapStorage()
        let authData = Data("auth-\(UUID().uuidString)".utf8)
        var account = try CodexAuthSnapshotService(repository: repository)
            .saveAuthSnapshot(authData, named: name)
        account.email = email
        account.planType = "team"
        account.identity.remoteIdentity = CodexRemoteAccountIdentity(emailAddress: email)
        try repository.saveAccounts([account])
        try authData.write(to: repository.paths.codexAuthFile, options: .atomic)
        return account
    }
}

private final class ValidationSinkProbe: @unchecked Sendable, MenuBarValidationSink {
    private(set) var snapshots: [MenuBarValidationSnapshot] = []
    private(set) var events: [MenuBarValidationEvent] = []

    func record(_ snapshot: MenuBarValidationSnapshot) throws {
        snapshots.append(snapshot)
    }

    func record(_ event: MenuBarValidationEvent) throws {
        events.append(event)
    }
}

private final class UserNotificationCenterProbe: @unchecked Sendable, UserNotificationCenterClient {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var requestAuthorizationCallCount = 0
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var notificationCategories: Set<UNNotificationCategory> = []

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatus
    }

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationCallCount += 1
        authorizationStatus = .authorized
        return true
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        notificationCategories = categories
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

private struct NullCodexAppProcessClient: CodexAppProcessClient {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}

private struct RemoteHostStatusProbe: RemoteHostSwitchWorkflowOperations, RemoteHostAccountSigningOut {
    var status: CodexAccountStatus?
    var statusesByDestination: [String: CodexAccountStatus] = [:]
    var readError: Error?
    var readErrorsByDestination: [String: Error] = [:]
    var switchError: Error?

    func testConnection(to host: RemoteHost) async throws {}
    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState { .installed }
    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        if let switchError {
            throw switchError
        }
    }
    func signOut(on host: RemoteHost) async throws {}
    func refreshCodexAppServer(on host: RemoteHost) async throws {}
    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        if let scopedError = readErrorsByDestination[host.destination] {
            throw scopedError
        }
        if let readError {
            throw readError
        }
        if let scopedStatus = statusesByDestination[host.destination] {
            return scopedStatus
        }
        if let status {
            return status
        }
        return CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)
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
            return CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)
        }
        if statuses.count > 1 {
            statuses.removeFirst()
            statusesByDestination[host.destination] = statuses
        }
        return first
    }

    func readCount(for destination: String) -> Int {
        return readCounts[destination, default: 0]
    }
}
