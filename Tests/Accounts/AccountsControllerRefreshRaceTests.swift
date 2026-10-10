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

        #expect(controller.accounts.map(\.name) == ["Personal"])
        #expect(fixture.catalog.savedAccounts.map(\.name) == ["Personal"])
    }

    @Test
    func renamingAnAccountDuringAnInactiveRefreshKeepsTheNewNameAndTheRefreshedLimits() async throws {
        let fixture = RefreshRaceFixture()
        let controller = fixture.makeController()
        controller.load()

        let refresh = Task { await controller.refreshInactiveSavedAccountsMetadata() }
        await fixture.statusClient.waitUntilReading()
        let rename = await startOperation(on: controller) { await controller.renameSavedAccount(fixture.backup, to: "Side project") }
        await fixture.statusClient.finishRead(status: .success(fixture.refreshedStatus), rotatedAuthData: nil)
        await rename.value
        await refresh.value

        let backup = try #require(controller.accounts.first(where: { $0.id == fixture.backup.id }))
        #expect(backup.name == "Side project")
        #expect(backup.rateLimits?.primary?.usedPercent == 70)
        #expect(fixture.catalog.savedAccounts.map(\.name) == ["Personal", "Side project"])
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
    let personal = makeRaceAccount(name: "Personal", stableAccountID: "personal")
    let backup = makeRaceAccount(name: "Backup", stableAccountID: "backup")
    let authStore = InMemoryCodexAuthStore()
    let statusClient = SuspendedSavedStatusClient()
    let catalog: InMemoryAccountCatalog
    let refreshedStatus = CodexAccountStatus(
        email: "backup@example.com",
        planType: "pro",
        rateLimits: CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "pro",
            primary: CodexRateLimitWindow(
                usedPercent: 70,
                resetsAt: Date(timeIntervalSince1970: 1_776_256_138),
                windowDurationMinutes: 300
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 30,
                resetsAt: Date(timeIntervalSince1970: 1_776_842_938),
                windowDurationMinutes: 10_080
            ),
            fetchedAt: Date(timeIntervalSince1970: 1_776_300_000)
        )
    )

    init() {
        catalog = InMemoryAccountCatalog(accounts: [personal, backup])
        authStore.liveAuth = "personal:1"
        authStore.snapshots = [personal.id: "personal:1", backup.id: "backup:1"]
    }

    func makeController() -> AccountsController {
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: authStore,
            storedAccountReconciler: RaceStoredIdentityAdapter()
        )
        let refreshActiveAccountUseCase = RefreshActiveAccountUseCase(
            accountStatusClient: RaceUnavailableAccountStatusClient(),
            identityResolver: identityResolver,
            repository: catalog,
            activeAuthSnapshotRelinker: authStore
        )
        return AccountsController(
            identityResolver: identityResolver,
            loadAccountsUseCase: LoadAccountsUseCase(repository: catalog, identityResolver: identityResolver),
            refreshActiveAccountUseCase: refreshActiveAccountUseCase,
            silentPostActionRefresh: SilentPostActionRefresh(
                refreshActiveAccountUseCase: refreshActiveAccountUseCase,
                delay: .zero
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: authStore,
                savedAccountStatusClient: statusClient,
                repository: catalog
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(repository: catalog, identityResolver: identityResolver),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: catalog),
            persistSavedAccountMetadataUseCase: PersistSavedAccountMetadataUseCase(repository: catalog),
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
            )
        )
    }
}

private func makeRaceAccount(name: String, stableAccountID: String) -> CodexAccount {
    let id = UUID()
    return CodexAccount(
        id: id,
        name: name,
        snapshotFileName: "\(id.uuidString).json",
        createdAt: .distantPast,
        updatedAt: .distantPast,
        email: nil,
        planType: nil,
        rateLimits: nil,
        identity: CodexAccountIdentity(
            stableAccountID: stableAccountID,
            snapshotFingerprint: "\(stableAccountID):1"
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

    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
        var account = try #require(existing)
        let payload = String(decoding: authData, as: UTF8.self)
        account.name = name
        account.identity.snapshotFingerprint = payload
        snapshots[account.id] = payload
        return account
    }

    func replaceAuthSnapshot(_ authData: Data, ifUnchangedFrom expected: Data, for account: CodexAccount) throws -> CodexAccount? {
        guard try readAuthSnapshot(for: account) == expected else { return nil }
        return try saveAuthSnapshot(authData, named: account.name, existing: account)
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

    init(accounts: [CodexAccount]) {
        self.accounts = accounts
    }

    var savedAccounts: [CodexAccount] {
        lock.withLock { accounts }
    }

    func bootstrapStorage() throws {}
    func loadAccounts() throws -> [CodexAccount] { savedAccounts }
    func saveAccounts(_ accounts: [CodexAccount]) throws { lock.withLock { self.accounts = accounts } }
    func deleteSnapshot(for account: CodexAccount) throws {}
}

private struct RaceUnavailableAccountStatusClient: CodexAccountStatusClient {
    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        throw RefreshRaceFailure.readFailed
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
