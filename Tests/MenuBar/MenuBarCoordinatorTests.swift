import AppKit
import Foundation
import Testing

@testable import RUsage

@MainActor
struct MenuBarCoordinatorTests {
    @Test
    func signingInToAnotherCodexAccountAsksThenReplacesTheOneOnThisMac() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.settings.general.masksEmails = true
        harness.makeActiveAccount(email: "business-4@example.com")
        let newAuth = makeCodexAuthData(email: "sam@example.com", accountID: "acct-2", userID: "user-2")
        harness.login.authData = newAuth
        harness.panelPresenter.waitsForSignIn = true
        let coordinator = harness.makeCoordinator()
        coordinator.start()
        await coordinator.waitForPendingWork()

        harness.send(.addAccount, for: .codex)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Use s•••m@example.com for Codex?"])
        #expect(harness.alertPresenter.confirmationRequests.last?.informativeText.hasPrefix("s•••m@example.com replaces bu•••4@example.com on this Mac") == true)
        #expect(try harness.authFile.read() != newAuth)

        harness.alertPresenter.confirmationResponse = true
        harness.send(.addAccount, for: .codex)
        await coordinator.waitForPendingWork()

        #expect(try harness.authFile.read() == newAuth)
        #expect(harness.accountsController.activeAccount?.email == "sam@example.com")
        #expect(harness.codexApp.relaunchCount == 1)
    }

    @Test
    func firstRunAsksToSignInToCodexOnlyWhenNoToolIsConnected() async throws {
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

            #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == Array(repeating: "Sign in to Codex?", count: expectedPrompts))
        }
    }

    @Test
    func openingAMenuBuiltAWhileAgoRebuildsItSoCountdownsStartNow() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        let builtAt = Date(timeIntervalSince1970: 1_800_000_000)
        var clock = builtAt
        harness.makeActiveAccount(email: "personal@example.com")
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
    func signingOutOfCodexAsksFirstAndOnlyThenRemovesTheSignIn() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.makeActiveAccount(email: "personal@example.com")
        let coordinator = harness.makeCoordinator()
        coordinator.start()
        await coordinator.waitForPendingWork()

        harness.send(.signOut, for: .codex)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Sign Out of Codex?"])
        #expect(harness.alertPresenter.confirmationRequests.last?.informativeText == "This signs Codex out on this Mac, including the Codex app and CLI.")
        #expect(FileManager.default.fileExists(atPath: harness.authFile.url.path))
        #expect(harness.codexApp.relaunchCount == 0)

        harness.alertPresenter.confirmationResponse = true
        harness.send(.signOut, for: .codex)
        await coordinator.waitForPendingWork()

        #expect(!FileManager.default.fileExists(atPath: harness.authFile.url.path))
        #expect(harness.codexApp.relaunchCount == 1)
        #expect(cardAreaTitles(coordinator) == [])
    }

    @Test
    func removingAProviderAsksFirstThenStopsReadingIt() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.makeActiveAccount(email: "personal@example.com")
        let claude = ProviderConnectionProbe(provider: .claude, refreshInterval: 0, reading: .snapshot(UsageSnapshot(provider: .claude, planName: nil, windows: [], fetchedAt: Date())))
        let coordinator = harness.makeCoordinator(providerConnections: [claude])
        coordinator.start()
        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()
        #expect(cardAreaTitles(coordinator) == ["Claude", "", "Codex"])

        coordinator.removeProvider(.claude)
        coordinator.removeProvider(.codex)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Remove Claude from rusage?", "Remove Codex from rusage?"])
        #expect(harness.alertPresenter.confirmationRequests.last?.informativeText == "rusage stops showing Codex. Codex stays signed in on this Mac.")
        #expect(cardAreaTitles(coordinator) == ["Claude", "", "Codex"])

        harness.alertPresenter.confirmationResponse = true
        coordinator.removeProvider(.claude)
        coordinator.removeProvider(.codex)
        await coordinator.waitForPendingWork()

        #expect(cardAreaTitles(coordinator) == [])
        #expect(FileManager.default.fileExists(atPath: harness.authFile.url.path))
    }

    @Test
    func signingInWithoutTheCodexAppReplacesTheAccountAndSaysCodexWasNotRestarted() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.makeActiveAccount(email: "personal@example.com")
        let workAuth = makeCodexAuthData(email: "work@example.com", accountID: "acct-2", userID: "user-2")
        harness.login.authData = workAuth
        harness.panelPresenter.waitsForSignIn = true
        harness.codexApp.relaunchResult = .appNotFound
        harness.alertPresenter.confirmationResponse = true
        let coordinator = harness.makeCoordinator()
        coordinator.start()
        await coordinator.waitForPendingWork()

        harness.send(.addAccount, for: .codex)
        await coordinator.waitForPendingWork()

        #expect(try harness.authFile.read() == workAuth)
        #expect(harness.alertPresenter.infoRequests.map(\.messageText) == ["Codex app not found"])
        #expect(harness.alertPresenter.infoRequests.map(\.informativeText) == ["Signed in. Codex uses the account when it opens."])
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

        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .claude, status: .notConnected, ownSignIn: .signedOut)])
        #expect(cardAreaTitles(coordinator) == [])

        harness.toggleTool(.claude)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Connect Claude Code?"])
        #expect(fixture.settings.value.isConnected == false)
        #expect(fixture.keychainReadPrompts == [])

        harness.alertPresenter.confirmationResponse = true
        harness.toggleTool(.claude)
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

        harness.toggleTool(.claude)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.count == 2)
        #expect(fixture.settings.value.isConnected == false)
        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .claude, status: .notConnected, ownSignIn: .signedOut)])
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

        harness.toggleTool(.cursor)
        await coordinator.waitForPendingWork()

        #expect(harness.alertPresenter.confirmationRequests.map(\.messageText) == ["Connect Cursor?"])
        #expect(fixture.settings.value.isConnected == false)
        #expect(fixture.requestCount == 0)

        harness.alertPresenter.confirmationResponse = true
        harness.toggleTool(.cursor)
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

        harness.toggleTool(.cursor)
        await coordinator.waitForPendingWork()

        #expect(fixture.settings.value.isConnected == false)
        #expect(coordinator.menuState().providerUsage == [ProviderUsageState(provider: .cursor, status: .notConnected)])
        #expect(cardAreaTitles(coordinator) == [])
    }

    @Test
    func showToolsHidesAToolsCardAndStopsReadingItUntilCheckedAgain() async throws {
        let harness = try MenuBarCoordinatorHarness()
        defer { harness.tearDown() }
        harness.alertPresenter.confirmationResponse = true
        harness.makeActiveAccount(email: "business-4@example.com")
        let codexReads = CountingAccountStatusClient()
        let claude = ProviderConnectionProbe(provider: .claude, refreshInterval: 0, reading: .snapshot(UsageSnapshot(provider: .claude, planName: nil, windows: [], fetchedAt: Date())))
        let coordinator = harness.makeCoordinator(providerConnections: [claude], accountStatusClient: codexReads)
        coordinator.start()
        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()
        #expect(cardAreaTitles(coordinator) == ["Claude", "", "Codex"])

        harness.toggleTool(.claude)
        harness.toggleTool(.codex)
        await coordinator.waitForPendingWork()
        let (claudeReads, codexReadsWhenHidden) = (claude.readCount, codexReads.readCount)
        await coordinator.performScheduledRefresh()
        await coordinator.waitForPendingWork()

        #expect(cardAreaTitles(coordinator) == [])
        #expect(claude.readCount == claudeReads)
        #expect(codexReads.readCount == codexReadsWhenHidden)
        #expect(!harness.settings.codex.isConnected)

        harness.toggleTool(.codex)
        harness.toggleTool(.claude)
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
        harness.makeActiveAccount(email: "personal@example.com")
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

    /// The main menu's titles above Settings…: the cards and their follow-up rows.
    private func cardAreaTitles(_ coordinator: MenuBarCoordinator) -> [String] {
        let titles = MenuBarMenuBuilder().makeMenu(state: coordinator.menuState(), target: coordinator).items.map(\.title)
        var cardArea = Array(titles.prefix { $0 != "Settings…" })
        if cardArea.last == "" {
            cardArea.removeLast()
        }
        return cardArea
    }
}

