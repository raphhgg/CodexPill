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
        let coordinator = harness.makeCoordinator()
        coordinator.start()
        await coordinator.waitForPendingWork()

        harness.send(.switchAccount(codexAccount.id), for: .codex)
        harness.send(.removeAccount(codexAccount.id), for: .codex)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.informativeText).first == "This switches This Mac to bu•••4@example.com and restarts Codex.")
        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText).dropFirst() == ["bu•••4@example.com is in use"])
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
    func switchingWithoutTheCodexAppSwitchesAndSaysCodexWasNotRestarted() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let active = try harness.makeActiveAccount(email: "personal@example.com")
        let workAuth = Data("work-auth".utf8)
        let work = try CodexAuthSnapshotService(repository: harness.repository).saveAuthSnapshot(workAuth)
        try harness.repository.saveAccounts([active, work])
        harness.codexApp.relaunchResult = .appNotFound
        harness.alertPresenter.confirmationResponse = true
        let coordinator = harness.makeCoordinator()
        coordinator.start()
        await coordinator.waitForPendingWork()

        harness.send(.switchAccount(work.id), for: .codex)
        await coordinator.waitForPendingWork()

        #expect(try Data(contentsOf: harness.repository.paths.codexAuthFile) == workAuth)
        #expect(harness.alertPresenter.infoRequests.map(\.messageText) == ["Codex app not found"])
        #expect(harness.alertPresenter.infoRequests.map(\.informativeText) == ["Switched. Codex uses the account when it opens."])
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
        #expect(cardAreaTitles(coordinator) == [])

        harness.click("Appearance", "Show Tools", "Claude")
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Connect Claude Code?"])
        #expect(fixture.settings.isEnabled == false)
        #expect(fixture.keychainReadPrompts == [])

        harness.alertPresenter.confirmationResponse = true
        harness.click("Appearance", "Show Tools", "Claude")
        await coordinator.waitForPendingWork()

        #expect(fixture.keychainReadPrompts == [true])
        guard case .current = coordinator.menuState().providerUsage.first?.status else {
            Issue.record("Expected current Claude usage right after connecting")
            return
        }
        #expect(cardAreaTitles(coordinator) == ["Claude"])

        fixture.signInToKeychain(expiresAt: Date().addingTimeInterval(3_600), needsPermission: true)
        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()

        guard case .unavailable(.keychainAccessNeeded, lastSnapshot: .some) = coordinator.menuState().providerUsage.first?.status else {
            Issue.record("Expected the Allow Keychain access state with the last usage kept")
            return
        }
        #expect(cardAreaTitles(coordinator) == ["Claude", "Allow Keychain Access…"])
        let card = try #require(coordinator.menuState().toolSections.first?.card)
        #expect(card.title == nil)
        #expect(card.detail?.hasPrefix("As of ") == true)
        #expect(card.isDimmed)
        #expect(card.windows.map(\.kind) == [.session, .weekly])

        harness.click("Allow Keychain Access…")
        await coordinator.waitForPendingWork()

        guard case .current = coordinator.menuState().providerUsage.first?.status else {
            Issue.record("Expected current Claude usage after allowing Keychain access")
            return
        }
        #expect(fixture.keychainReadPrompts.suffix(2) == [false, true])

        harness.click("Appearance", "Show Tools", "Claude")
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.count == 2)
        #expect(fixture.settings.isEnabled == false)
        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .claude, status: .notConnected)])
        #expect(cardAreaTitles(coordinator) == [])
    }

    @Test
    func claudeSignInAsksFirstThenShowsWhatWentWrong() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let claude = ProviderConnectionProbe(provider: .claude, reading: .unavailable(.signInExpired))
        claude.update {
            $0.ownSignIn = .signedOut
            $0.notice = ProviderNotice(title: "Claude sign-in timed out", detail: "Start it again from the menu.")
        }
        let coordinator = harness.makeCoordinator(providerConnections: [claude])
        coordinator.start()
        await coordinator.waitForPendingWork()

        harness.send(.signIn, for: .claude)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Sign in with Claude?"])
        #expect(harness.alertPresenter.infoRequests.isEmpty)

        harness.alertPresenter.confirmationResponse = true
        harness.send(.signIn, for: .claude)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.infoRequests.map(\.messageText) == ["Claude sign-in timed out"])
        #expect(harness.alertPresenter.infoRequests.map(\.informativeText) == ["Start it again from the menu."])

        harness.send(.signOut, for: .claude)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.count == 2)
        #expect(harness.alertPresenter.infoRequests.count == 2)
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
        #expect(cardAreaTitles(coordinator) == [])

        harness.click("Appearance", "Show Tools", "Cursor")
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Connect Cursor?"])
        #expect(fixture.settings.isEnabled == false)
        #expect(fixture.requestCount == 0)

        harness.alertPresenter.confirmationResponse = true
        harness.click("Appearance", "Show Tools", "Cursor")
        await coordinator.waitForPendingWork()

        let current = UsageSnapshot(
            provider: .cursor,
            planName: "pro",
            windows: [UsageWindow(kind: .billingCycle, usedPercent: 82, resetsAt: Date(timeIntervalSince1970: 1_793_373_788), durationMinutes: 43_200)],
            fetchedAt: now,
            credits: .extraUsage(spent: Decimal(string: "12.34")!, limit: 50, currencyCode: "USD")
        )
        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .cursor, status: .current(current))])
        #expect(cardAreaTitles(coordinator) == ["Cursor"])

        fixture.response = .failure(.transport)
        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()

        #expect(coordinator.menuState().providerUsage == [
            ProviderUsageState(provider: .cursor, status: .unavailable(.unreachable, lastSnapshot: current))
        ])

        harness.click("Appearance", "Show Tools", "Cursor")
        await coordinator.waitForPendingWork()

        #expect(fixture.settings.isEnabled == false)
        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .cursor, status: .notConnected)])
        #expect(cardAreaTitles(coordinator) == [])
    }

    @Test
    func showToolsHidesAToolsCardAndStopsReadingItUntilCheckedAgain() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.alertPresenter.confirmationResponse = true
        _ = try harness.makeActiveAccount(email: "business-4@example.com")
        let codexReads = CountingAccountStatusClient()
        let claude = ProviderConnectionProbe(provider: .claude, refreshInterval: 0, reading: .snapshot(UsageSnapshot(provider: .claude, planName: nil, windows: [], fetchedAt: Date())))
        let coordinator = harness.makeCoordinator(providerConnections: [claude], accountStatusClient: codexReads)
        coordinator.start()
        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()
        #expect(cardAreaTitles(coordinator) == ["Claude", "", "Codex"])

        harness.click("Appearance", "Show Tools", "Claude")
        harness.click("Appearance", "Show Tools", "Codex")
        await coordinator.waitForPendingWork()
        let (claudeReads, codexReadsWhenHidden) = (claude.readCount, codexReads.readCount)
        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()

        #expect(cardAreaTitles(coordinator) == [])
        #expect(claude.readCount == claudeReads)
        #expect(codexReads.readCount == codexReadsWhenHidden)
        #expect(harness.settings.menuDisplaySettings.hidesCodex)

        harness.click("Appearance", "Show Tools", "Codex")
        harness.click("Appearance", "Show Tools", "Claude")
        await coordinator.waitForPendingWork()

        #expect(cardAreaTitles(coordinator) == ["Claude", "", "Codex"])
        #expect(claude.readCount > claudeReads)
        #expect(codexReads.readCount > codexReadsWhenHidden)
        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Connect Claude Code?"])
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

    /// The main menu's titles above Add Account: the cards and their follow-up rows.
    private func cardAreaTitles(_ coordinator: MenuBarCoordinator) -> [String] {
        let titles = MenuBarMenuBuilder().makeMenu(state: coordinator.menuState(), target: coordinator).items.map(\.title)
        var cardArea = Array(titles.prefix { $0 != "Add Account" })
        if cardArea.last == "" {
            cardArea.removeLast()
        }
        return cardArea
    }
}

