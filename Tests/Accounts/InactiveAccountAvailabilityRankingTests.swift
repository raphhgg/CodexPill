import Foundation
import Testing

@testable import CodexPill

struct AccountAvailabilityTests {
    @Test
    func availabilityReadsSessionAndWeeklyUsage() {
        let account = makeAccount(name: "Ready", rateLimits: makeRateLimits(sessionUsedPercent: 35, weeklyUsedPercent: 40))

        let availability = AccountAvailabilityService().availability(for: account)

        #expect(availability.sessionUsedPercent == 35)
        #expect(availability.weeklyUsedPercent == 40)
    }

    @Test
    func weeklyOnlyAccountHasNoSessionUsage() {
        let account = CodexAccount(
            id: UUID(),
            name: "Free",
            snapshotFileName: "free.json",
            createdAt: .now,
            updatedAt: .now,
            email: "free@example.com",
            planType: "free",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "free",
                primary: CodexRateLimitWindow(
                    usedPercent: 0,
                    resetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                secondary: nil,
                fetchedAt: .now
            )
        )

        let availability = AccountAvailabilityService().availability(for: account)

        #expect(availability.sessionUsedPercent == 0)
        #expect(availability.weeklyUsedPercent == 0)
        #expect(availability.sessionResetAt == nil)
    }

    @Test
    func exhaustedSessionKeepsItsResetTime() {
        let now = Date()
        let resetAt = now.addingTimeInterval(1800)
        let account = makeAccount(
            name: "Session Blocked",
            rateLimits: makeRateLimits(sessionUsedPercent: 100, sessionResetsAt: resetAt, weeklyUsedPercent: 10)
        )

        let availability = AccountAvailabilityService().availability(for: account, now: now)

        #expect(availability.sessionUsedPercent == 100)
        #expect(availability.sessionResetAt == resetAt)
        #expect(availability.weeklyUsedPercent == 10)
    }

    @Test
    func accountNeverReadCountsAsUsedUp() {
        let account = CodexAccount(
            id: UUID(),
            name: "Unread",
            snapshotFileName: "unread.json",
            createdAt: .now,
            updatedAt: .now,
            email: nil,
            planType: nil,
            rateLimits: nil
        )

        let availability = AccountAvailabilityService().availability(for: account)

        #expect(availability.sessionUsedPercent == 100)
        #expect(availability.weeklyUsedPercent == 100)
    }
}

struct InactiveAccountAvailabilityRankingTests {
    @Test
    func prefersWeeklyHeadroomBeforeSessionReadiness() {
        let ranking = InactiveAccountAvailabilityRanking()
        let weeklyHealthy = makeAccount(
            name: "Weekly Healthy",
            rateLimits: makeRateLimits(sessionUsedPercent: 35, weeklyUsedPercent: 40)
        )
        let weeklyConstrained = makeAccount(
            name: "Weekly Constrained",
            rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 96)
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
            rateLimits: makeRateLimits(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 60)
        )
        let laterAvailable = makeAccount(
            name: "Later",
            rateLimits: makeRateLimits(sessionUsedPercent: 60, sessionResetsAt: laterReset, weeklyUsedPercent: 60)
        )
        let sameAvailabilityHigherUsage = makeAccount(
            name: "Higher Usage",
            rateLimits: makeRateLimits(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 90)
        )
        let sameMetricsNameB = makeAccount(
            name: "Zulu",
            rateLimits: makeRateLimits(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 80)
        )
        let sameMetricsNameA = makeAccount(
            name: "Alpha",
            rateLimits: makeRateLimits(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 80)
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
        let preferred = makeAccount(name: "Preferred", rateLimits: makeRateLimits(sessionUsedPercent: 0, weeklyUsedPercent: 10))
        let constrained = makeAccount(name: "Constrained", rateLimits: makeRateLimits(sessionUsedPercent: 90, weeklyUsedPercent: 100))
        let active = makeAccount(name: "Active", fingerprint: "active", rateLimits: makeRateLimits(sessionUsedPercent: 20, weeklyUsedPercent: 20))
        let repository = RankingLoadingPersistingAccountCatalogProbe(accountsToLoad: [constrained, active, preferred])
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: LiveIdentityStub(fingerprint: "active"),
            storedAccountReconciler: PassthroughIdentityReconciler()
        )
        let controller = AccountsController(
            identityResolver: identityResolver,
            inactiveAccountAvailabilityRanking: InactiveAccountAvailabilityRanking(),
            loadAccountsUseCase: LoadAccountsUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            refreshActiveAccountUseCase: RefreshActiveAccountUseCase(
                accountStatusClient: StubAccountStatusClient(error: RankingTestFailure.backgroundRefreshFailed),
                identityResolver: identityResolver,
                repository: repository
            ),
            hydrateSavedAccountsMetadataUseCase: HydrateSavedAccountsMetadataUseCase(
                authService: RankingNullAuthService(),
                savedAccountStatusClient: DisabledAccountStatusClient(),
                repository: repository
            ),
            deleteSavedAccountUseCase: DeleteSavedAccountUseCase(
                repository: repository,
                identityResolver: identityResolver
            ),
            renameSavedAccountUseCase: RenameSavedAccountUseCase(repository: repository),
            accountCatalogStore: repository,
            switchAccountWorkflow: SwitchAccountWorkflow(
                authService: RankingNullAuthService(),
                repository: repository,
                codexAppProcessClient: CodexAppProcessProbe(),
                identityResolver: identityResolver
            ),
            addAccountWorkflow: AddAccountWorkflow(
                authService: RankingNullAuthService(),
                repository: repository,
                identityResolver: identityResolver
            )
        )

        controller.load()

        #expect(controller.activeAccount?.name == "Active")
        #expect(controller.sortedInactiveAccounts.map(\.name) == ["Preferred", "Constrained"])
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

private final class RankingLoadingPersistingAccountCatalogProbe: AccountCatalogLoader, AccountSnapshotRemover {
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

private struct RankingNullAuthService: CodexAuthSessionStore, CodexSignInAuthStore {
    func activate(_ account: CodexAccount) throws {}
    func readCurrentAuthData() throws -> Data { Data() }
    func readAuthSnapshot(for account: CodexAccount) throws -> Data { Data() }
    func currentAuthFingerprint() -> String? { nil }
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity { .empty }
    func restoreCurrentAuthData(_ data: Data) throws {}

    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
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

    func replaceAuthSnapshot(_ authData: Data, ifUnchangedFrom expected: Data, for account: CodexAccount) throws -> CodexAccount? { nil }
    func deleteAuthSnapshot(for account: CodexAccount) throws {}
}
