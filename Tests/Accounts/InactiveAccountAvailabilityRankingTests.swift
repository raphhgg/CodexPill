import Foundation
import Testing

@testable import CodexPill

struct InactiveAccountAvailabilityRankingTests {
    @Test
    func availabilityServiceMarksAccountAvailableWhenBothWindowsHaveHeadroom() {
        let service = AccountAvailabilityService()
        let account = makeAccount(name: "Ready", sessionUsedPercent: 35, weeklyUsedPercent: 40)

        let availability = service.availability(for: account)

        #expect(availability.target == .local)
        #expect(availability.status == .availableNow)
        #expect(availability.isAvailableNow)
        #expect(availability.nextAvailableAt == nil)
    }

    @Test
    func availabilityServiceMarksAccountBlockedBySessionWhenSessionIsExhausted() {
        let service = AccountAvailabilityService()
        let now = Date()
        let resetAt = now.addingTimeInterval(1800)
        let account = makeAccount(
            name: "Session Blocked",
            sessionUsedPercent: 100,
            sessionResetAt: resetAt,
            weeklyUsedPercent: 10
        )

        let availability = service.availability(for: account, now: now)

        #expect(availability.status == .blocked(until: resetAt, reason: .session))
        #expect(!availability.isAvailableNow)
        #expect(availability.nextAvailableAt == resetAt)
    }

    @Test
    func availabilityServiceMarksAccountBlockedByBothWindowsWhenBothAreExhausted() {
        let service = AccountAvailabilityService()
        let now = Date()
        let sessionResetAt = now.addingTimeInterval(3600)
        let weeklyResetAt = now.addingTimeInterval(7200)
        let account = makeAccount(
            name: "Fully Blocked",
            sessionUsedPercent: 100,
            sessionResetAt: sessionResetAt,
            weeklyUsedPercent: 100,
            weeklyResetAt: weeklyResetAt
        )

        let availability = service.availability(for: account, now: now)

        #expect(availability.status == .blocked(until: sessionResetAt, reason: .sessionAndWeekly))
        #expect(availability.nextAvailableAt == sessionResetAt)
    }

    @Test
    func availabilityServiceMarksRemoteTargetDisconnectedWhenHostIsDisconnected() {
        let service = AccountAvailabilityService()
        let account = makeAccount(name: "Remote", sessionUsedPercent: 10, weeklyUsedPercent: 20)

        let availability = service.availability(
            for: RemoteAccountTargetContext(
                hostDestination: "user@buildbox",
                connectionState: .disconnected,
                verificationState: .failed,
                activeAccount: nil,
                displayAccount: account
            )
        )

        #expect(availability.target == .remote(hostDestination: "user@buildbox"))
        #expect(availability.status == .unavailable(reason: .disconnected))
    }

    @Test
    func availabilityServiceMarksRemoteTargetVerificationFailureWhenHostIsReachableButUnverified() {
        let service = AccountAvailabilityService()
        let account = makeAccount(name: "Remote", sessionUsedPercent: 10, weeklyUsedPercent: 20)

        let availability = service.availability(
            for: RemoteAccountTargetContext(
                hostDestination: "user@buildbox",
                connectionState: .connected,
                verificationState: .failed,
                activeAccount: nil,
                displayAccount: account
            )
        )

        #expect(availability.status == .unavailable(reason: .verificationFailed))
    }

    @Test
    func availabilityServiceUsesVerifiedRemoteAccountRateLimitsWhenHostIsVerified() {
        let service = AccountAvailabilityService()
        let account = makeAccount(name: "Remote", sessionUsedPercent: 100, sessionResetAt: Date().addingTimeInterval(1800), weeklyUsedPercent: 20)

        let availability = service.availability(
            for: RemoteAccountTargetContext(
                hostDestination: "user@buildbox",
                connectionState: .connected,
                verificationState: .verified,
                activeAccount: account,
                displayAccount: account
            )
        )

        #expect(availability.status != .unavailable(reason: .verificationFailed))
        #expect(availability.target == .remote(hostDestination: "user@buildbox"))
        #expect(availability.sessionUsedPercent == 100)
    }

