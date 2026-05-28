import Foundation
import Testing

@testable import CodexPill

struct HydrateSavedAccountsMetadataUseCaseTests {
    @Test
    func runBackfillsInactiveAccountsMissingRateLimitsAndRestoresOriginalAuth() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: true)
        let inactiveMissing = makeAccount(name: "Missing", fingerprint: "missing", withRateLimits: false)
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "missing": CodexAccountStatus(
                    email: "missing@example.com",
                    planType: "pro",
                    rateLimits: makeRateLimitsSnapshot()
                )
            ], authService: auth),
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "missing": CodexAccountStatus(
                    email: "missing@example.com",
                    planType: "pro",
                    rateLimits: makeRateLimitsSnapshot()
                )
            ], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: HydrationIdentitySource(activeFingerprint: "active"),
                storedAccountReconciler: HydrationIdentityReconcilerAdapter()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveMissing, inactiveReady],
            activeAccountID: active.id
        )

        let hydratedMissing = try #require(result.accounts.first(where: { $0.id == inactiveMissing.id }))
        let preservedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))

        #expect(hydratedMissing.rateLimits?.primary?.usedPercent == 46)
        #expect(hydratedMissing.email == "missing@example.com")
        #expect(preservedReady.rateLimits != nil)
        #expect(auth.recordedSnapshotReads() == [inactiveMissing.id])
        #expect(auth.currentAuthDataString() == "active-auth")
        #expect(result.activeAccountID == active.id)
        #expect(result.hydratedAccountIDs == [inactiveMissing.id])
        #expect(repository.savedAccounts == result.accounts)
    }

    @Test
    func runSkipsWhenNoInactiveAccountsNeedHydration() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: true)
        let inactive = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [:], authService: auth),
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [:], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: HydrationIdentitySource(activeFingerprint: "active"),
                storedAccountReconciler: HydrationIdentityReconcilerAdapter()
            ),
            repository: repository
        )

        let result = try await useCase.run(accounts: [active, inactive], activeAccountID: active.id)

        #expect(result.accounts == [active, inactive])
        #expect(result.activeAccountID == active.id)
        #expect(result.hydratedAccountIDs.isEmpty)
        #expect(repository.savedAccounts == nil)
        #expect(auth.recordedSnapshotReads().isEmpty)
    }

    @Test
    func runRefreshesInactiveAccountsThatAlreadyHaveRateLimitsWhenRequested() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: true)
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let refreshedRateLimits = CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "team",
            primary: CodexRateLimitWindow(
                usedPercent: 12,
                resetsAt: Date(timeIntervalSince1970: 1_776_256_138),
                windowDurationMinutes: 300
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 3,
                resetsAt: Date(timeIntervalSince1970: 1_776_842_938),
                windowDurationMinutes: 10_080
            ),
            fetchedAt: Date(timeIntervalSince1970: 1_776_300_000)
        )
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "ready": CodexAccountStatus(
                    email: "fresh-ready@example.com",
                    planType: "team",
                    rateLimits: refreshedRateLimits
                )
            ], authService: auth),
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "ready": CodexAccountStatus(
                    email: "fresh-ready@example.com",
                    planType: "team",
                    rateLimits: refreshedRateLimits
                )
            ], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: HydrationIdentitySource(activeFingerprint: "active"),
                storedAccountReconciler: HydrationIdentityReconcilerAdapter()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveReady],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        let refreshedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))
        #expect(refreshedReady.rateLimits == refreshedRateLimits)
        #expect(refreshedReady.email == "fresh-ready@example.com")
        #expect(refreshedReady.planType == "team")
        #expect(auth.recordedSnapshotReads() == [inactiveReady.id])
        #expect(auth.currentAuthDataString() == "active-auth")
        #expect(result.activeAccountID == active.id)
        #expect(result.hydratedAccountIDs == [inactiveReady.id])
        #expect(repository.savedAccounts == result.accounts)
    }

    @Test
    func runBackfillsInactiveAccountsWithWeeklyOnlyRateLimits() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: true)
        let inactiveMissing = makeAccount(name: "Missing", fingerprint: "missing", withRateLimits: false)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let primaryOnlyRateLimits = CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "free",
            primary: CodexRateLimitWindow(
                usedPercent: 9,
                resetsAt: Date(timeIntervalSince1970: 1_776_256_138),
                windowDurationMinutes: 10_080
            ),
            secondary: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_776_200_000)
        )
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [:], authService: auth),
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "missing": CodexAccountStatus(
                    email: "missing@example.com",
                    planType: "free",
                    rateLimits: primaryOnlyRateLimits
                )
            ], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: HydrationIdentitySource(activeFingerprint: "active"),
                storedAccountReconciler: HydrationIdentityReconcilerAdapter()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveMissing],
            activeAccountID: active.id
        )

        let hydratedMissing = try #require(result.accounts.first(where: { $0.id == inactiveMissing.id }))
        #expect(hydratedMissing.rateLimits == primaryOnlyRateLimits)
        #expect(hydratedMissing.email == "missing@example.com")
        #expect(hydratedMissing.planType == "free")
        #expect(result.hydratedAccountIDs == [inactiveMissing.id])
        #expect(repository.savedAccounts == result.accounts)
    }

    @Test
    func runDoesNotMarkPreservedInactiveRateLimitsFreshWhenRefreshReturnsNoRateLimits() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: true)
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let originalUpdatedAt = inactiveReady.updatedAt
        let originalRateLimits = try #require(inactiveReady.rateLimits)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "ready": CodexAccountStatus(
                    email: inactiveReady.email,
                    planType: inactiveReady.planType,
                    rateLimits: nil
                )
            ], authService: auth),
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "ready": CodexAccountStatus(
                    email: inactiveReady.email,
                    planType: inactiveReady.planType,
                    rateLimits: nil
                )
            ], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: HydrationIdentitySource(activeFingerprint: "active"),
                storedAccountReconciler: HydrationIdentityReconcilerAdapter()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveReady],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        let refreshedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))
        #expect(refreshedReady.rateLimits == originalRateLimits)
        #expect(refreshedReady.updatedAt == originalUpdatedAt)
        #expect(auth.recordedSnapshotReads() == [inactiveReady.id])
        #expect(auth.currentAuthDataString() == "active-auth")
        #expect(result.hydratedAccountIDs.isEmpty)
        #expect(repository.savedAccounts == nil)
    }

    @Test(arguments: [
        CodexAccountStatus(email: "ready@example.com", planType: "pro", rateLimits: nil),
        CodexAccountStatus(email: "ready@example.com", planType: "pro", rateLimits: CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "pro",
            primary: CodexRateLimitWindow(usedPercent: 0, resetsAt: .now.addingTimeInterval(60 * 60), windowDurationMinutes: 300),
            secondary: CodexRateLimitWindow(usedPercent: 0, resetsAt: .now.addingTimeInterval(7 * 24 * 60 * 60), windowDurationMinutes: 10_080),
            fetchedAt: .now
        ))
    ])
    func runPreservesPreviousMeaningfulRateLimitsWhenIsolatedReadIsNotUsable(status: CodexAccountStatus) async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: true)
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let originalRateLimits = try #require(inactiveReady.rateLimits)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [:], authService: auth),
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: ["ready": status], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: HydrationIdentitySource(activeFingerprint: "active"),
                storedAccountReconciler: HydrationIdentityReconcilerAdapter()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveReady],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        let refreshedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))
        #expect(refreshedReady.rateLimits == originalRateLimits)
        #expect(auth.currentAuthDataString() == "active-auth")
        #expect(result.hydratedAccountIDs.isEmpty)
    }

    @Test
    func runPreservesPreviousMeaningfulRateLimitsWhenIsolatedReadFails() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: true)
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let originalRateLimits = try #require(inactiveReady.rateLimits)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [:], authService: auth),
            savedAccountStatusClient: HydrationFailingSavedStatusProbe(),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: HydrationIdentitySource(activeFingerprint: "active"),
                storedAccountReconciler: HydrationIdentityReconcilerAdapter()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveReady],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        let refreshedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))
        #expect(refreshedReady.rateLimits == originalRateLimits)
        #expect(auth.currentAuthDataString() == "active-auth")
        #expect(result.hydratedAccountIDs.isEmpty)
    }

    private func makeAccount(name: String, fingerprint: String, withRateLimits: Bool) -> CodexAccount {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        return CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: now,
            updatedAt: now,
            email: withRateLimits ? "\(name.lowercased())@example.com" : nil,
            planType: withRateLimits ? "pro" : nil,
            rateLimits: withRateLimits ? makeRateLimitsSnapshot() : nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: fingerprint,
                remoteIdentity: withRateLimits ? CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com") : nil
            )
        )
    }

    private func makeRateLimitsSnapshot() -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "pro",
            primary: CodexRateLimitWindow(
                usedPercent: 46,
                resetsAt: Date(timeIntervalSince1970: 1_776_256_138),
                windowDurationMinutes: 300
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 7,
                resetsAt: Date(timeIntervalSince1970: 1_776_842_938),
                windowDurationMinutes: 10_080
            ),
            fetchedAt: Date(timeIntervalSince1970: 1_776_200_000)
        )
    }
}

