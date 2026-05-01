import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarHostActionCoordinatorTests {
    @Test
    func switchAccountOnHostSequencesRuntimeSwitchAndValidationCallbacks() async throws {
        let account = makeAccount(name: "Business", email: "business@example.com")
        let host = RemoteHost(destination: "user@buildbox", displayName: "Buildbox")
        let harness = makeHarness(accounts: [account])
        harness.settings.remoteHostStates = [PersistedRemoteHostState(host: host)]
        harness.store.remoteSwitchOutcome = .verified(CodexAccountStatus(email: account.email, planType: "team"))

        harness.coordinator.switchAccountOnHost(accountID: account.id, hostDestination: host.destination)
        await harness.waitForRebuildCount(atLeast: 2)

        #expect(harness.store.switchCalls == [RemoteSwitchCall(account: account, host: host)])
        let hostState = try #require(harness.settings.remoteHostState(for: host.destination))
        #expect(hostState.desiredAccountID == account.id)
        #expect(hostState.verifiedAccount?.id == account.id)
        #expect(hostState.verificationStatus == .verified)
        #expect(harness.lastSwitchTargetName == account.name)
        #expect(harness.menuActions.map(\.name) == ["switchAccountOnHost"])
        #expect(harness.validationEvents.contains { $0.name == "remote_host_active_account_changed" })
    }

    @Test
    func addHostInstallsActiveAccountWhenUserAcceptsInstallPrompt() async throws {
        let account = makeAccount(name: "Business", email: "business@example.com")
        let host = RemoteHost(destination: "user@buildbox", displayName: "Buildbox")
        let panelPresenter = MenuBarPanelPresenterProbe()
        panelPresenter.hostSetupResponse = host
        let alertPresenter = MenuBarAlertPresenterProbe()
        alertPresenter.confirmationResponse = true
        let harness = makeHarness(
            accounts: [account],
            activeAccount: account,
            alertPresenter: alertPresenter,
            panelPresenter: panelPresenter
        )
        harness.store.remoteSwitchOutcome = .verified(CodexAccountStatus(email: account.email, planType: "team"))

        harness.coordinator.addHost()
        await harness.waitForRebuildCount(atLeast: 2)

        #expect(panelPresenter.hostSetupRequests.count == 1)
        #expect(alertPresenter.confirmationRequests.count == 1)
        #expect(harness.store.switchCalls == [RemoteSwitchCall(account: account, host: host)])
        let hostState = try #require(harness.settings.remoteHostState(for: host.destination))
        #expect(hostState.installedAccountIDs == [account.id])
        #expect(hostState.verifiedAccount?.id == account.id)
        #expect(hostState.verificationStatus == .verified)
    }

    @Test
    func removeHostConfirmsThenRemovesConfiguredHost() throws {
        let host = RemoteHost(destination: "user@buildbox", displayName: "Buildbox")
        let alertPresenter = MenuBarAlertPresenterProbe()
        alertPresenter.confirmationResponse = true
        let harness = makeHarness(alertPresenter: alertPresenter)
        harness.settings.remoteHostStates = [PersistedRemoteHostState(host: host)]

        harness.coordinator.removeHost(hostDestination: host.destination)

        #expect(alertPresenter.confirmationRequests.count == 1)
        #expect(harness.settings.remoteHostState(for: host.destination) == nil)
        #expect(harness.rebuildCount == 1)
        #expect(harness.menuActions.map(\.name) == ["removeHost"])
    }

    @Test
    func reverifyHostRefreshesFromRemoteStatus() async throws {
        let account = makeAccount(name: "Business", email: "business@example.com")
        let host = RemoteHost(destination: "user@buildbox", displayName: "Buildbox")
        let remoteHostClient = RemoteHostClientFixture(status: CodexAccountStatus(email: account.email, planType: "team"))
        let harness = makeHarness(accounts: [account], remoteHostClient: remoteHostClient)
        harness.settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: host,
                installedAccountIDs: [account.id],
                desiredAccountID: account.id,
                verifiedAccount: account
            )
        ]

        harness.coordinator.reverifyHost(hostDestination: host.destination)
        await harness.waitForRebuildCount(atLeast: 2)

        let hostState = try #require(harness.settings.remoteHostState(for: host.destination))
        #expect(hostState.verificationStatus == .verified)
        #expect(hostState.verifiedAccount?.id == account.id)
        #expect(harness.cancelMenuTrackingCount == 1)
        #expect(harness.validationEvents.contains { $0.name == "remote_host_reverify_succeeded" })
    }

    @Test
    func adoptDetectedRemoteAccountRefreshesUsingDetectedAccount() async throws {
        let desiredAccount = makeAccount(name: "Personal", email: "personal@example.com")
        let detectedAccount = makeAccount(name: "Business", email: "business@example.com")
        let host = RemoteHost(destination: "user@buildbox", displayName: "Buildbox")
        let remoteHostClient = RemoteHostClientFixture(status: CodexAccountStatus(email: detectedAccount.email, planType: "team"))
        let harness = makeHarness(accounts: [desiredAccount, detectedAccount], remoteHostClient: remoteHostClient)
        harness.settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: host,
                installedAccountIDs: [desiredAccount.id, detectedAccount.id],
                desiredAccountID: desiredAccount.id,
                verifiedAccount: nil,
                detectedAccountID: detectedAccount.id,
                verificationStatus: .failed,
                lastVerificationError: "Remote account differs."
            )
        ]

        harness.coordinator.adoptDetectedRemoteAccount(
            hostDestination: host.destination,
            accountID: detectedAccount.id
        )
        await harness.waitForRebuildCount(atLeast: 2)

        let hostState = try #require(harness.settings.remoteHostState(for: host.destination))
        #expect(hostState.desiredAccountID == detectedAccount.id)
        #expect(hostState.verifiedAccount?.id == detectedAccount.id)
        #expect(hostState.detectedAccountID == nil)
        #expect(hostState.verificationStatus == .verified)
        #expect(harness.cancelMenuTrackingCount == 1)
        #expect(harness.menuActions.map(\.name) == ["adoptDetectedRemoteAccount"])
    }

    private func makeHarness(
        accounts: [CodexAccount] = [],
        activeAccount: CodexAccount? = nil,
        remoteHostClient: RemoteHostClient = RemoteHostClientFixture(),
        alertPresenter: MenuBarAlertPresenterProbe? = nil,
        panelPresenter: MenuBarPanelPresenterProbe? = nil
    ) -> MenuBarHostActionCoordinatorHarness {
        MenuBarHostActionCoordinatorHarness(
            accounts: accounts,
            activeAccount: activeAccount,
            remoteHostClient: remoteHostClient,
            alertPresenter: alertPresenter ?? MenuBarAlertPresenterProbe(),
            panelPresenter: panelPresenter ?? MenuBarPanelPresenterProbe()
        )
    }

    private func makeAccount(name: String, email: String) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(name).json",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            email: email,
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email))
        )
    }
}

