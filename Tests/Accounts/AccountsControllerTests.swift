import Foundation
import Testing

@testable import rusage

@MainActor
struct AccountsControllerTests {
    @Test
    func completeIsolatedAddAccountHydratesNewInactiveAccountMetadata() async throws {
        let active = makeAccount(name: "Personal", fingerprint: "live-fingerprint")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [active])
        let liveIdentity = LiveIdentityStub(fingerprint: "live-fingerprint")
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: liveIdentity,
            storedAccountReconciler: PassthroughIdentityReconciler()
        )
        let authService = IsolatedAddAccountAuthProbe(
            currentFingerprint: "live-fingerprint",
            capturedFingerprint: "backup-fingerprint"
        )
        let hydratedRateLimits = makeUsageSnapshot()
        let savedStatusClient = SavedAccountStatusFixture(statusBySnapshot: [
            "backup-fingerprint": CodexAccountStatus(
                email: "backup@example.com",
                planType: "free",
                usage: hydratedRateLimits
            )
        ])
        let loginSession = IsolatedAddAccountLoginSessionProbe(authData: Data("captured-auth".utf8))
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: authService,
            savedAccountStatusClient: savedStatusClient,
            isolatedLoginClient: IsolatedAddAccountLoginClientProbe(session: loginSession)
        )

        controller.load()
        let session = try await controller.startIsolatedAddAccountFlow()
        let savedAccount = try await controller.completeIsolatedAddAccount(session)

        let hydratedBackup = try #require(controller.accounts.first(where: { $0.id == savedAccount.id }))
        #expect(hydratedBackup.email == "backup@example.com")
        #expect(hydratedBackup.planType == "free")
        #expect(hydratedBackup.usage == hydratedRateLimits)
        #expect(savedStatusClient.readSnapshots == [Data("backup-fingerprint".utf8)])
        #expect(controller.activeAccountID == active.id)
        #expect(controller.isBusy == false)
    }

    @Test
    func startIsolatedAddAccountRejectsOverlapWithoutClearingActiveOperation() async throws {
        let active = makeAccount(name: "Personal", fingerprint: "live-fingerprint")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [active])
        let liveIdentity = LiveIdentityStub(fingerprint: "live-fingerprint")
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: liveIdentity,
            storedAccountReconciler: PassthroughIdentityReconciler()
        )
        let authService = IsolatedAddAccountAuthProbe(
            currentFingerprint: "live-fingerprint",
            capturedFingerprint: "backup-fingerprint"
        )
        let loginSession = IsolatedAddAccountLoginSessionProbe(authData: Data("captured-auth".utf8))
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: authService,
            isolatedLoginClient: IsolatedAddAccountLoginClientProbe(session: loginSession)
        )

        controller.load()
        _ = try await controller.startIsolatedAddAccountFlow()

        await #expect(throws: AccountsControllerError.operationAlreadyInProgress) {
            _ = try await controller.startIsolatedAddAccountFlow()
        }
        #expect(controller.isBusy)
        #expect(controller.statusMessage == "Adding account...")
    }

    @Test
    func completeIsolatedAddAccountAlreadySavedDoesNotQueueSecondPendingError() async throws {
        let existing = makeAccount(name: "Business 1", fingerprint: "captured-fingerprint")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [existing])
        let liveIdentity = LiveIdentityStub(fingerprint: "live-fingerprint")
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: liveIdentity,
            storedAccountReconciler: PassthroughIdentityReconciler()
        )
        let authService = IsolatedAddAccountAuthProbe(
            currentFingerprint: "live-fingerprint",
            capturedFingerprint: "captured-fingerprint"
        )
        let loginSession = IsolatedAddAccountLoginSessionProbe(authData: Data("captured-auth".utf8))
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: authService,
            isolatedLoginClient: IsolatedAddAccountLoginClientProbe(session: loginSession)
        )

        controller.load()
        let session = try await controller.startIsolatedAddAccountFlow()

        await #expect(throws: AddAccountWorkflowError.accountAlreadySaved(existing.id)) {
            _ = try await controller.completeIsolatedAddAccount(session)
        }

        #expect(controller.pendingErrorMessage == nil)
        #expect(controller.consumePendingErrorMessage() == nil)
        #expect(loginSession.cleanupCount == 1)
    }

    @Test
    func refreshAccountDataFailureDoesNotQueuePendingErrorMessage() async {
        let account = makeAccount(name: "Business 4", fingerprint: "live")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [account])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
            storedAccountReconciler: PassthroughIdentityReconciler()
        )
        let controller = AccountsController(
            identityResolver: identityResolver,
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                accountStatusClient: StubAccountStatusClient(error: TestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: NullAuthService(),
                savedAccountStatusClient: DisabledAccountStatusClient(),
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            accountCatalogStore: repository,
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: NullAuthService(),
                repository: repository,
                codexAppProcessClient: CodexAppProcessProbe(),
                identityResolver: identityResolver
            ),
            addAccountWorkflow: makeAddAccountWorkflow(
                repository: repository,
                identityResolver: identityResolver
            )
        )

        controller.load()
        let outcome = await controller.refreshAccountData(for: account)

        #expect(outcome == .failed("Background refresh failed."))
        #expect(controller.activeAccountID == account.id)
        #expect(controller.accounts == [account])
        #expect(controller.pendingErrorMessage == nil)
        #expect(controller.consumePendingErrorMessage() == nil)
    }

    @Test
    func refreshInactiveSavedAccountsMetadataRefreshesExistingRateLimits() async throws {
        let active = makeAccount(name: "Personal", fingerprint: "live-fingerprint")
        var inactive = makeAccount(name: "Backup", fingerprint: "backup-fingerprint")
        inactive.usage = makeUsageSnapshot()
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [active, inactive])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: LiveIdentityStub(fingerprint: "live-fingerprint"),
            storedAccountReconciler: PassthroughIdentityReconciler()
        )
        let authService = IsolatedAddAccountAuthProbe(
            currentFingerprint: "live-fingerprint",
            capturedFingerprint: "unused"
        )
        let refreshedRateLimits = UsageSnapshot.codex(
            planName: "pro",
            primary: (usedPercent: 70, resetsAt: Date(timeIntervalSince1970: 1_776_256_138), durationMinutes: 300),
            secondary: (usedPercent: 30, resetsAt: Date(timeIntervalSince1970: 1_776_842_938), durationMinutes: 10_080),
            fetchedAt: Date(timeIntervalSince1970: 1_776_300_000)
        )
        let savedStatusClient = SavedAccountStatusFixture(statusBySnapshot: [
            "backup-fingerprint": CodexAccountStatus(
                email: "backup@example.com",
                planType: "pro",
                usage: refreshedRateLimits
            )
        ])
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: authService,
            savedAccountStatusClient: savedStatusClient
        )

        controller.load()
        await controller.refreshInactiveSavedAccountsMetadata()

        let refreshedBackup = try #require(controller.accounts.first(where: { $0.id == inactive.id }))
        #expect(savedStatusClient.readSnapshots == [Data("backup-fingerprint".utf8)])
        #expect(refreshedBackup.usage == refreshedRateLimits)
        #expect(refreshedBackup.email == "backup@example.com")
        #expect(refreshedBackup.planType == "pro")
    }

    @Test
    func refreshInactiveSavedAccountsMetadataRunsAtMostEveryFifteenMinutes() async throws {
        let active = makeAccount(name: "Personal", fingerprint: "live-fingerprint")
        var inactive = makeAccount(name: "Backup", fingerprint: "backup-fingerprint")
        inactive.usage = makeUsageSnapshot()
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [active, inactive])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: LiveIdentityStub(fingerprint: "live-fingerprint"),
            storedAccountReconciler: PassthroughIdentityReconciler()
        )
        let savedStatusClient = SavedAccountStatusFixture(statusBySnapshot: [:])
        var now = Date(timeIntervalSince1970: 1_776_300_000)
        let controller = makeController(
            repository: repository,
            identityResolver: identityResolver,
            authService: IsolatedAddAccountAuthProbe(currentFingerprint: "live-fingerprint", capturedFingerprint: "unused"),
            savedAccountStatusClient: savedStatusClient,
            now: { now }
        )
        let backupSnapshot = Data("backup-fingerprint".utf8)

        controller.load()
        await controller.refreshInactiveSavedAccountsMetadata()
        now += 14 * 60
        await controller.refreshInactiveSavedAccountsMetadata()

        #expect(savedStatusClient.readSnapshots == [backupSnapshot])

        now += 60
        await controller.refreshInactiveSavedAccountsMetadata()

        #expect(savedStatusClient.readSnapshots == [backupSnapshot, backupSnapshot])
    }

    @Test
    func switchToAccountSkipsSilentRefreshWhenNoActiveAccountResolves() async {
        let account = makeAccount(name: "Business 4", fingerprint: "live")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [account])
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "other"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            authService: NullAuthService()
        )
        controller.load()

        let didRefresh = await controller.switchToAccount(account).didRefresh

        #expect(didRefresh == false)
        #expect(controller.activeAccountID == nil)
        #expect(controller.accounts == [account])
    }

    @Test
    func switchToAccountKeepsAccountsWhenSilentRefreshFails() async {
        let account = makeAccount(name: "Business 4", fingerprint: "live")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [account])
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            authService: NullAuthService()
        )
        controller.load()

        let didRefresh = await controller.switchToAccount(account).didRefresh

        #expect(didRefresh == false)
        #expect(controller.activeAccountID == account.id)
        #expect(controller.accounts == [account])
        #expect(controller.pendingErrorMessage == nil)
    }

    @Test
    func switchToAccountAppliesSilentRefreshResult() async {
        let account = makeAccount(email: "business@example.com", fingerprint: "live")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [account])
        let refreshedRateLimits = makeUsageSnapshot()
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            authService: NullAuthService(),
            accountStatusClient: StubAccountStatusClient(
                status: CodexAccountStatus(
                    email: "business@example.com",
                    planType: "pro",
                    usage: refreshedRateLimits
                )
            )
        )
        controller.load()

        let didRefresh = await controller.switchToAccount(account).didRefresh

        #expect(didRefresh == true)
        #expect(controller.accounts.count == 1)
        #expect(controller.accounts[0].planType == "pro")
        #expect(controller.accounts[0].usage == refreshedRateLimits)
        #expect(repository.savedAccounts == controller.accounts)
    }

    @Test
    func useResetCreditRefreshesLimitsAfterReset() async {
        let account = makeAccount(email: "business@example.com", fingerprint: "live")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [account])
        var refreshedUsage = makeUsageSnapshot()
        refreshedUsage.resetCredits = UsageResetCredits(availableCount: 1, credits: nil)
        let resetCredits = ResetCreditClientProbe(results: [.success(.reset)])
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            authService: NullAuthService(),
            accountStatusClient: StubAccountStatusClient(
                status: CodexAccountStatus(email: "business@example.com", planType: "pro", usage: refreshedUsage)
            ),
            resetCreditClient: resetCredits
        )
        controller.load()

        let result = await controller.useResetCredit()

        #expect(result == .reset)
        #expect(result.message == "Your Codex limits are reset.")
        #expect(controller.accounts[0].usage?.resetCredits == UsageResetCredits(availableCount: 1, credits: nil))
        #expect(repository.savedAccounts == controller.accounts)
    }

    @Test
    func useResetCreditRetriesWithTheSameKeyUntilCodexAnswers() async {
        let account = makeAccount(name: "Business 4", fingerprint: "live")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [account])
        let resetCredits = ResetCreditClientProbe(results: [
            .failure(TestFailure.backgroundRefreshFailed),
            .success(.alreadyRedeemed),
            .success(.noCredit),
        ])
        let keys = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        ]
        var nextKey = keys.makeIterator()
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            authService: NullAuthService(),
            resetCreditClient: resetCredits,
            makeIdempotencyKey: { nextKey.next()! }
        )
        controller.load()

        let failed = await controller.useResetCredit()
        let retried = await controller.useResetCredit()
        let nextAttempt = await controller.useResetCredit()

        #expect(failed == .failed)
        #expect(failed.message == "Couldn't use a reset. Try again.")
        #expect(retried == .reset)
        #expect(nextAttempt == .noCredit)
        #expect(nextAttempt.message == "No resets left on this account.")
        #expect(await resetCredits.receivedKeys == [keys[0], keys[0], keys[1]])
    }

    @Test
    func useResetCreditWithNothingToResetKeepsLimitsAsTheyAre() async {
        let account = makeAccount(name: "Business 4", fingerprint: "live", usage: makeUsageSnapshot())
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [account])
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            authService: NullAuthService(),
            accountStatusClient: StubAccountStatusClient(
                status: CodexAccountStatus(email: "business@example.com", planType: "pro", usage: makeUsage())
            ),
            resetCreditClient: ResetCreditClientProbe(results: [.success(.nothingToReset)])
        )
        controller.load()

        let result = await controller.useResetCredit()

        #expect(result == .nothingToReset)
        #expect(result.message == "Nothing to reset right now. Your reset is still available.")
        #expect(controller.accounts == [account])
    }

    private func makeAddAccountWorkflow(
        repository: AccountCatalogStore,
        identityResolver: SavedAccountIdentityResolver
    ) -> AddAccountWorkflow {
        AddAccountWorkflow(
            authService: NullAuthService(),
            repository: repository,
            identityResolver: identityResolver
        )
    }

    @Test
    func useResetCreditKeepsAnUnansweredAttemptPerAccount() async {
        let personal = makeAccount(name: "Personal", fingerprint: "personal")
        let work = makeAccount(name: "Work", fingerprint: "work")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [personal, work])
        let liveIdentity = SwitchableLiveIdentity(fingerprint: "personal")
        let resetCredits = ResetCreditClientProbe(results: [
            .failure(TestFailure.backgroundRefreshFailed),
            .success(.noCredit),
            .success(.reset),
        ])
        let keys = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        ]
        var nextKey = keys.makeIterator()
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: liveIdentity,
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            authService: NullAuthService(),
            resetCreditClient: resetCredits,
            makeIdempotencyKey: { nextKey.next()! }
        )
        controller.load()

        let personalFailed = await controller.useResetCredit()
        liveIdentity.fingerprint = "work"
        controller.refreshActiveAccount()
        let workAnswered = await controller.useResetCredit()
        liveIdentity.fingerprint = "personal"
        controller.refreshActiveAccount()
        let personalRetried = await controller.useResetCredit()

        #expect(personalFailed == .failed)
        #expect(workAnswered == .noCredit)
        #expect(personalRetried == .reset)
        #expect(await resetCredits.receivedKeys == [keys[0], keys[1], keys[0]])
    }

    @Test
    func switchingWaitsUntilAResetCreditFinishes() async {
        let personal = makeAccount(name: "Personal", fingerprint: "live")
        let work = makeAccount(name: "Work", fingerprint: "work")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [personal, work])
        let codexApp = CodexAppProcessProbe()
        let resetCredits = SuspendedResetCreditClient()
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            authService: NullAuthService(),
            codexAppProcessClient: codexApp,
            resetCreditClient: resetCredits
        )
        controller.load()

        let reset = Task { await controller.useResetCredit() }
        await resetCredits.waitUntilCalled()
        let switchedDuringReset = await controller.switchToAccount(work)

        #expect(controller.isApplyingResetCredit)
        #expect(switchedDuringReset == SwitchToAccountOutcome(didRefresh: false, relaunch: nil))
        #expect(codexApp.relaunchCount == 0)

        await resetCredits.answer(.nothingToReset)
        #expect(await reset.value == .nothingToReset)
        _ = await controller.switchToAccount(work)

        #expect(!controller.isApplyingResetCredit)
        #expect(codexApp.relaunchCount == 1)
    }

    @Test
    func aResetIsRefusedWhileASwitchRunsAndWorksAfterIt() async {
        let personal = makeAccount(name: "Personal", fingerprint: "live")
        let work = makeAccount(name: "Work", fingerprint: "work")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [personal, work])
        let codexApp = CodexAppProcessProbe()
        let gate = TestGate()
        codexApp.relaunchGate = gate
        let resetCredits = ResetCreditClientProbe(results: [.success(.reset)])
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            authService: NullAuthService(),
            codexAppProcessClient: codexApp,
            resetCreditClient: resetCredits
        )
        controller.load()

        let switching = Task { await controller.switchToAccount(work) }
        await gate.waitUntilReached()
        let resetDuringSwitch = await controller.useResetCredit()

        #expect(resetDuringSwitch == .accountChangeInProgress)
        #expect(await resetCredits.receivedKeys.isEmpty)

        await gate.open()
        _ = await switching.value
        #expect(await controller.useResetCredit() == .reset)
        #expect(await resetCredits.receivedKeys.count == 1)
    }

    @Test
    func removingAnAccountWaitsUntilAResetCreditFinishes() async {
        let personal = makeAccount(name: "Personal", fingerprint: "live")
        let work = makeAccount(name: "Work", fingerprint: "work")
        let repository = LoadingPersistingAccountCatalogProbe(accountsToLoad: [personal, work])
        let resetCredits = SuspendedResetCreditClient()
        let controller = makeController(
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "live"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            authService: NullAuthService(),
            resetCreditClient: resetCredits
        )
        controller.load()

        let reset = Task { await controller.useResetCredit() }
        await resetCredits.waitUntilCalled()
        await controller.removeSavedAccount(work)

        #expect(controller.accounts.map(\.email) == ["personal@example.com", "work@example.com"])
        #expect(controller.consumePendingErrorMessage() == "A reset is in progress. Try again when it finishes.")

        await resetCredits.answer(.nothingToReset)
        _ = await reset.value
        await controller.removeSavedAccount(work)
        #expect(controller.accounts.map(\.email) == ["personal@example.com"])
    }

    private func makeController(
        repository: LoadingPersistingAccountCatalogProbe,
        identityResolver: SavedAccountIdentityResolver,
        authService: some CodexAuthSessionStore & CodexSignInAuthStore,
        accountStatusClient: CodexAccountStatusClient = StubAccountStatusClient(error: TestFailure.backgroundRefreshFailed),
        savedAccountStatusClient: SavedCodexAccountStatusClient = DisabledAccountStatusClient(),
        isolatedLoginClient: IsolatedCodexLoginClient = IsolatedAddAccountLoginClientProbe(
            session: IsolatedAddAccountLoginSessionProbe(authData: Data())
        ),
        codexAppProcessClient: CodexAppProcessProbe = CodexAppProcessProbe(),
        resetCreditClient: CodexResetCreditClient = UnavailableResetCreditClient(),
        makeIdempotencyKey: @escaping () -> UUID = UUID.init,
        now: @escaping () -> Date = Date.init
    ) -> AccountsController {
        AccountsController(
            identityResolver: identityResolver,
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                accountStatusClient: accountStatusClient,
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: authService,
                savedAccountStatusClient: savedAccountStatusClient,
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            accountCatalogStore: repository,
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: authService,
                repository: repository,
                codexAppProcessClient: codexAppProcessClient,
                identityResolver: identityResolver
            ),
            addAccountWorkflow: AddAccountWorkflow(
                authService: authService,
                repository: repository,
                identityResolver: identityResolver,
                isolatedLoginClient: isolatedLoginClient
            ),
            resetCreditClient: resetCreditClient,
            makeIdempotencyKey: makeIdempotencyKey,
            now: now,
            postSwitchRefreshDelay: .zero
        )
    }

    private func makeUsageSnapshot() -> UsageSnapshot {
        UsageSnapshot.codex(
            planName: "free",
            primary: (usedPercent: 11, resetsAt: Date(timeIntervalSince1970: 1_776_256_138), durationMinutes: 300),
            secondary: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_776_200_000)
        )
    }
}