    @Test
    func availabilitySnapshotExposesLocalAndRemoteTargetsAndEarliestNextAvailability() {
        let service = AccountAvailabilityService()
        let now = Date()
        let localResetAt = now.addingTimeInterval(3600)
        let remoteResetAt = now.addingTimeInterval(1800)
        let account = makeAccount(
            name: "Snapshot",
            sessionUsedPercent: 100,
            sessionResetAt: localResetAt,
            weeklyUsedPercent: 20
        )
        let remoteAccount = makeAccount(
            name: "Snapshot",
            sessionUsedPercent: 100,
            sessionResetAt: remoteResetAt,
            weeklyUsedPercent: 20
        )

        let snapshot = service.snapshot(
            for: account,
            remoteTargets: [
                RemoteAccountTargetContext(
                    hostDestination: "user@buildbox",
                    connectionState: .connected,
                    verificationState: .verified,
                    activeAccount: remoteAccount,
                    displayAccount: remoteAccount
                )
            ],
            now: now
        )

        #expect(snapshot.localAvailability.target == .local)
        #expect(snapshot.remoteAvailabilities.count == 1)
        #expect(snapshot.availability(for: .remote(hostDestination: "user@buildbox"))?.nextAvailableAt == remoteResetAt)
        #expect(snapshot.nextAvailabilityAt == remoteResetAt)
    }

    @Test
    func availabilityTransitionsReportWhenLocalAccountBecomesAvailable() {
        let service = AccountAvailabilityService()
        let now = Date()
        let account = makeAccount(
            name: "Ready Soon",
            sessionUsedPercent: 100,
            sessionResetAt: now.addingTimeInterval(1200),
            weeklyUsedPercent: 20
        )
        let previous = service.snapshot(for: account, now: now)
        let current = service.snapshot(
            for: makeAccount(name: "Ready Soon", sessionUsedPercent: 0, weeklyUsedPercent: 20),
            now: now
        )

        let transitions = service.transitions(from: previous, to: current)

        #expect(transitions == [
            AccountAvailabilityTransition(
                target: .local,
                from: .blocked(until: previous.localAvailability.sessionResetAt, reason: .session),
                to: .availableNow
            )
        ])
    }

    @Test
    func availabilityTransitionsReportWhenRemoteTargetBecomesAvailable() {
        let service = AccountAvailabilityService()
        let now = Date()
        let account = makeAccount(name: "Remote Transition", sessionUsedPercent: 10, weeklyUsedPercent: 20)
        let previous = service.snapshot(
            for: account,
            remoteTargets: [
                RemoteAccountTargetContext(
                    hostDestination: "user@buildbox",
                    connectionState: .connected,
                    verificationState: .failed,
                    activeAccount: nil,
                    displayAccount: account
                )
            ],
            now: now
        )
        let current = service.snapshot(
            for: account,
            remoteTargets: [
                RemoteAccountTargetContext(
                    hostDestination: "user@buildbox",
                    connectionState: .connected,
                    verificationState: .verified,
                    activeAccount: account,
                    displayAccount: account
                )
            ],
            now: now
        )

        let transitions = service.transitions(from: previous, to: current)

        #expect(transitions == [
            AccountAvailabilityTransition(
                target: .remote(hostDestination: "user@buildbox"),
                from: .unavailable(reason: .verificationFailed),
                to: .availableNow
            )
        ])
    }

    @Test
    func availabilityTransitionsIgnoreTargetsThatRemainAvailable() {
        let service = AccountAvailabilityService()
        let account = makeAccount(name: "Stable", sessionUsedPercent: 10, weeklyUsedPercent: 20)
        let previous = service.snapshot(for: account)
        let current = service.snapshot(for: account)

        let transitions = service.transitions(from: previous, to: current)

        #expect(transitions.isEmpty)
    }

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
            persistSavedAccountMetadataUseCase: PersistSavedAccountMetadataUseCase(repository: repository),
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
            addAccountWorkflow: AddAccountWorkflow(
                authService: RankingNoopAuthService(),
                appController: RankingNoopAppController(),
                captureClient: RankingNoopDeviceAuthCaptureClient(),
                repository: repository
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

private struct RankingNoopAuthService: CodexAuthDataRestoring, CodexAuthSnapshotSaving, CodexAuthSnapshotImporting {
    func activate(_ account: CodexAccount) throws {}
    func readCurrentAuthData() throws -> Data { Data() }
    func restoreCurrentAuthData(_ data: Data) throws {}

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

    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
        try saveCurrentAuthSnapshot(named: name, existing: existing)
    }
}

private struct RankingNoopDeviceAuthCaptureClient: CodexDeviceAuthCapturing {
    func beginDeviceAuth(in session: IsolatedCodexHomeSession) async throws -> any CodexDeviceAuthCaptureHandling {
        RankingNoopDeviceAuthCapture()
    }
}

private final class RankingNoopDeviceAuthCapture: CodexDeviceAuthCaptureHandling {
    func deviceAuthPrompt() async -> CodexDeviceAuthPrompt {
        CodexDeviceAuthPrompt(
            verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
            userCode: nil
        )
    }

    func waitForCapturedAuth() async throws -> Data { Data() }
    func cancel() async {}
    func cleanup() async throws {}
}
