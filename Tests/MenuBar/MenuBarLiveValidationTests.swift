import AppKit
import Foundation
import Testing
import UserNotifications

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
                .init(title: "Active Account", items: ["Primary • Pro x20"])
            ],
            statusMessage: "Refreshing account data...",
            currentAccount: .init(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                identityDigest: "digest-primary"
            ),
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
            "error": "Authorization: Bearer sk-demo failed for /Users/demo/.codex/auth.json",
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

        defer { coordinator.invalidate() }
        coordinator.start()
        let initialSnapshotCount = sink.snapshots.count

        runtime.handleHoverChanged(true)

        #expect(sink.events.contains(where: { $0.event == "status_item_hover_entered" }))
        #expect(sink.snapshots.count > initialSnapshotCount)
        #expect(sink.snapshots.last?.statusItem?.isHovered == true)
    }


    private func makeIsolatedRepository() throws -> AccountRepository {
        let appSupportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarLiveValidationTests-\(UUID().uuidString)", isDirectory: true)
        return try AccountRepository(
            environment: [AppRuntimeEnvironment.validationAppSupportDirectoryEnvironmentKey: appSupportDirectory.path]
        )
    }

    private func waitUntil(
        timeoutMilliseconds: Int = 1_000,
        condition: () throws -> Bool
    ) async throws {
        let attempts = max(timeoutMilliseconds / 20, 1)
        for _ in 0..<attempts {
            if try condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
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

private struct NullCodexAppProcessClient: CodexAppProcessClient {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}