@MainActor
private final class MenuBarCoordinatorHarness {
    let authFile = makeCodexAuthFile()
    let settings: SettingsModel
    let alertPresenter = AlertPresenterProbe()
    let panelPresenter = PanelPresenterProbe()
    let codexApp = CodexAppProcessProbe()
    let login = IsolatedCodexLoginProbe(authData: Data())
    private(set) var accountsController: AccountsController!
    private var coordinator: MenuBarCoordinator?
    private let suiteName = "MenuBarCoordinatorTests-\(UUID().uuidString)"
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init() throws {
        settings = SettingsModel(userDefaults: UserDefaults(suiteName: suiteName)!)
    }

    func makeCoordinator(
        providerConnections: [any ProviderConnection] = [],
        allowsEmptyStatePrompt: Bool = false,
        accountStatusClient: CodexAccountStatusClient = DisabledAccountStatusClient(),
        resetCreditClient: CodexResetCreditClient = UnavailableResetCreditClient(),
        now: @escaping () -> Date = Date.init
    ) -> MenuBarCoordinator {
        accountsController = AccountsController(
            authFile: authFile,
            accountStatusClient: accountStatusClient,
            signInWorkflow: CodexSignInWorkflow(authFile: authFile, isolatedLoginClient: login, codexAppProcessClient: codexApp),
            resetCreditClient: resetCreditClient,
            postSignInRefreshDelay: .zero
        )
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

    /// Signs Codex in on this Mac to `email`.
    func makeActiveAccount(email: String) {
        try! authFile.write(makeCodexAuthData(email: email))
    }

    var menu: NSMenu? { statusItem.menu }

    /// Sends a tool action the way a menu item carrying it would.
    func send(_ action: ProviderAction, for provider: UsageProvider) {
        let item = NSMenuItem()
        item.representedObject = ProviderMenuAction(provider: provider, action: action)
        coordinator?.performProviderAction(item)
    }

    /// Flips a tool's switch in Settings › Tools, as the user would from what the menu shows now.
    func toggleTool(_ provider: UsageProvider) {
        guard let coordinator else { return }
        let isShown = coordinator.menuState().toolSections.contains { $0.provider == provider }
        coordinator.setTool(provider, shown: !isShown)
    }

    /// Clicks the enabled item at `path`, such as "Claude", "Move Down", in the menu the coordinator would build now.
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
        try? FileManager.default.removeItem(at: authFile.url.deletingLastPathComponent())
    }
}