private enum TestFailure: LocalizedError {
    case backgroundRefreshFailed

    var errorDescription: String? {
        switch self {
        case .backgroundRefreshFailed:
            "Background refresh failed."
        }
    }
}

private final class LoadingPersistingAccountCatalogProbe: AccountCatalogLoader, AccountSnapshotRemover, @unchecked Sendable {
    let accountsToLoad: [CodexAccount]
    private(set) var savedAccounts: [CodexAccount]?
    private(set) var bootstrapCount = 0

    init(accountsToLoad: [CodexAccount]) {
        self.accountsToLoad = accountsToLoad
    }

    func bootstrapStorage() throws {
        bootstrapCount += 1
    }

    func loadAccounts() throws -> [CodexAccount] {
        accountsToLoad
    }

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }

    func deleteSnapshot(for account: CodexAccount) throws {}
}

private final class ActiveSnapshotRelinkerProbe: ActiveAuthSnapshotRelinking {
    let currentFingerprint: String?
    let relinkedFingerprint: String

    init(currentFingerprint: String?, relinkedFingerprint: String) {
        self.currentFingerprint = currentFingerprint
        self.relinkedFingerprint = relinkedFingerprint
    }

    func currentAuthFingerprint() -> String? {
        currentFingerprint
    }

    func readCurrentAuthData() throws -> Data {
        Data("fresh-auth".utf8)
    }

