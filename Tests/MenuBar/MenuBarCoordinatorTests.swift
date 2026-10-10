import AppKit
import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarCoordinatorTests {
    @Test
    func removeAccountSignsOutThisMacBeforeDeletingSavedAccount() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let account = try harness.makeActiveAccount(named: "Business 4", email: "business-4@example.com")
        harness.alertPresenter.confirmationResponse = true
        let coordinator = harness.makeCoordinator()
        coordinator.start()
        await coordinator.waitForPendingWork()

        coordinator.removeAccount(harness.menuItem(representing: account.id.uuidString))
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.last?.messageText == "Business 4 is in use")
        #expect(harness.alertPresenter.confirmationRequests.last?.informativeText == "Sign out on This Mac before removing it?")
        #expect(harness.accountsController.accounts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: harness.repository.paths.codexAuthFile.path))
    }

    @Test
    func fullyUsedProviderDoesNotChangeAccountRanking() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let now = Date()
        var personal = try harness.makeActiveAccount(named: "Personal", email: "personal@example.com")
        personal.usage = makeUsage(resettingAfter: now, sessionUsedPercent: 20, weeklyUsedPercent: 20)
        let busier = makeAccount(name: "Business 1", usage: makeUsage(resettingAfter: now, sessionUsedPercent: 30, weeklyUsedPercent: 30))
        let quieter = makeAccount(name: "Business 2", usage: makeUsage(resettingAfter: now, sessionUsedPercent: 10, weeklyUsedPercent: 10))
        try harness.repository.saveAccounts([personal, busier, quieter])
        let claudeUsage = UsageSnapshot(
            provider: .claude,
            planName: nil,
            windows: [
                UsageWindow(kind: .session, usedPercent: 100, resetsAt: now.addingTimeInterval(3_600), durationMinutes: 300),
                UsageWindow(kind: .weekly, usedPercent: 100, resetsAt: now.addingTimeInterval(86_400), durationMinutes: 10_080)
            ],
            fetchedAt: now
        )
        let coordinator = harness.makeCoordinator(
            providerUsageSources: [UsageProviderSourceProbe(provider: .claude, reading: .snapshot(claudeUsage))]
        )

        coordinator.start()
        await coordinator.waitForPendingWork()

        let state = coordinator.menuState()
        #expect(state.providerUsage == [ProviderUsageState(provider: .claude, status: .current(claudeUsage))])
        #expect(state.activeAccount?.name == "Personal")
        #expect(state.inactiveAccounts.map(\.name) == ["Business 2", "Business 1"])
    }

    @Test
    func openingTheMenuMeasuresResetCountdownsFromTheMomentItOpens() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let builtAt = Date(timeIntervalSince1970: 1_800_000_000)
        var clock = builtAt
        let active = try harness.makeActiveAccount(named: "Personal", email: "personal@example.com")
        let limited = makeAccount(
            name: "Business 2",
            usage: makeUsage(
                sessionUsedPercent: 100,
                sessionResetsAt: builtAt.addingTimeInterval(2 * 60 * 60),
                weeklyUsedPercent: 20,
                weeklyResetsAt: builtAt.addingTimeInterval(3 * 24 * 60 * 60),
                fetchedAt: builtAt
            )
        )
        try harness.repository.saveAccounts([active, limited])
        let coordinator = harness.makeCoordinator(now: { clock })
        coordinator.start()
        await coordinator.waitForPendingWork()
        let menu = try #require(harness.menu)
        func limitedRowTitle() -> String? {
            menu.items.first { ($0.representedObject as? String) == limited.id.uuidString }?.attributedTitle?.string
        }
        #expect(limitedRowTitle()?.contains("S 100% (2h00)") == true)

        clock = builtAt.addingTimeInterval(10)
        coordinator.menuWillOpen(menu)
        #expect(limitedRowTitle()?.contains("S 100% (2h00)") == true)

        clock = builtAt.addingTimeInterval(30 * 60)
        coordinator.menuWillOpen(menu)
        #expect(limitedRowTitle()?.contains("S 100% (1h30)") == true)
    }

    @Test
    func switchingWhileAResetCreditIsAppliedExplainsWhyInsteadOfAskingToSwitch() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let active = try harness.makeActiveAccount(named: "Personal", email: "personal@example.com")
        let work = makeAccount(name: "Work")
        try harness.repository.saveAccounts([active, work])
        let resetCredits = SuspendedResetCreditClient()
        let coordinator = harness.makeCoordinator(resetCreditClient: resetCredits)
        coordinator.start()
        await coordinator.waitForPendingWork()

        let reset = Task { await harness.accountsController.useResetCredit() }
        await resetCredits.waitUntilCalled()
        coordinator.switchAccount(harness.menuItem(representing: work.id.uuidString))

        #expect(harness.alertPresenter.confirmationRequests.isEmpty)
        #expect(harness.alertPresenter.infoRequests.map(\.messageText) == ["Reset in progress"])
        #expect(harness.alertPresenter.infoRequests.map(\.informativeText) == ["Switch accounts when it finishes."])

        await resetCredits.answer(.nothingToReset)
        _ = await reset.value
    }

    @Test
    func claudeSectionAsksForConsentThenAsksForKeychainAccessAndShowsUsage() async throws {
        let harness = try MenuBarCoordinatorHarness()
        let fixture = ClaudeUsageFixture(refreshInterval: 0)
        defer {
            harness.tearDown()
            fixture.remove()
        }
        fixture.signInToKeychain(expiresAt: Date().addingTimeInterval(3_600), needsPermission: true)
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))
        let coordinator = harness.makeCoordinator(providerUsageSources: [fixture.usage], claudeCodeUsage: fixture.usage)
        coordinator.start()
        await coordinator.waitForPendingWork()

        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .claude, status: .notConnected)])
        #expect(claudeMenuTitles(coordinator) == ["Connect Claude Code…"])

        coordinator.connectClaudeCode()
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Connect Claude Code?"])
        #expect(fixture.settings.isEnabled == false)
        #expect(fixture.keychainReadPrompts == [])

        harness.alertPresenter.confirmationResponse = true
        coordinator.connectClaudeCode()
        await coordinator.waitForPendingWork()

        #expect(fixture.keychainReadPrompts == [true])
        guard case .current = coordinator.menuState().providerUsage.first?.status else {
            Issue.record("Expected current Claude usage right after connecting")
            return
        }
        #expect(claudeMenuTitles(coordinator) == ["Disconnect Claude Code…"])

        fixture.signInToKeychain(expiresAt: Date().addingTimeInterval(3_600), needsPermission: true)
        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()

        guard case .unavailable(.keychainAccessNeeded, lastSnapshot: .some) = coordinator.menuState().providerUsage.first?.status else {
            Issue.record("Expected the Allow Keychain access state with the last usage kept")
            return
        }
        #expect(claudeMenuTitles(coordinator) == ["Allow Keychain access…", "Disconnect Claude Code…"])

        coordinator.allowClaudeKeychainAccess()
        await coordinator.waitForPendingWork()

        guard case .current = coordinator.menuState().providerUsage.first?.status else {
            Issue.record("Expected current Claude usage after allowing Keychain access")
            return
        }
        #expect(fixture.keychainReadPrompts.suffix(2) == [false, true])

        coordinator.disconnectClaudeCode()
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.count == 2)
        #expect(fixture.settings.isEnabled == false)
        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .claude, status: .notConnected)])
        #expect(claudeMenuTitles(coordinator) == ["Connect Claude Code…"])
    }

    @Test
    func cursorSectionAsksForConsentThenShowsUsageAndKeepsItThroughAFailedRead() async throws {
        let harness = try MenuBarCoordinatorHarness()
        let now = Date()
        let fixture = CursorUsageFixture(now: { now }, refreshInterval: 0)
        defer {
            harness.tearDown()
            fixture.remove()
        }
        fixture.signIn(expiresAt: now.addingTimeInterval(3_600), summary: CursorUsageFixture.proPlanWithCappedOnDemand)
        let coordinator = harness.makeCoordinator(providerUsageSources: [fixture.usage], cursorUsage: fixture.usage)
        coordinator.start()
        await coordinator.waitForPendingWork()

        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .cursor, status: .notConnected)])
        #expect(cursorMenuTitles(coordinator) == ["Connect Cursor…"])

        coordinator.connectCursor()
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Connect Cursor?"])
        #expect(fixture.settings.isEnabled == false)
        #expect(fixture.requestCount == 0)

        harness.alertPresenter.confirmationResponse = true
        coordinator.connectCursor()
        await coordinator.waitForPendingWork()

        let current = UsageSnapshot(
            provider: .cursor,
            planName: "pro",
            windows: [UsageWindow(kind: .billingCycle, usedPercent: 82, resetsAt: Date(timeIntervalSince1970: 1_793_373_788), durationMinutes: 43_200)],
            fetchedAt: now,
            spend: UsageSpend(usedUSD: Decimal(string: "12.34")!, limitUSD: 50)
        )
        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .cursor, status: .current(current))])
        #expect(cursorMenuTitles(coordinator) == ["Disconnect Cursor…"])

        fixture.response = .failure(.transport)
        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()

        #expect(coordinator.menuState().providerUsage == [
            ProviderUsageState(provider: .cursor, status: .unavailable(.unreachable, lastSnapshot: current))
        ])

        coordinator.disconnectCursor()
        await coordinator.waitForPendingWork()

        #expect(fixture.settings.isEnabled == false)
        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .cursor, status: .notConnected)])
        #expect(cursorMenuTitles(coordinator) == ["Connect Cursor…"])
    }

    @Test
    func commonModeTimerFiresWhileAMenuIsTracking() {
        var fireCount = 0
        let timer = Timer.repeatingInCommonModes(interval: 0.01) { fireCount += 1 }
        defer { timer.invalidate() }

        CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString), 0.2, false)

        #expect(fireCount > 0)
    }

    private func cursorMenuTitles(_ coordinator: MenuBarCoordinator) -> [String] {
        let menu = MenuBarMenuBuilder().makeMenu(state: coordinator.menuState(), target: coordinator)
        let preferences = menu.items.first { $0.title == "Preferences" }?.submenu?.items ?? []
        return (menu.items + preferences).map(\.title).filter { $0.contains("Cursor") }
    }

    /// Claude rows in the main menu and the Preferences submenu, read from the built `NSMenu`.
    private func claudeMenuTitles(_ coordinator: MenuBarCoordinator) -> [String] {
        let menu = MenuBarMenuBuilder().makeMenu(state: coordinator.menuState(), target: coordinator)
        let preferences = menu.items.first { $0.title == "Preferences" }?.submenu?.items ?? []
        return (menu.items + preferences).map(\.title).filter { $0.contains("Claude") || $0.contains("Keychain") }
    }
}

