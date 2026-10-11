import AppKit
import Foundation
import Testing

@testable import Refill

@MainActor
struct MenuBarCoordinatorTests {
    @Test
    func removeAccountSignsOutThisMacBeforeDeletingSavedAccount() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let account = try harness.makeActiveAccount(email: "business-4@example.com")
        harness.alertPresenter.confirmationResponse = true
        let coordinator = harness.makeCoordinator()
        coordinator.start()
        await coordinator.waitForPendingWork()

        harness.send(.removeAccount(account.id), for: .codex)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.last?.messageText == "business-4@example.com is in use")
        #expect(harness.alertPresenter.confirmationRequests.last?.informativeText == "Sign out on This Mac before removing it?")
        #expect(harness.accountsController.accounts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: harness.repository.paths.codexAuthFile.path))
    }

    @Test
    func alertsNameAccountsAsTheSideMenuDoesWithEmailsHidden() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.settings.menuDisplaySettings.masksEmails = true
        let codexAccount = try harness.makeActiveAccount(email: "business-4@example.com")
        let claudeAccount = ProviderAccount(id: UUID(), email: "sam@acme.dev", isActive: false)
        let claude = ProviderConnectionProbe(provider: .claude, reading: .snapshot(UsageSnapshot(provider: .claude, planName: nil, windows: [], fetchedAt: Date())))
        claude.update { $0.accounts = [claudeAccount] }
        let coordinator = harness.makeCoordinator(providerConnections: [claude])
        coordinator.start()
        await coordinator.waitForPendingWork()

        harness.send(.switchAccount(codexAccount.id), for: .codex)
        harness.send(.removeAccount(codexAccount.id), for: .codex)
        harness.send(.removeAccount(claudeAccount.id), for: .claude)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.informativeText).first == "This switches This Mac to bu•••4@example.com and restarts Codex.")
        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText).dropFirst() == ["bu•••4@example.com is in use", "Remove s•••m@acme.dev?"])
    }

    @Test
    func firstRunAsksToAddACodexAccountOnlyWhenNoToolIsConnected() async throws {
        for (claudeReading, expectedPrompts) in [(UsageProviderReading.notConnected, 1), (.awaitingUsage, 0)] {
            let harness = try MenuBarCoordinatorHarness()
            defer { harness.tearDown() }
            let coordinator = harness.makeCoordinator(
                providerConnections: [ProviderConnectionProbe(provider: .claude, reading: claudeReading)],
                allowsEmptyStatePrompt: true
            )

            coordinator.start()
            await coordinator.waitForPendingWork()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }

            #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == Array(repeating: "Add a Codex account?", count: expectedPrompts))
        }
    }

    @Test
    func fullyUsedProviderDoesNotChangeAccountRanking() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let now = Date()
        var personal = try harness.makeActiveAccount(email: "personal@example.com")
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
            providerConnections: [ProviderConnectionProbe(provider: .claude, reading: .snapshot(claudeUsage))]
        )

        coordinator.start()
        await coordinator.waitForPendingWork()

        let state = coordinator.menuState()
        #expect(state.providerUsage == [ProviderUsageState(provider: .claude, status: .current(claudeUsage))])
        #expect(state.activeAccount?.email == "personal@example.com")
        #expect(state.inactiveAccounts.map(\.email) == ["business 2@example.com", "business 1@example.com"])
    }

    @Test
    func openingAMenuBuiltAWhileAgoRebuildsItSoCountdownsStartNow() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let builtAt = Date(timeIntervalSince1970: 1_800_000_000)
        var clock = builtAt
        let active = try harness.makeActiveAccount(email: "personal@example.com")
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
        func codexCard() -> NSMenuItem? {
            menu.items.first { $0.title == "Codex" }
        }
        let builtCard = try #require(codexCard())

        clock = builtAt.addingTimeInterval(10)
        coordinator.menuWillOpen(menu)
        #expect(codexCard() === builtCard)

        clock = builtAt.addingTimeInterval(30 * 60)
        coordinator.menuWillOpen(menu)
        #expect(codexCard() !== builtCard)
        #expect(codexCard() != nil)
    }

    @Test
    func switchingWhileAResetCreditIsAppliedExplainsWhyInsteadOfAskingToSwitch() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let active = try harness.makeActiveAccount(email: "personal@example.com")
        let work = makeAccount(name: "Work")
        try harness.repository.saveAccounts([active, work])
        let resetCredits = SuspendedResetCreditClient()
        let coordinator = harness.makeCoordinator(resetCreditClient: resetCredits)
        coordinator.start()
        await coordinator.waitForPendingWork()

        let reset = Task { await harness.accountsController.useResetCredit() }
        await resetCredits.waitUntilCalled()
        harness.send(.switchAccount(work.id), for: .codex)

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
        let coordinator = harness.makeCoordinator(providerConnections: [fixture.usage])
        coordinator.start()
        await coordinator.waitForPendingWork()

        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .claude, status: .notConnected)])
        #expect(mainMenuTitles(coordinator) == ["Add Account", "", "Settings", "", "Quit"])

        harness.click("Claude…")
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Connect Claude Code?"])
        #expect(fixture.settings.isEnabled == false)
        #expect(fixture.keychainReadPrompts == [])

        harness.alertPresenter.confirmationResponse = true
        harness.click("Claude…")
        await coordinator.waitForPendingWork()

        #expect(fixture.keychainReadPrompts == [true])
        guard case .current = coordinator.menuState().providerUsage.first?.status else {
            Issue.record("Expected current Claude usage right after connecting")
            return
        }
        #expect(mainMenuTitles(coordinator) == ["Claude", "", "Settings", "", "Quit"])

        fixture.signInToKeychain(expiresAt: Date().addingTimeInterval(3_600), needsPermission: true)
        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()

        guard case .unavailable(.keychainAccessNeeded, lastSnapshot: .some) = coordinator.menuState().providerUsage.first?.status else {
            Issue.record("Expected the Allow Keychain access state with the last usage kept")
            return
        }
        #expect(mainMenuTitles(coordinator) == ["Claude", "Allow Keychain access…", "", "Settings", "", "Quit"])

        harness.click("Allow Keychain access…")
        await coordinator.waitForPendingWork()

        guard case .current = coordinator.menuState().providerUsage.first?.status else {
            Issue.record("Expected current Claude usage after allowing Keychain access")
            return
        }
        #expect(fixture.keychainReadPrompts.suffix(2) == [false, true])

        harness.click("Disconnect Claude")
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.count == 2)
        #expect(fixture.settings.isEnabled == false)
        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .claude, status: .notConnected)])
        #expect(mainMenuTitles(coordinator) == ["Add Account", "", "Settings", "", "Quit"])
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
        let coordinator = harness.makeCoordinator(providerConnections: [fixture.usage])
        coordinator.start()
        await coordinator.waitForPendingWork()

        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .cursor, status: .notConnected)])
        #expect(mainMenuTitles(coordinator) == ["Add Account", "", "Settings", "", "Quit"])

        harness.click("Cursor…")
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Connect Cursor?"])
        #expect(fixture.settings.isEnabled == false)
        #expect(fixture.requestCount == 0)

        harness.alertPresenter.confirmationResponse = true
        harness.click("Cursor…")
        await coordinator.waitForPendingWork()

        let current = UsageSnapshot(
            provider: .cursor,
            planName: "pro",
            windows: [UsageWindow(kind: .billingCycle, usedPercent: 82, resetsAt: Date(timeIntervalSince1970: 1_793_373_788), durationMinutes: 43_200)],
            fetchedAt: now,
            spend: UsageSpend(usedUSD: Decimal(string: "12.34")!, limitUSD: 50)
        )
        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .cursor, status: .current(current))])
        #expect(mainMenuTitles(coordinator) == ["Cursor", "", "Settings", "", "Quit"])

        fixture.response = .failure(.transport)
        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()

        #expect(coordinator.menuState().providerUsage == [
            ProviderUsageState(provider: .cursor, status: .unavailable(.unreachable, lastSnapshot: current))
        ])

        harness.click("Disconnect Cursor")
        await coordinator.waitForPendingWork()

        #expect(fixture.settings.isEnabled == false)
        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .cursor, status: .notConnected)])
        #expect(mainMenuTitles(coordinator) == ["Add Account", "", "Settings", "", "Quit"])
    }

    @Test
    func switchingAToolAccountNeverShowsThePreviousAccountsNumbers() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let now = Date()
        let personal = UUID()
        let work = UUID()
        let personalUsage = UsageSnapshot(
            provider: .cursor,
            planName: "pro",
            windows: [UsageWindow(kind: .billingCycle, usedPercent: 82, resetsAt: now.addingTimeInterval(86_400), durationMinutes: 43_200)],
            fetchedAt: now
        )
        let cursor = ProviderConnectionProbe(provider: .cursor, reading: .snapshot(personalUsage))
        cursor.update {
            $0.accounts = [
                ProviderAccount(id: personal, email: "personal@example.com", isActive: true),
                ProviderAccount(id: work, email: "work@example.com", isActive: false),
            ]
            $0.readingAfterSwitch = .unavailable(.unreachable)
        }
        let coordinator = harness.makeCoordinator(providerConnections: [cursor])
        coordinator.start()
        await coordinator.waitForPendingWork()
        #expect(coordinator.menuState().providerUsage.first?.status == .current(personalUsage))

        harness.alertPresenter.confirmationResponse = true
        harness.send(.switchAccount(work), for: .cursor)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Switch to work@example.com?"])
        #expect(cursor.switchedTo == [work])
        #expect(coordinator.menuState().providerUsage == [
            ProviderUsageState(
                provider: .cursor,
                status: .unavailable(.unreachable, lastSnapshot: nil),
                accounts: [
                    ProviderAccount(id: personal, email: "personal@example.com", isActive: false),
                    ProviderAccount(id: work, email: "work@example.com", isActive: true),
                ]
            )
        ])
    }

    @Test
    func aFailedToolSwitchExplainsWhyInAShortAlert() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let claude = ProviderConnectionProbe(provider: .claude, reading: .awaitingUsage)
        claude.update { $0.switchError = ClaudeCodeAccountError.claudeCodeRunning.notice }
        let coordinator = harness.makeCoordinator(providerConnections: [claude])
        coordinator.start()
        await coordinator.waitForPendingWork()

        harness.send(.switchAccount(UUID()), for: .claude)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.isEmpty)
        #expect(harness.alertPresenter.infoRequests.map(\.messageText) == ["Quit Claude Code first"])
        #expect(harness.alertPresenter.infoRequests.map(\.informativeText) == ["Close every claude session."])
    }

    @Test
    func usingACodexResetAsksFirstThenReportsTheOutcome() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        _ = try harness.makeActiveAccount(email: "personal@example.com")
        let resetCredits = SuspendedResetCreditClient()
        let coordinator = harness.makeCoordinator(resetCreditClient: resetCredits)
        coordinator.start()
        await coordinator.waitForPendingWork()

        harness.send(.useResetCredit, for: .codex)
        await coordinator.waitForPendingWork()
        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Reset Codex limits?"])

        harness.alertPresenter.confirmationResponse = true
        harness.send(.useResetCredit, for: .codex)
        await resetCredits.waitUntilCalled()
        await resetCredits.answer(.reset)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.infoRequests.map(\.messageText) == ["Your Codex limits are reset."])
    }

    @Test
    func commonModeTimerFiresWhileAMenuIsTracking() {
        var fireCount = 0
        let timer = Timer.repeatingInCommonModes(interval: 0.01) { fireCount += 1 }
        defer { timer.invalidate() }

        CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString), 0.2, false)

        #expect(fireCount > 0)
    }

    private func mainMenuTitles(_ coordinator: MenuBarCoordinator) -> [String] {
        MenuBarMenuBuilder().makeMenu(state: coordinator.menuState(), target: coordinator).items.map(\.title)
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
        providerConnections: [any ProviderConnection] = [],
        allowsEmptyStatePrompt: Bool = false,
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
            providerConnections: providerConnections,
            allowsEmptyStatePrompt: allowsEmptyStatePrompt,
            now: now
        )
        self.coordinator = coordinator
        return coordinator
    }

    func makeActiveAccount(email: String) throws -> CodexAccount {
        let authData = Data("auth-\(UUID().uuidString)".utf8)
        var account = try CodexAuthSnapshotService(repository: repository).saveAuthSnapshot(authData)
        account.email = email
        account.planType = "team"
        account.identity.remoteIdentity = CodexRemoteAccountIdentity(emailAddress: email)
        try repository.saveAccounts([account])
        try authData.write(to: repository.paths.codexAuthFile, options: .atomic)
        return account
    }

    var menu: NSMenu? { statusItem.menu }

    /// Sends a tool action the way a menu item carrying it would.
    func send(_ action: ProviderAction, for provider: UsageProvider) {
        let item = NSMenuItem()
        item.representedObject = ProviderMenuAction(provider: provider, action: action)
        coordinator?.performProviderAction(item)
    }

    /// Clicks the item titled `title`, in the menu or any submenu, as the coordinator would build it now.
    func click(_ title: String) {
        guard let coordinator else { return }
        let menu = MenuBarMenuBuilder().makeMenu(state: coordinator.menuState(), target: coordinator)
        guard let item = Self.item(titled: title, in: menu), let action = item.action else {
            Issue.record("No menu item titled \(title)")
            return
        }
        _ = (item.target as? NSObject)?.perform(action, with: item)
    }

    private static func item(titled title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title { return item }
            if let submenu = item.submenu, let found = Self.item(titled: title, in: submenu) { return found }
        }
        return nil
    }

    func tearDown() {
        coordinator?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: repositoryDirectory)
    }
}