    func saveAuthSnapshot(_ authData: Data, existing: CodexAccount?) throws -> CodexAccount {
        var account = existing ?? CodexAccount(
            id: UUID(),
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            usage: nil,
            identity: .empty
        )
        account.identity.snapshotFingerprint = relinkedFingerprint
        return account
    }
}

private final class NullAuthService: CodexAuthSessionStore, CodexSignInAuthStore {

    func activate(_ account: CodexAccount) throws {}

    func readCurrentAuthData() throws -> Data { Data() }
    func readAuthSnapshot(for account: CodexAccount) throws -> Data { Data() }
    func currentAuthFingerprint() -> String? { nil }
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity { .empty }
    func restoreCurrentAuthData(_ data: Data) throws {}

    func saveAuthSnapshot(_ authData: Data, existing: CodexAccount?) throws -> CodexAccount {
        if let existing {
            return existing
        }

        let id = UUID()
        return CodexAccount(
            id: id,
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            usage: nil,
            identity: .empty
        )
    }

    func replaceAuthSnapshot(_ authData: Data, ifUnchangedFrom expected: Data, for account: CodexAccount) throws -> CodexAccount? { nil }
    func deleteAuthSnapshot(for account: CodexAccount) throws {}
}

private final class SignInAuthErrorCase: CodexAuthSessionStore, CodexSignInAuthStore {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func activate(_ account: CodexAccount) throws {}
    func readCurrentAuthData() throws -> Data { Data() }
    func readAuthSnapshot(for account: CodexAccount) throws -> Data { Data() }
    func currentAuthFingerprint() -> String? { nil }
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity { .empty }
    func restoreCurrentAuthData(_ data: Data) throws {}

