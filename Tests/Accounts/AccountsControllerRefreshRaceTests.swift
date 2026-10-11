import Foundation
import Testing

@testable import CodexPill

@MainActor
struct AccountsControllerRefreshRaceTests {
    @Test
    func removingAnAccountDuringAnInactiveRefreshKeepsItRemoved() async {
        let fixture = RefreshRaceFixture()
        let controller = fixture.makeController()
        controller.load()

        let refresh = Task { await controller.refreshInactiveSavedAccountsMetadata() }
        await fixture.statusClient.waitUntilReading()
        let remove = await startOperation(on: controller) { await controller.removeSavedAccount(fixture.backup) }
        await fixture.statusClient.finishRead(status: .success(fixture.refreshedStatus), rotatedAuthData: nil)
        await remove.value
        await refresh.value

        #expect(controller.accounts.map(\.id) == [fixture.personal.id])
        #expect(fixture.catalog.savedAccounts.map(\.id) == [fixture.personal.id])
    }

    @Test
    func switchingToAnAccountDuringAnInactiveRefreshActivatesItsRotatedAuth() async {
        let fixture = RefreshRaceFixture()
        let controller = fixture.makeController()
        controller.load()

        let refresh = Task { await controller.refreshInactiveSavedAccountsMetadata() }
        await fixture.statusClient.waitUntilReading()
        let switchToBackup = await startOperation(on: controller) { _ = await controller.switchToAccount(fixture.backup) }
        await fixture.statusClient.finishRead(
            status: .failure(RefreshRaceFailure.readFailed),
            rotatedAuthData: Data("backup:2".utf8)
        )
        await switchToBackup.value
        await refresh.value

        #expect(fixture.authStore.liveAuth == "backup:2")
        #expect(fixture.authStore.snapshot(for: fixture.backup) == "backup:2")
        #expect(controller.activeAccountID == fixture.backup.id)
    }

    @Test
    func switchingAwaySavesTheActiveAccountsRotatedLiveAuth() async throws {
        let fixture = RefreshRaceFixture()
        fixture.authStore.liveAuth = "personal:2"
        let controller = fixture.makeController()
        controller.load()

        _ = await controller.switchToAccount(fixture.backup)

        let personal = try #require(controller.accounts.first(where: { $0.id == fixture.personal.id }))
        #expect(fixture.authStore.snapshot(for: fixture.personal) == "personal:2")
        #expect(personal.identity.snapshotFingerprint == "personal:2")
        #expect(fixture.authStore.liveAuth == "backup:1")
        #expect(controller.activeAccountID == fixture.backup.id)
    }

    @Test
    func removingAnAccountDuringAnActiveRefreshKeepsItRemoved() async throws {
        let fixture = RefreshRaceFixture()
        await fixture.activeStatusClient.holdReads()
        let controller = fixture.makeController()
        controller.load()

        let refresh = Task { await controller.refreshAccountData(for: fixture.personal) }
        await fixture.activeStatusClient.waitUntilReading()
        await controller.removeSavedAccount(fixture.backup)
        await fixture.activeStatusClient.finishRead(with: fixture.refreshedStatus)
        #expect(await refresh.value == .refreshed)

        let personal = try #require(controller.accounts.first(where: { $0.id == fixture.personal.id }))
        #expect(controller.accounts.map(\.id) == [fixture.personal.id])
        #expect(fixture.catalog.savedAccounts.map(\.id) == [fixture.personal.id])
        #expect(personal.usage?.window(.session)?.usedPercent == 70)
        #expect(controller.activeAccountID == fixture.personal.id)
    }

    @Test
    func switchingAccountsDuringAnActiveRefreshKeepsTheNewAccountActive() async throws {
        let fixture = RefreshRaceFixture()
        await fixture.activeStatusClient.holdReads()
        let controller = fixture.makeController()
        controller.load()

        let refresh = Task { await controller.refreshAccountData(for: fixture.personal) }
        await fixture.activeStatusClient.waitUntilReading(count: 1)
        let switchToBackup = Task { _ = await controller.switchToAccount(fixture.backup) }
        await fixture.activeStatusClient.waitUntilReading(count: 2)
        await fixture.activeStatusClient.finishRead(with: fixture.refreshedStatus)
        await switchToBackup.value
        await fixture.activeStatusClient.finishRead(with: fixture.personalStatus)
        #expect(await refresh.value == .refreshed)

        let personal = try #require(controller.accounts.first(where: { $0.id == fixture.personal.id }))
        let backup = try #require(controller.accounts.first(where: { $0.id == fixture.backup.id }))
        #expect(controller.activeAccountID == fixture.backup.id)
        #expect(fixture.authStore.liveAuth == "backup:1")
        #expect(fixture.authStore.snapshots == [fixture.personal.id: "personal:1", fixture.backup.id: "backup:1"])
        #expect(personal.usage?.window(.session)?.usedPercent == 20)
        #expect(backup.usage?.window(.session)?.usedPercent == 70)
    }

