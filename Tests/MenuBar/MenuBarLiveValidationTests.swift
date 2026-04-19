import AppKit
import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarLiveValidationTests {
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
        let repository = try AccountRepository()
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
            alertPresenter: MenuBarAlertPresenter(),
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
        let repository = try AccountRepository()
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
            email: "old@example.com",
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
            alertPresenter: MenuBarAlertPresenter(),
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
    func coordinatorRestoresAllPersistedRemoteHostAccountsOnStart() async throws {
        let sink = RecordingValidationSink()
        let repository = try AccountRepository()
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
                    email: "old-buildbox@example.com",
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
                    email: "old-debian@example.com",
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
            alertPresenter: MenuBarAlertPresenter(),
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
    func coordinatorPreservesMeaningfulSavedLimitsWhenRemoteRefreshReturnsZeroedWindows() async throws {
        let sink = RecordingValidationSink()
        let repository = try AccountRepository()
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
            email: "old@example.com",
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
            alertPresenter: MenuBarAlertPresenter(),
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
        let repository = try AccountRepository()
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
        settings.configuredRemoteHost = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        settings.remoteHostActiveAccount = CodexAccount(
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
            alertPresenter: MenuBarAlertPresenter(),
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

    func testConnection(to host: RemoteHost) async throws {}
    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState { .installed }
    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        if let scopedStatus = statusesByDestination[host.destination] {
            return scopedStatus
        }
        if let status {
            return status
        }
        return CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)
    }
}
