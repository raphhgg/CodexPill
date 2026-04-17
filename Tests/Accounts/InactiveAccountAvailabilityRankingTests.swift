import Foundation
import Testing

@testable import CodexPill

struct InactiveAccountAvailabilityRankingTests {
    @Test
    func prefersWeeklyHeadroomBeforeSessionReadiness() {
        let ranking = InactiveAccountAvailabilityRanking()
        let weeklyHealthy = makeAccount(
            name: "Weekly Healthy",
            sessionUsedPercent: 35,
            weeklyUsedPercent: 40
        )
        let weeklyConstrained = makeAccount(
            name: "Weekly Constrained",
            sessionUsedPercent: 0,
            weeklyUsedPercent: 96
        )

        let sorted = ranking.sort([weeklyConstrained, weeklyHealthy])

        #expect(sorted.map(\.name) == ["Weekly Healthy", "Weekly Constrained"])
    }

    @Test
    func breaksTiesByNextAvailabilityThenUsageThenName() {
        let ranking = InactiveAccountAvailabilityRanking()
        let now = Date()
        let laterReset = now.addingTimeInterval(7_200)
        let earlierReset = now.addingTimeInterval(3_600)
        let earlierAvailable = makeAccount(
            name: "Earlier",
            sessionUsedPercent: 60,
            sessionResetAt: earlierReset,
            weeklyUsedPercent: 60
        )
        let laterAvailable = makeAccount(
            name: "Later",
            sessionUsedPercent: 60,
            sessionResetAt: laterReset,
            weeklyUsedPercent: 60
        )
        let sameAvailabilityHigherUsage = makeAccount(
            name: "Higher Usage",
            sessionUsedPercent: 60,
            sessionResetAt: earlierReset,
            weeklyUsedPercent: 90
        )
        let sameMetricsNameB = makeAccount(
            name: "Zulu",
            sessionUsedPercent: 60,
            sessionResetAt: earlierReset,
            weeklyUsedPercent: 80
        )
        let sameMetricsNameA = makeAccount(
            name: "Alpha",
            sessionUsedPercent: 60,
            sessionResetAt: earlierReset,
            weeklyUsedPercent: 80
        )

        let sorted = ranking.sort([
            laterAvailable,
            sameMetricsNameB,
            sameAvailabilityHigherUsage,
            sameMetricsNameA,
            earlierAvailable
        ])

        #expect(sorted.map(\.name) == ["Earlier", "Alpha", "Zulu", "Later", "Higher Usage"])
    }

    @MainActor
    @Test
    func accountsControllerDelegatesInactiveSortingToRankingPolicy() async {
        let preferred = makeAccount(name: "Preferred", sessionUsedPercent: 0, weeklyUsedPercent: 10)
        let constrained = makeAccount(name: "Constrained", sessionUsedPercent: 90, weeklyUsedPercent: 100)
        let active = makeAccount(name: "Active", sessionUsedPercent: 20, weeklyUsedPercent: 20)
        let repository = RankingLoadingPersistingRepositorySpy(accountsToLoad: [constrained, active, preferred])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentityReader: RankingCurrentIdentityStub(fingerprint: "active"),
            storedAccountReconciler: RankingStoredIdentityPassthrough()
        )
        let controller = AccountsController(
            identityResolver: identityResolver,
            inactiveAccountAvailabilityRanking: InactiveAccountAvailabilityRanking(),
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                appServerClient: RankingFailingAccountStatusReader(error: RankingTestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: RankingNoopAuthService(),
                appServerClient: RankingFailingAccountStatusReader(error: RankingTestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: RankingNoopAuthService(),
                repository: repository,
                appController: RankingNoopAppController(),
                identityResolver: identityResolver
            ),
            saveCurrentAccountWorkflow: SaveCurrentAccountWorkflow(
                appServerClient: RankingFailingAccountStatusReader(error: RankingTestFailure.backgroundRefreshFailed),
                authService: RankingNoopAuthService(),
                repository: repository,
                identityResolver: identityResolver
            ),
            signInAnotherWorkflow: SignInAnotherWorkflow(
                authService: RankingNoopAuthService(),
                appController: RankingNoopAppController(),
                appServerClient: RankingFailingAccountStatusReader(error: RankingTestFailure.backgroundRefreshFailed),
                repository: repository,
                identityResolver: identityResolver
            )
        )

        controller.load()

        #expect(controller.activeAccount?.name == "Active")
        #expect(controller.sortedInactiveAccounts.map(\.name) == ["Preferred", "Constrained"])
        #expect(controller.compareForMenu(active, preferred))
        #expect(controller.compareForMenu(preferred, constrained))
    }

    private func makeAccount(
        name: String,
        sessionUsedPercent: Int,
        sessionResetAt: Date? = nil,
        weeklyUsedPercent: Int,
        weeklyResetAt: Date? = nil
    ) -> CodexAccount {
        let id = UUID()
        let now = Date()
        return CodexAccount(
            id: id,
            name: name,
            snapshotFileName: "\(id.uuidString).json",
            createdAt: now,
            updatedAt: now,
            email: "\(name.lowercased())@example.com",
            planType: "pro",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "pro",
                primary: CodexRateLimitWindow(
                    usedPercent: sessionUsedPercent,
                    resetsAt: sessionResetAt,
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: weeklyUsedPercent,
                    resetsAt: weeklyResetAt,
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ),
            identity: CodexAccountIdentity(
                snapshotFingerprint: name == "Active" ? "active" : UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com")
            )
        )
    }
}

private enum RankingTestFailure: LocalizedError {
    case backgroundRefreshFailed

    var errorDescription: String? {
        switch self {
        case .backgroundRefreshFailed:
            "Background refresh failed."
        }
    }
}

private final class RankingFailingAccountStatusReader: CodexAccountStatusReading {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        throw error
    }
}

private final class RankingLoadingPersistingRepositorySpy: AccountCatalogLoading, AccountSnapshotDeleting {
    let accountsToLoad: [CodexAccount]

    init(accountsToLoad: [CodexAccount]) {
        self.accountsToLoad = accountsToLoad
    }

    func bootstrapStorage() throws {}

    func loadAccounts() throws -> [CodexAccount] {
        accountsToLoad
    }

    func saveAccounts(_: [CodexAccount]) throws {}

    func deleteSnapshot(for _: CodexAccount) throws {}
}

private struct RankingCurrentIdentityStub: LiveCodexAccountIdentityReading {
    let fingerprint: String?

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: fingerprint)
    }
}

private struct RankingStoredIdentityPassthrough: StoredAccountIdentityReconciling {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}

private struct RankingNoopAppController: CodexAppRelaunching {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}

private struct RankingNoopAuthService: CodexAuthDataRestoring, CodexAuthSnapshotSaving, CodexSignInAnotherAuthHandling {
    func activate(_ account: CodexAccount) throws {}
    func readCurrentAuthData() throws -> Data { Data() }
    func restoreCurrentAuthData(_ data: Data) throws {}
    func prepareForNewSignIn() throws {}

    func saveCurrentAuthSnapshot(named name: String, existing: CodexAccount?) throws -> CodexAccount {
        existing ?? CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: .empty
        )
    }
}