    @Test
    func removingTheActiveAccountDuringAnActiveRefreshLeavesNoSnapshotForIt() async {
        let fixture = RefreshRaceFixture()
        fixture.authStore.liveAuth = "personal:2"
        await fixture.activeStatusClient.holdReads()
        let controller = fixture.makeController()
        controller.load()

        let refresh = Task { await controller.refreshAccountData(for: fixture.personal) }
        await fixture.activeStatusClient.waitUntilReading()
        await controller.removeSavedAccount(fixture.personal)
        await fixture.activeStatusClient.finishRead(with: fixture.refreshedStatus)
        _ = await refresh.value

        #expect(fixture.authStore.snapshots == [fixture.backup.id: "backup:1"])
        #expect(controller.accounts.map(\.id) == [fixture.backup.id])
        #expect(fixture.catalog.savedAccounts.map(\.id) == [fixture.backup.id])
    }

    private func startOperation(
        on controller: AccountsController,
        _ operation: @escaping @MainActor () async -> Void
    ) async -> Task<Void, Never> {
        let finished = OperationFinished()
        let task = Task {
            await operation()
            finished.value = true
        }
        while !controller.isBusy, !finished.value {
            await Task.yield()
        }
        return task
    }
}

@MainActor
private final class OperationFinished {
    var value = false
}

private enum RefreshRaceFailure: Error {
    case readFailed
}

@MainActor
private final class RefreshRaceFixture {
    let personal = makeRaceAccount(stableAccountID: "personal")
    let backup = makeRaceAccount(stableAccountID: "backup")
    let authStore = InMemoryCodexAuthStore()
    let statusClient = SuspendedSavedStatusClient()
    let activeStatusClient = SuspendedActiveStatusClient()
    let catalog: InMemoryAccountCatalog
    let refreshedStatus = makeRaceStatus(email: "backup@example.com", primaryUsedPercent: 70)
    let personalStatus = makeRaceStatus(email: "personal@example.com", primaryUsedPercent: 20)

    init() {
        catalog = InMemoryAccountCatalog(accounts: [personal, backup], authStore: authStore)
        authStore.liveAuth = "personal:1"
        authStore.snapshots = [personal.id: "personal:1", backup.id: "backup:1"]
    }

    func makeController() -> AccountsController {
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: authStore,
            storedAccountReconciler: RaceStoredIdentityAdapter()
        )
        let refreshActiveAccountUseCase = RefreshActiveAccountUseCase(
            accountStatusClient: activeStatusClient,
            identityResolver: identityResolver,
            repository: catalog,
            activeAuthSnapshotRelinker: authStore
        )
        return AccountsController(
            identityResolver: identityResolver,
            loadAccountsUseCase: LoadAccountsUseCase(repository: catalog, identityResolver: identityResolver),
            refreshActiveAccountUseCase: refreshActiveAccountUseCase,
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: authStore,
                savedAccountStatusClient: statusClient,
                repository: catalog
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(repository: catalog, identityResolver: identityResolver),
            accountCatalogStore: catalog,
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: authStore,
                repository: catalog,
                codexAppProcessClient: RaceCodexAppProcessClient(),
                identityResolver: identityResolver
            ),
            addAccountWorkflow: AddAccountWorkflow(
                authService: authStore,
                repository: catalog,
                identityResolver: identityResolver
            ),
            postSwitchRefreshDelay: .zero
        )
    }
}

private func makeRaceAccount(stableAccountID: String) -> CodexAccount {
    let id = UUID()
    return CodexAccount(
        id: id,
        snapshotFileName: "\(id.uuidString).json",
        createdAt: .distantPast,
        updatedAt: .distantPast,
        email: nil,
        planType: nil,
        usage: nil,
        identity: CodexAccountIdentity(
            stableAccountID: stableAccountID,
            snapshotFingerprint: "\(stableAccountID):1"
        )
    )
}

private func makeRaceStatus(email: String, primaryUsedPercent: Int) -> CodexAccountStatus {
    CodexAccountStatus(
        email: email,
        planType: "pro",
        usage: UsageSnapshot.codex(
            planName: "pro",
            primary: (usedPercent: primaryUsedPercent, resetsAt: Date(timeIntervalSince1970: 1_776_256_138), durationMinutes: 300),
            secondary: (usedPercent: 30, resetsAt: Date(timeIntervalSince1970: 1_776_842_938), durationMinutes: 10_080),
            fetchedAt: Date(timeIntervalSince1970: 1_776_300_000)
        )
    )
}

