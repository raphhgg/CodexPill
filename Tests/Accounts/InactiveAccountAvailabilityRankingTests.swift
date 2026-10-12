import Foundation
import Testing

@testable import CodexPill

struct AccountAvailabilityTests {
    @Test
    func availabilityReadsSessionAndWeeklyUsage() {
        let account = makeAccount(name: "Ready", usage: makeUsage(sessionUsedPercent: 35, weeklyUsedPercent: 40))

        let availability = AccountAvailabilityService().availability(for: account)

        #expect(availability.sessionUsedPercent == 35)
        #expect(availability.longWindowUsedPercent == 40)
    }

    @Test
    func weeklyOnlyAccountHasNoSessionUsage() {
        let account = CodexAccount(
            id: UUID(),
            snapshotFileName: "free.json",
            createdAt: .now,
            updatedAt: .now,
            email: "free@example.com",
            planType: "free",
            usage: UsageSnapshot.codex(
                planName: "free",
                primary: (usedPercent: 0, resetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60), durationMinutes: 10_080),
                secondary: nil,
                fetchedAt: .now
            )
        )

        let availability = AccountAvailabilityService().availability(for: account)

        #expect(availability.sessionUsedPercent == 0)
        #expect(availability.longWindowUsedPercent == 0)
        #expect(availability.sessionResetAt == nil)
    }

    @Test
    func usedUpMonthlyWindowLimitsAFreeAccount() {
        let now = Date()
        let resetAt = now.addingTimeInterval(20 * 86_400)
        let account = makeAccount(
            name: "Free",
            usage: UsageSnapshot.codex(
                planName: "free",
                primary: nil,
                secondary: (usedPercent: 100, resetsAt: resetAt, durationMinutes: 43_200),
                fetchedAt: now
            )
        )

        let availability = AccountAvailabilityService().availability(for: account, now: now)

        #expect(availability.longWindowUsedPercent == 100)
        #expect(availability.longWindowResetAt == resetAt)
    }

    @Test
    func exhaustedSessionKeepsItsResetTime() {
        let now = Date()
        let resetAt = now.addingTimeInterval(1800)
        let account = makeAccount(
            name: "Session Blocked",
            usage: makeUsage(sessionUsedPercent: 100, sessionResetsAt: resetAt, weeklyUsedPercent: 10)
        )

        let availability = AccountAvailabilityService().availability(for: account, now: now)

        #expect(availability.sessionUsedPercent == 100)
        #expect(availability.sessionResetAt == resetAt)
        #expect(availability.longWindowUsedPercent == 10)
    }

    @Test
    func accountNeverReadCountsAsUsedUp() {
        let account = CodexAccount(
            id: UUID(),
            snapshotFileName: "unread.json",
            createdAt: .now,
            updatedAt: .now,
            email: nil,
            planType: nil,
            usage: nil
        )

        let availability = AccountAvailabilityService().availability(for: account)

        #expect(availability.sessionUsedPercent == 100)
        #expect(availability.longWindowUsedPercent == 100)
    }
}

struct InactiveAccountAvailabilityRankingTests {
    @Test
    func prefersWeeklyHeadroomBeforeSessionReadiness() {
        let ranking = InactiveAccountAvailabilityRanking()
        let weeklyHealthy = makeAccount(
            name: "Weekly Healthy",
            usage: makeUsage(sessionUsedPercent: 35, weeklyUsedPercent: 40)
        )
        let weeklyConstrained = makeAccount(
            name: "Weekly Constrained",
            usage: makeUsage(sessionUsedPercent: 0, weeklyUsedPercent: 96)
        )

        let sorted = ranking.sort([weeklyConstrained, weeklyHealthy])

        #expect(sorted.map(\.email) == ["weekly healthy@example.com", "weekly constrained@example.com"])
    }

    @Test
    func breaksTiesByNextAvailabilityThenUsageThenEmail() {
        let ranking = InactiveAccountAvailabilityRanking()
        let now = Date()
        let laterReset = now.addingTimeInterval(7_200)
        let earlierReset = now.addingTimeInterval(3_600)
        let earlierAvailable = makeAccount(
            name: "Earlier",
            usage: makeUsage(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 60)
        )
        let laterAvailable = makeAccount(
            name: "Later",
            usage: makeUsage(sessionUsedPercent: 60, sessionResetsAt: laterReset, weeklyUsedPercent: 60)
        )
        let sameAvailabilityHigherUsage = makeAccount(
            name: "Higher Usage",
            usage: makeUsage(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 90)
        )
        let sameMetricsNameB = makeAccount(
            name: "Zulu",
            usage: makeUsage(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 80)
        )
        let sameMetricsNameA = makeAccount(
            name: "Alpha",
            usage: makeUsage(sessionUsedPercent: 60, sessionResetsAt: earlierReset, weeklyUsedPercent: 80)
        )

        let sorted = ranking.sort([
            laterAvailable,
            sameMetricsNameB,
            sameAvailabilityHigherUsage,
            sameMetricsNameA,
            earlierAvailable
        ])

        #expect(sorted.map(\.email) == ["earlier@example.com", "alpha@example.com", "zulu@example.com", "later@example.com", "higher usage@example.com"])
    }

    @MainActor
    @Test
    func accountsControllerDelegatesInactiveSortingToRankingPolicy() async {
        let preferred = makeAccount(name: "Preferred", usage: makeUsage(sessionUsedPercent: 0, weeklyUsedPercent: 10))
        let constrained = makeAccount(name: "Constrained", usage: makeUsage(sessionUsedPercent: 90, weeklyUsedPercent: 100))
        let active = makeAccount(name: "Active", fingerprint: "active", usage: makeUsage(sessionUsedPercent: 20, weeklyUsedPercent: 20))
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

        #expect(controller.activeAccount?.email == "active@example.com")
        #expect(controller.sortedInactiveAccounts.map(\.email) == ["preferred@example.com", "constrained@example.com"])
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

    func saveAuthSnapshot(_ authData: Data, existing: CodexAccount?) throws -> CodexAccount {
        existing ?? CodexAccount(
            id: UUID(),
            snapshotFileName: "\(UUID().uuidString).json",
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