@MainActor
private final class MenuBarHostActionCoordinatorHarness {
    let store: MenuBarHostActionStoreProbe
    let settings: CodexPillSettingsStore
    var coordinator: MenuBarHostActionCoordinator!

    private(set) var menuActions: [MenuActionRecord] = []
    private(set) var validationEvents: [ValidationEventRecord] = []
    private(set) var rebuildCount = 0
    private(set) var cancelMenuTrackingCount = 0
    private(set) var lastSwitchTargetName: String?

    private let suiteName = "MenuBarHostActionCoordinatorTests-\(UUID().uuidString)"

    init(
        accounts: [CodexAccount],
        activeAccount: CodexAccount?,
        remoteHostClient: RemoteHostClient,
        alertPresenter: MenuBarAlertPresenter,
        panelPresenter: MenuBarPanelPresenter
    ) {
        store = MenuBarHostActionStoreProbe(accounts: accounts, activeAccount: activeAccount)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = CodexPillSettingsStore(userDefaults: defaults)
        let remoteHostRuntime = RemoteHostRuntime(
            settings: settings.remoteHostSettings,
            remoteHostClient: remoteHostClient,
            accounts: { [self] in store.accounts },
            persistAccountMetadata: { [self] in store.persistedAccounts.append($0) },
            markAccountActivated: { [self] in store.activatedAccountIDs.append($0) }
        )
        coordinator = MenuBarHostActionCoordinator(
            store: store,
            settings: settings,
            remoteHostClient: remoteHostClient,
            remoteHostRuntime: remoteHostRuntime,
            alertPresenter: alertPresenter,
            panelPresenter: panelPresenter,
            alertFactory: MenuBarAlertFactory(),
            sealValidationRun: nil,
            recordMenuAction: { [weak self] name, payload in
                self?.menuActions.append(MenuActionRecord(name: name, payload: payload))
            },
            recordValidationEvent: { [weak self] name, step, invariantIds, payload in
                self?.validationEvents.append(
                    ValidationEventRecord(
                        name: name,
                        step: step,
                        invariantIds: invariantIds,
                        payload: payload
                    )
                )
            },
            rebuildMenu: { [weak self] in
                self?.rebuildCount += 1
            },
            cancelMenuTracking: { [weak self] in
                self?.cancelMenuTrackingCount += 1
            },
            setLastSwitchTargetName: { [weak self] name in
                self?.lastSwitchTargetName = name
            }
        )
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func waitForRebuildCount(atLeast expectedCount: Int) async {
        for _ in 0..<100 where rebuildCount < expectedCount {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class MenuBarHostActionStoreProbe: MenuBarHostActionAccountsStore {
    var accounts: [CodexAccount]
    var activeAccount: CodexAccount?
    var remoteSwitchOutcome: AccountsController.RemoteHostSwitchOutcome = .failed("Not configured.", hostReachable: false)
    private(set) var switchCalls: [RemoteSwitchCall] = []
    var persistedAccounts: [CodexAccount] = []
    var activatedAccountIDs: [UUID] = []

    init(accounts: [CodexAccount], activeAccount: CodexAccount?) {
        self.accounts = accounts
        self.activeAccount = activeAccount
    }

    func switchToAccountOnHost(
        _ account: CodexAccount,
        on host: RemoteHost
    ) async -> AccountsController.RemoteHostSwitchOutcome {
        switchCalls.append(RemoteSwitchCall(account: account, host: host))
        return remoteSwitchOutcome
    }
}

private struct RemoteSwitchCall: Equatable {
    let account: CodexAccount
    let host: RemoteHost
}

private struct MenuActionRecord: Equatable {
    let name: String
    let payload: [String: String]
}

private struct ValidationEventRecord: Equatable {
    let name: String
    let step: String
    let invariantIds: [String]
    let payload: [String: String]
}

private struct RemoteHostClientFixture: RemoteHostClient {
    var status = CodexAccountStatus(email: "business@example.com", planType: "team")

    func testConnection(to host: RemoteHost) async throws {}
    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState {
        .installed
    }
    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func signOut(on host: RemoteHost) async throws {}
    func refreshCodexAppServer(on host: RemoteHost) async throws {}
    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        status
    }
}