// Auth payloads are "<stable account id>:<token version>", so a rotation bumps the version.
private final class InMemoryCodexAuthStore: CodexAuthSessionStore, CodexSignInAuthStore, ActiveAuthSnapshotRelinking,
    LiveCodexAccountIdentitySource, @unchecked Sendable {
    private let lock = NSLock()
    private var storedLiveAuth = ""
    private var storedSnapshots: [UUID: String] = [:]

    var liveAuth: String {
        get { lock.withLock { storedLiveAuth } }
        set { lock.withLock { storedLiveAuth = newValue } }
    }

    var snapshots: [UUID: String] {
        get { lock.withLock { storedSnapshots } }
        set { lock.withLock { storedSnapshots = newValue } }
    }

    func snapshot(for account: CodexAccount) -> String? {
        snapshots[account.id]
    }

    func activate(_ account: CodexAccount) throws {
        liveAuth = try String(decoding: readAuthSnapshot(for: account), as: UTF8.self)
    }

    func readCurrentAuthData() throws -> Data { Data(liveAuth.utf8) }
    func restoreCurrentAuthData(_ data: Data) throws { liveAuth = String(decoding: data, as: UTF8.self) }
    func currentAuthFingerprint() -> String? { liveAuth }

    func readAuthSnapshot(for account: CodexAccount) throws -> Data {
        guard let snapshot = snapshot(for: account) else { throw CocoaError(.fileNoSuchFile) }
        return Data(snapshot.utf8)
    }

    func saveAuthSnapshot(_ authData: Data, existing: CodexAccount?) throws -> CodexAccount {
        var account = try #require(existing)
        let payload = String(decoding: authData, as: UTF8.self)
        account.identity.snapshotFingerprint = payload
        snapshots[account.id] = payload
        return account
    }

    func replaceAuthSnapshot(_ authData: Data, ifUnchangedFrom expected: Data, for account: CodexAccount) throws -> CodexAccount? {
        guard try readAuthSnapshot(for: account) == expected else { return nil }
        return try saveAuthSnapshot(authData, existing: account)
    }

    func deleteAuthSnapshot(for account: CodexAccount) throws {
        snapshots[account.id] = nil
    }

    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity {
        let payload = String(decoding: authData, as: UTF8.self)
        return LiveCodexAccountIdentity(
            stableAccountID: payload.split(separator: ":").first.map(String.init),
            snapshotFingerprint: payload
        )
    }

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        liveIdentity(forAuthData: Data(liveAuth.utf8))
    }
}

private actor SuspendedSavedStatusClient: SavedCodexAccountStatusClient {
    private var pendingRead: CheckedContinuation<SavedCodexAccountStatusRead, Never>?
    private var readStarted: CheckedContinuation<Void, Never>?

    func readSavedAccountStatus(authData: Data) async -> SavedCodexAccountStatusRead {
        await withCheckedContinuation { continuation in
            pendingRead = continuation
            readStarted?.resume()
            readStarted = nil
        }
    }

    func waitUntilReading() async {
        guard pendingRead == nil else { return }
        await withCheckedContinuation { readStarted = $0 }
    }

    func finishRead(status: Result<CodexAccountStatus, Error>, rotatedAuthData: Data?) {
        pendingRead?.resume(returning: SavedCodexAccountStatusRead(status: status, rotatedAuthData: rotatedAuthData))
        pendingRead = nil
    }
}

private final class InMemoryAccountCatalog: AccountCatalogLoader, AccountSnapshotRemover, @unchecked Sendable {
    private let lock = NSLock()
    private var accounts: [CodexAccount]
    private let authStore: InMemoryCodexAuthStore

    init(accounts: [CodexAccount], authStore: InMemoryCodexAuthStore) {
        self.accounts = accounts
        self.authStore = authStore
    }

    var savedAccounts: [CodexAccount] {
        lock.withLock { accounts }
    }

    func bootstrapStorage() throws {}
    func loadAccounts() throws -> [CodexAccount] { savedAccounts }
    func saveAccounts(_ accounts: [CodexAccount]) throws { lock.withLock { self.accounts = accounts } }
    func deleteSnapshot(for account: CodexAccount) throws { try authStore.deleteAuthSnapshot(for: account) }
}

// Fails reads until a test holds them, so switch tests skip the post-switch refresh.
// `finishRead` resumes the most recent held read.
private actor SuspendedActiveStatusClient: CodexAccountStatusClient {
    private var isHoldingReads = false
    private var pendingReads: [CheckedContinuation<CodexAccountStatus, Never>] = []
    private var readWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func holdReads() {
        isHoldingReads = true
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        guard isHoldingReads else { throw RefreshRaceFailure.readFailed }
        return await withCheckedContinuation { continuation in
            pendingReads.append(continuation)
            let ready = readWaiters.filter { $0.count <= pendingReads.count }
            readWaiters.removeAll { $0.count <= pendingReads.count }
            ready.forEach { $0.continuation.resume() }
        }
    }

    func waitUntilReading(count: Int = 1) async {
        guard pendingReads.count < count else { return }
        await withCheckedContinuation { readWaiters.append((count, $0)) }
    }

    func finishRead(with status: CodexAccountStatus) {
        pendingReads.popLast()?.resume(returning: status)
    }
}

private struct RaceCodexAppProcessClient: CodexAppProcessClient {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}

private struct RaceStoredIdentityAdapter: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