    func saveAuthSnapshot(_ authData: Data, existing: CodexAccount?) throws -> CodexAccount {
        throw error
    }

    func replaceAuthSnapshot(_ authData: Data, ifUnchangedFrom expected: Data, for account: CodexAccount) throws -> CodexAccount? {
        throw error
    }
    func deleteAuthSnapshot(for account: CodexAccount) throws {}
}

private final class IsolatedAddAccountAuthProbe: CodexAuthSessionStore, CodexSignInAuthStore, @unchecked Sendable {
    var currentFingerprint: String?
    let capturedFingerprint: String?

    init(currentFingerprint: String?, capturedFingerprint: String?) {
        self.currentFingerprint = currentFingerprint
        self.capturedFingerprint = capturedFingerprint
    }

    func activate(_ account: CodexAccount) throws {}
    func readCurrentAuthData() throws -> Data { Data() }
    func readAuthSnapshot(for account: CodexAccount) throws -> Data {
        Data((account.identity.snapshotFingerprint ?? "").utf8)
    }
    func currentAuthFingerprint() -> String? { currentFingerprint }
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: capturedFingerprint)
    }
    func restoreCurrentAuthData(_ data: Data) throws {}
    func saveAuthSnapshot(_ authData: Data, existing: CodexAccount?) throws -> CodexAccount {
        let id = UUID()
        return CodexAccount(
            id: id,
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            usage: nil,
            identity: CodexAccountIdentity(snapshotFingerprint: capturedFingerprint)
        )
    }
    func replaceAuthSnapshot(_ authData: Data, ifUnchangedFrom expected: Data, for account: CodexAccount) throws -> CodexAccount? { nil }
    func deleteAuthSnapshot(for account: CodexAccount) throws {}
}