@MainActor
private final class MenuBarCoordinatorHarness {
    let repository: AccountRepository
    let settings: SettingsStores
    let alertPresenter = AlertPresenterProbe()
    let panelPresenter = PanelPresenterProbe()
    let codexApp = CodexAppProcessProbe()
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
        accountStatusClient: CodexAccountStatusClient & SavedCodexAccountStatusClient = DisabledAccountStatusClient(),
        resetCreditClient: CodexResetCreditClient = UnavailableResetCreditClient(),
        now: @escaping () -> Date = Date.init
    ) -> MenuBarCoordinator {
        accountsController = AccountsFeatureFactory(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: codexApp,
            accountStatusClient: accountStatusClient,
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

    /// Clicks the enabled item at `path`, such as "Appearance", "Show Tools", "Claude", in the menu the coordinator would build now.
    func click(_ path: String...) {
        guard let coordinator else { return }
        var menu: NSMenu? = MenuBarMenuBuilder().makeMenu(state: coordinator.menuState(), target: coordinator)
        var item: NSMenuItem?
        for title in path {
            item = menu?.items.first { $0.title == title }
            menu = item?.submenu
        }
        guard let item, item.isEnabled, let action = item.action else {
            Issue.record("No enabled menu item at \(path.joined(separator: " › "))")
            return
        }
        _ = (item.target as? NSObject)?.perform(action, with: item)
    }

    func tearDown() {
        coordinator?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: repositoryDirectory)
    }
}