private final class HydrationAuthSnapshotProbe: CodexAuthSessionStore, @unchecked Sendable {
    private var currentAuthData: Data
    private var accountsByID: [UUID: CodexAccount] = [:]
    private var snapshotReadIDs: [UUID] = []

    init(currentAuthData: Data) {
        self.currentAuthData = currentAuthData
    }

    func readCurrentAuthData() throws -> Data {
        currentAuthData
    }

    func restoreCurrentAuthData(_ data: Data) throws {
        currentAuthData = data
    }

    func readAuthSnapshot(for account: CodexAccount) throws -> Data {
        accountsByID[account.id] = account
        snapshotReadIDs.append(account.id)
        return Data((account.identity.snapshotFingerprint ?? "").utf8)
    }

    func activate(_ account: CodexAccount) throws {
        accountsByID[account.id] = account
        currentAuthData = Data((account.identity.snapshotFingerprint ?? "").utf8)
    }

    func currentFingerprint() -> String {
        String(decoding: currentAuthData, as: UTF8.self)
    }

    func recordedSnapshotReads() -> [UUID] {
        snapshotReadIDs
    }

    func currentAuthDataString() -> String {
        String(decoding: currentAuthData, as: UTF8.self)
    }
}

private struct HydrationAccountStatusProbe: CodexAccountStatusClient, SavedCodexAccountStatusClient {
    let statusByFingerprint: [String: CodexAccountStatus]
    let authService: HydrationAuthSnapshotProbe

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        let fingerprint = authService.currentFingerprint()
        guard let status = statusByFingerprint[fingerprint] else {
            throw NSError(domain: "HydrationAccountStatusProbe", code: 1)
        }
        return status
    }

    func readSavedAccountStatus(authData: Data) async throws -> CodexAccountStatus {
        let fingerprint = String(decoding: authData, as: UTF8.self)
        guard let status = statusByFingerprint[fingerprint] else {
            throw NSError(domain: "HydrationAccountStatusProbe", code: 1)
        }
        return status
    }
}

private struct HydrationFailingSavedStatusProbe: SavedCodexAccountStatusClient {
    func readSavedAccountStatus(authData: Data) async throws -> CodexAccountStatus {
        throw NSError(domain: "HydrationFailingSavedStatusProbe", code: 1)
    }
}

private final class HydrationCatalogProbe: AccountCatalogStore, @unchecked Sendable {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}

private struct HydrationIdentitySource: LiveCodexAccountIdentitySource {
    let activeFingerprint: String

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: activeFingerprint)
    }
}

private struct HydrationIdentityReconcilerAdapter: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