private final class SavedAccountStatusFixture: SavedCodexAccountStatusClient, @unchecked Sendable {
    let statusBySnapshot: [String: CodexAccountStatus]
    private(set) var readSnapshots: [Data] = []

    init(statusBySnapshot: [String: CodexAccountStatus]) {
        self.statusBySnapshot = statusBySnapshot
    }

    func readSavedAccountStatus(authData: Data) async -> SavedCodexAccountStatusRead {
        readSnapshots.append(authData)
        let snapshot = String(decoding: authData, as: UTF8.self)
        guard let status = statusBySnapshot[snapshot] else {
            return SavedCodexAccountStatusRead(status: .failure(NSError(domain: "SavedAccountStatusFixture", code: 1)), rotatedAuthData: nil)
        }
        return SavedCodexAccountStatusRead(status: .success(status), rotatedAuthData: nil)
    }
}

private struct IsolatedAddAccountLoginClientProbe: IsolatedCodexLoginClient {
    let session: IsolatedCodexLoginSession

    func startLogin() async throws -> IsolatedCodexLoginSession {
        session
    }
}

private final class IsolatedAddAccountLoginSessionProbe: IsolatedCodexLoginSession, @unchecked Sendable {
    let prompt = IsolatedCodexLoginPrompt(
        url: URL(string: "https://auth.openai.com/codex/device")!,
        userCode: "ABCD-EFGH"
    )
    let codexHome = URL(fileURLWithPath: "/tmp/rusage-test-codex-home")
    let authData: Data
    private(set) var cleanupCount = 0

    init(authData: Data) {
        self.authData = authData
    }

    func waitForAuthData() async throws -> Data { authData }
    func verifyLoginStatus() async -> Bool { true }
    func cancel() {}
    func cleanup() {
        cleanupCount += 1
    }
}

private final class SwitchableLiveIdentity: LiveCodexAccountIdentitySource, @unchecked Sendable {
    var fingerprint: String

    init(fingerprint: String) {
        self.fingerprint = fingerprint
    }

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveIdentityStub(fingerprint: fingerprint).identity
    }
}

private actor ResetCreditClientProbe: CodexResetCreditClient {
    private var results: [Result<CodexResetCreditOutcome, Error>]
    private(set) var receivedKeys: [UUID] = []

    init(results: [Result<CodexResetCreditOutcome, Error>]) {
        self.results = results
    }

    func consumeResetCredit(idempotencyKey: UUID) async throws -> CodexResetCreditOutcome {
        receivedKeys.append(idempotencyKey)
        return try results.removeFirst().get()
    }
}
