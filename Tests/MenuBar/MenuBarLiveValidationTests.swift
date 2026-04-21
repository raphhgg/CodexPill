import AppKit
import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarLiveValidationTests {
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

        let remoteSection = try #require(snapshot.sections.first(where: { $0.title == "Remote Accounts" }))
        #expect(remoteSection.items.first?.contains("Desired: Business 2") == true)
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
                .init(title: "Current Account", items: ["Primary • Pro • primary@example.com"])
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
                    title: "Display",
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
    func coordinatorRefreshesLiveSnapshotWhenStatusItemRuntimeStateChanges() throws {
        let sink = RecordingValidationSink()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        let suiteName = "MenuBarLiveValidationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            alertPresenter: TestMenuBarAlertPresenter(),
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
    func coordinatorRestoresPersistedRemoteHostAccountOnStart() async throws {
        let sink = RecordingValidationSink()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        let suiteName = "MenuBarLiveValidationRemoteRestore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(
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
            alertPresenter: TestMenuBarAlertPresenter(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(sink.snapshots.contains(where: { $0.sections.contains(where: { $0.title == "Remote Accounts" }) }))
        #expect(sink.snapshots.last?.remoteHosts.first?.activeAccount?.email == "remote@example.com")
    }

    @Test
    func coordinatorMarksPersistedRemoteHostDisconnectedWhenRefreshFails() async throws {
        let sink = RecordingValidationSink()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        let suiteName = "MenuBarLiveValidationRemoteFailure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(
                readError: RemoteHostClientError.commandFailed("ssh: connection refused")
            ),
            alertPresenter: TestMenuBarAlertPresenter(),
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
        let sink = RecordingValidationSink()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        let suiteName = "MenuBarLiveValidationMissingDesiredRemote-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(),
            alertPresenter: TestMenuBarAlertPresenter(),
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
        let sink = RecordingValidationSink()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        let suiteName = "MenuBarLiveValidationMultipleRemoteRestore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(
                statusesByDestination: [
                    "user@buildbox": CodexAccountStatus(email: "buildbox@example.com", planType: "team", rateLimits: nil),
                    "user@debian-vm": CodexAccountStatus(email: "debian@example.com", planType: "team", rateLimits: nil)
                ]
            ),
            alertPresenter: TestMenuBarAlertPresenter(),
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
        let sink = RecordingValidationSink()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        let suiteName = "MenuBarLiveValidationMixedRemoteRestore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(
                statusesByDestination: [
                    "user@buildbox": CodexAccountStatus(email: "buildbox@example.com", planType: "team", rateLimits: nil)
                ],
                readErrorsByDestination: [
                    "user@debian-vm": RemoteHostClientError.commandFailed("ssh: connection refused")
                ]
            ),
            alertPresenter: TestMenuBarAlertPresenter(),
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
        let sink = RecordingValidationSink()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        let suiteName = "MenuBarLiveValidationReverifyRemote-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(
                status: CodexAccountStatus(email: "business-2@example.com", planType: "team", rateLimits: nil)
            ),
            alertPresenter: TestMenuBarAlertPresenter(),
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
        let sink = RecordingValidationSink()
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
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        store.load()

        let suiteName = "MenuBarLiveValidationAdoptDetectedRemote-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(
                status: CodexAccountStatus(
                    email: "business-1@example.com",
                    planType: "team",
                    rateLimits: nil,
                    stableAccountID: "acct-business-1",
                    snapshotFingerprint: "snapshot-business-1"
                )
            ),
            alertPresenter: TestMenuBarAlertPresenter(),
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
        let sink = RecordingValidationSink()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        let suiteName = "MenuBarLiveValidationRemoteMismatch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(
                status: CodexAccountStatus(
                    email: "different@example.com",
                    planType: "team",
                    rateLimits: nil
                )
            ),
            alertPresenter: TestMenuBarAlertPresenter(),
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
        let sink = RecordingValidationSink()
        let repository = try makeIsolatedRepository()
        try repository.bootstrapStorage()
        let alertPresenter = TestMenuBarAlertPresenter()
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
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        store.load()

        let suiteName = "MenuBarLiveValidationReachableRemoteFailure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(
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
        let sink = RecordingValidationSink()
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
        let settings = AppSettings(userDefaults: defaults)
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

        let remoteHostClient = RemoteHostClientStatusSpy(
            readError: RemoteHostClientError.authReadFailed("cat: .codex/auth.json: Permission denied")
        )
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient(),
            remoteHostClient: remoteHostClient
        )
        store.load()

        let coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            remoteHostClient: remoteHostClient,
            alertPresenter: TestMenuBarAlertPresenter(),
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
    func coordinatorPreservesMeaningfulSavedLimitsWhenRemoteRefreshReturnsZeroedWindows() async throws {
        let sink = RecordingValidationSink()
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        let suiteName = "MenuBarLiveValidationRemoteLimitsFallback-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(
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
            alertPresenter: TestMenuBarAlertPresenter(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        let remoteSummary = try #require(
            sink.snapshots.last?.sections.first(where: { $0.title == "Remote Accounts" })?.items.first
        )
        #expect(remoteSummary.contains("Session: 97% used"))
        #expect(remoteSummary.contains("Weekly: 15% used"))
    }

    @Test
    func coordinatorUsesMatchingInactiveSavedAccountLimitsWhenRemoteRefreshReturnsZeroedWindows() async throws {
        let sink = RecordingValidationSink()
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
        let personalAccount = CodexAccount(
            id: UUID(),
            name: "Personal 1",
            snapshotFileName: "personal-1.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "raphaelgrau@gmail.com",
            planType: "plus",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "plus",
                primary: CodexRateLimitWindow(
                    usedPercent: 44,
                    resetsAt: Date().addingTimeInterval(7200),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 8,
                    resetsAt: Date().addingTimeInterval(3 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: .now
            ),
            identity: CodexAccountIdentity(
                stableAccountID: "acct-personal",
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
        try repository.saveAccounts([matchingSavedAccount, personalAccount])
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        store.load()

        let suiteName = "MenuBarLiveValidationRemoteInactiveFallback-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(
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
            alertPresenter: TestMenuBarAlertPresenter(),
            validationSink: sink,
            validationScenario: "live-menu-open",
            allowsEmptyStatePrompt: false
        )

        coordinator.start()
        try? await Task.sleep(for: .milliseconds(50))

        let remoteSummary = try #require(
            sink.snapshots.last?.sections.first(where: { $0.title == "Remote Accounts" })?.items.first
        )
        #expect(remoteSummary.contains("Session: 100% used"))
        #expect(remoteSummary.contains("Weekly: 16% used"))
    }

    @Test
    func coordinatorRelinksStaleRemoteHostAccountIDsToCurrentSavedCatalogOnStartup() async throws {
        let sink = RecordingValidationSink()
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
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        store.load()

        let suiteName = "MenuBarLiveValidationRelinkedRemoteHost-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
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
            remoteHostClient: RemoteHostClientStatusSpy(
                status: CodexAccountStatus(
                    email: "raphaelgrau@gmail.com",
                    planType: "team",
                    rateLimits: nil
                )
            ),
            alertPresenter: TestMenuBarAlertPresenter(),
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
            sink.snapshots.last?.sections.first(where: { $0.title == "Remote Accounts" })?.items.first
        )
        #expect(remoteSummary.contains("Session: 100% used"))
        #expect(remoteSummary.contains("Weekly: 16% used"))
    }

    private func makeIsolatedRepository() throws -> AccountRepository {
        let appSupportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarLiveValidationTests-\(UUID().uuidString)", isDirectory: true)
        return try AccountRepository(
            environment: [AppRuntimeEnvironment.validationAppSupportDirectoryEnvironmentKey: appSupportDirectory.path]
        )
    }
}

private final class RecordingValidationSink: @unchecked Sendable, MenuBarValidationSink {
    private(set) var snapshots: [MenuBarValidationSnapshot] = []
    private(set) var events: [MenuBarValidationEvent] = []

    func record(_ snapshot: MenuBarValidationSnapshot) throws {
        snapshots.append(snapshot)
    }

    func record(_ event: MenuBarValidationEvent) throws {
        events.append(event)
    }
}

private struct RemoteHostClientStatusSpy: RemoteHostSwitching {
    var status: CodexAccountStatus?
    var statusesByDestination: [String: CodexAccountStatus] = [:]
    var readError: Error?
    var readErrorsByDestination: [String: Error] = [:]

    func testConnection(to host: RemoteHost) async throws {}
    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState { .installed }
    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
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