@MainActor
private final class MenuBarCoordinatorHarness {
    let repository: AccountRepository
    let settings: SettingsStores
    let alertPresenter = AlertPresenterProbe()
    let panelPresenter = PanelPresenterProbe()
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
        providerUsageSources: [any UsageProviderSource] = [],
        claudeCodeUsage: ClaudeCodeUsage? = nil,
        cursorUsage: CursorUsage? = nil,
        resetCreditClient: CodexResetCreditClient = UnavailableResetCreditClient(),
        now: @escaping () -> Date = Date.init
    ) -> MenuBarCoordinator {
        accountsController = AccountsFeatureFactory(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: CodexAppProcessProbe(),
            accountStatusClient: DisabledAccountStatusClient(),
            resetCreditClient: resetCreditClient,
            postSwitchRefreshDelay: .zero
        ).makeController()
        accountsController.load()
        let coordinator = MenuBarCoordinator.makeForTesting(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            accountsController: accountsController,
            settings: settings,
            alertPresenter: alertPresenter,
            panelPresenter: panelPresenter,
            providerUsageSources: providerUsageSources,
            claudeCodeUsage: claudeCodeUsage,
            cursorUsage: cursorUsage,
            allowsEmptyStatePrompt: false,
            now: now
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

    var menu: NSMenu? { statusItem.menu }

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
