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
        #expect(harness.menuActions.map(\.name) == ["switchAccountOnHost"])
        #expect(harness.validationSink.events.contains { $0.event == "remote_host_active_account_changed" })
    }

    @Test
    func addHostInstallsActiveAccountWhenUserAcceptsInstallPrompt() async throws {
        let account = makeAccount(name: "Business", email: "business@example.com")
        let host = RemoteHost(destination: "user@buildbox", displayName: "Buildbox")
        let panelPresenter = PanelPresenterProbe()
        panelPresenter.hostSetupResponse = host
        let alertPresenter = AlertPresenterProbe()
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
        let alertPresenter = AlertPresenterProbe()
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
        #expect(harness.validationSink.events.contains { $0.event == "remote_host_reverify_succeeded" })
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
        remoteHostClient: RemoteHostConnectionChecking & RemoteHostAccountStatusReading = RemoteHostClientFixture(),
        alertPresenter: AlertPresenterProbe? = nil,
        panelPresenter: PanelPresenterProbe? = nil
    ) -> MenuBarHostActionCoordinatorHarness {
        MenuBarHostActionCoordinatorHarness(
            accounts: accounts,
            activeAccount: activeAccount,
            remoteHostClient: remoteHostClient,
            alertPresenter: alertPresenter ?? AlertPresenterProbe(),
            panelPresenter: panelPresenter ?? PanelPresenterProbe()
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
    private(set) var rebuildCount = 0
    private(set) var cancelMenuTrackingCount = 0
    let validationSink = ValidationSinkProbe()

    private let suiteName = "MenuBarHostActionCoordinatorTests-\(UUID().uuidString)"

    init(
        accounts: [CodexAccount],
        activeAccount: CodexAccount?,
        remoteHostClient: RemoteHostConnectionChecking & RemoteHostAccountStatusReading,
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter
    ) {
        store = MenuBarHostActionStoreProbe(accounts: accounts, activeAccount: activeAccount)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = CodexPillSettingsStore(userDefaults: defaults)
        let remoteHostRuntime = RemoteHostRuntime(
            settings: settings.remoteHostSettings,
            accountStatusReader: remoteHostClient,
            accounts: { [self] in store.accounts },
            persistAccountMetadata: { [self] in store.persistedAccounts.append($0) },
            markAccountActivated: { [self] in store.activatedAccountIDs.append($0) }
        )
        coordinator = MenuBarHostActionCoordinator(
            store: store,
            settings: settings,
            connectionChecker: remoteHostClient,
            remoteHostRuntime: remoteHostRuntime,
            alertPresenter: alertPresenter,
            panelPresenter: panelPresenter,
            alertFactory: MenuBarAlertFactory(),
            validationObserver: MenuBarValidationObserver(
                sink: validationSink,
                scenario: "host-action-coordinator-tests"
            ),
            recordMenuAction: { [weak self] name, payload in
                self?.menuActions.append(MenuActionRecord(name: name, payload: payload))
            },
            rebuildMenu: { [weak self] in
                self?.rebuildCount += 1
            },
            cancelMenuTracking: { [weak self] in
                self?.cancelMenuTrackingCount += 1
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

private struct RemoteHostClientFixture: RemoteHostConnectionChecking, RemoteHostAccountStatusReading {
    var status = CodexAccountStatus(email: "business@example.com", planType: "team")

    func testConnection(to host: RemoteHost) async throws {}
    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        status
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
