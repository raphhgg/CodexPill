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

    func makeCoordinator(providerUsageSources: [any UsageProviderSource] = []) -> MenuBarCoordinator {
        accountsController = AccountsFeatureFactory(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: CodexAppProcessProbe(),
            accountStatusClient: DisabledAccountStatusClient(),
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
