import Foundation
import Testing

@testable import CodexPill

struct HydrateSavedAccountsMetadataUseCaseTests {
    @Test
    func runBackfillsInactiveAccountsMissingRateLimitsAndRestoresOriginalAuth() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", planType: "pro", usage: makeUsageSnapshot())
        let inactiveMissing = makeAccount(name: "Missing", email: nil, fingerprint: "missing")
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", planType: "pro", usage: makeUsageSnapshot())
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "missing": CodexAccountStatus(
                    email: "missing@example.com",
                    planType: "pro",
                    usage: makeUsageSnapshot()
                )
            ], authService: auth),
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "missing": CodexAccountStatus(
                    email: "missing@example.com",
                    planType: "pro",
                    usage: makeUsageSnapshot()
                )
            ], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "active"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveMissing, inactiveReady],
            activeAccountID: active.id
        )

        let hydratedMissing = try #require(result.accounts.first(where: { $0.id == inactiveMissing.id }))
        let preservedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))

        #expect(hydratedMissing.usage?.window(.session)?.usedPercent == 46)
        #expect(hydratedMissing.email == "missing@example.com")
        #expect(preservedReady.usage != nil)
        #expect(auth.recordedSnapshotReads() == [inactiveMissing.id])
        #expect(auth.currentAuthDataString() == "active-auth")
        #expect(result.activeAccountID == active.id)
        #expect(result.hydratedAccountIDs == [inactiveMissing.id])
        #expect(repository.savedAccounts == result.accounts)
    }

    @Test
    func runSkipsWhenNoInactiveAccountsNeedHydration() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", planType: "pro", usage: makeUsageSnapshot())
        let inactive = makeAccount(name: "Ready", fingerprint: "ready", planType: "pro", usage: makeUsageSnapshot())
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [:], authService: auth),
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [:], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "active"),
                storedAccountReconciler: PassthroughIdentityReconciler()
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
        let active = makeAccount(name: "Active", fingerprint: "active", planType: "pro", usage: makeUsageSnapshot())
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", planType: "pro", usage: makeUsageSnapshot())
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let refreshedRateLimits = UsageSnapshot.codex(
            planName: "team",
            primary: (usedPercent: 12, resetsAt: Date(timeIntervalSince1970: 1_776_256_138), durationMinutes: 300),
            secondary: (usedPercent: 3, resetsAt: Date(timeIntervalSince1970: 1_776_842_938), durationMinutes: 10_080),
            fetchedAt: Date(timeIntervalSince1970: 1_776_300_000)
        )
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "ready": CodexAccountStatus(
                    email: "fresh-ready@example.com",
                    planType: "team",
                    usage: refreshedRateLimits
                )
            ], authService: auth),
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "ready": CodexAccountStatus(
                    email: "fresh-ready@example.com",
                    planType: "team",
                    usage: refreshedRateLimits
                )
            ], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "active"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveReady],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        let refreshedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))
        #expect(refreshedReady.usage == refreshedRateLimits)
        #expect(refreshedReady.email == "fresh-ready@example.com")
        #expect(refreshedReady.planType == "team")
        #expect(refreshedReady.identity.snapshotFingerprint == "ready")
        #expect(auth.storedSnapshot(for: inactiveReady.id) == nil)
        #expect(auth.recordedSnapshotReads() == [inactiveReady.id])
        #expect(auth.currentAuthDataString() == "active-auth")
        #expect(result.activeAccountID == active.id)
        #expect(result.hydratedAccountIDs == [inactiveReady.id])
        #expect(repository.savedAccounts == result.accounts)
    }

    @Test
    func runBackfillsInactiveAccountsWithWeeklyOnlyRateLimits() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", planType: "pro", usage: makeUsageSnapshot())
        let inactiveMissing = makeAccount(name: "Missing", email: nil, fingerprint: "missing")
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let primaryOnlyRateLimits = UsageSnapshot.codex(
            planName: "free",
            primary: (usedPercent: 9, resetsAt: Date(timeIntervalSince1970: 1_776_256_138), durationMinutes: 10_080),
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
                    usage: primaryOnlyRateLimits
                )
            ], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "active"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveMissing],
            activeAccountID: active.id
        )

        let hydratedMissing = try #require(result.accounts.first(where: { $0.id == inactiveMissing.id }))
        #expect(hydratedMissing.usage == primaryOnlyRateLimits)
        #expect(hydratedMissing.email == "missing@example.com")
        #expect(hydratedMissing.planType == "free")
        #expect(result.hydratedAccountIDs == [inactiveMissing.id])
        #expect(repository.savedAccounts == result.accounts)
    }

    @Test
    func runDoesNotMarkPreservedInactiveRateLimitsFreshWhenRefreshReturnsNoRateLimits() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", planType: "pro", usage: makeUsageSnapshot())
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", planType: "pro", usage: makeUsageSnapshot())
        let originalUpdatedAt = inactiveReady.updatedAt
        let originalRateLimits = try #require(inactiveReady.usage)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "ready": CodexAccountStatus(
                    email: inactiveReady.email,
                    planType: inactiveReady.planType,
                    usage: nil
                )
            ], authService: auth),
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "ready": CodexAccountStatus(
                    email: inactiveReady.email,
                    planType: inactiveReady.planType,
                    usage: nil
                )
            ], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "active"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveReady],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        let refreshedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))
        #expect(refreshedReady.usage == originalRateLimits)
        #expect(refreshedReady.updatedAt == originalUpdatedAt)
        #expect(auth.recordedSnapshotReads() == [inactiveReady.id])
        #expect(auth.currentAuthDataString() == "active-auth")
        #expect(result.hydratedAccountIDs.isEmpty)
        #expect(repository.savedAccounts == nil)
    }

    @Test(arguments: [
        CodexAccountStatus(email: "ready@example.com", planType: "pro", usage: nil),
        CodexAccountStatus(email: "ready@example.com", planType: "pro", usage: UsageSnapshot.codex(
            planName: "pro",
            primary: (usedPercent: 0, resetsAt: .now.addingTimeInterval(60 * 60), durationMinutes: 300),
            secondary: (usedPercent: 0, resetsAt: .now.addingTimeInterval(7 * 24 * 60 * 60), durationMinutes: 10_080),
            fetchedAt: .now
        ))
    ])
    func runPreservesPreviousMeaningfulRateLimitsWhenIsolatedReadIsNotUsable(status: CodexAccountStatus) async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", planType: "pro", usage: makeUsageSnapshot())
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", planType: "pro", usage: makeUsageSnapshot())
        let originalRateLimits = try #require(inactiveReady.usage)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [:], authService: auth),
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: ["ready": status], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "active"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveReady],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        let refreshedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))
        #expect(refreshedReady.usage == originalRateLimits)
        #expect(auth.currentAuthDataString() == "active-auth")
        #expect(result.hydratedAccountIDs.isEmpty)
    }

    @Test
    func runPreservesPreviousMeaningfulRateLimitsWhenIsolatedReadFails() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", planType: "pro", usage: makeUsageSnapshot())
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", planType: "pro", usage: makeUsageSnapshot())
        let originalRateLimits = try #require(inactiveReady.usage)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationCatalogProbe()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [:], authService: auth),
            savedAccountStatusClient: HydrationFailingSavedStatusProbe(),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "active"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveReady],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        let refreshedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))
        #expect(refreshedReady.usage == originalRateLimits)
        #expect(auth.currentAuthDataString() == "active-auth")
        #expect(result.hydratedAccountIDs.isEmpty)
    }

    @Test
    func runWritesRotatedAuthBackToTheMatchingSavedAccount() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", planType: "pro", usage: makeUsageSnapshot())
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", stableAccountID: "acct-ready", planType: "pro", usage: makeUsageSnapshot())
        let rotatedAuthData = Data("ready-rotated".utf8)
        let auth = HydrationAuthSnapshotProbe(
            currentAuthData: Data("active-auth".utf8),
            identitiesByAuthData: [
                rotatedAuthData: LiveCodexAccountIdentity(stableAccountID: "acct-ready", snapshotFingerprint: "ready-rotated")
            ]
        )
        let repository = HydrationCatalogProbe()
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationAccountStatusProbe(
                statusByFingerprint: ["ready": CodexAccountStatus(
                    email: "ready@example.com",
                    planType: "pro",
                    usage: makeUsageSnapshot()
                )],
                authService: auth,
                rotatedAuthDataByFingerprint: ["ready": rotatedAuthData]
            ),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveReady],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        let refreshedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))
        #expect(auth.storedSnapshot(for: inactiveReady.id) == rotatedAuthData)
        #expect(refreshedReady.identity.snapshotFingerprint == "ready-rotated")
        #expect(refreshedReady.usage == makeUsageSnapshot())
        #expect(repository.savedAccounts == result.accounts)
    }

    @Test(arguments: ["acct-other", "acct-unknown"])
    func runDiscardsRotatedAuthThatDoesNotResolveToTheReadAccount(rotatedStableAccountID: String) async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", planType: "pro", usage: makeUsageSnapshot())
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", stableAccountID: "acct-ready", planType: "pro", usage: makeUsageSnapshot())
        let inactiveOther = makeAccount(name: "Other", fingerprint: "other", stableAccountID: "acct-other", planType: "pro", usage: makeUsageSnapshot())
        let rotatedAuthData = Data("ready-rotated".utf8)
        let auth = HydrationAuthSnapshotProbe(
            currentAuthData: Data("active-auth".utf8),
            identitiesByAuthData: [
                rotatedAuthData: LiveCodexAccountIdentity(stableAccountID: rotatedStableAccountID, snapshotFingerprint: "ready-rotated")
            ]
        )
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationAccountStatusProbe(
                statusByFingerprint: [:],
                authService: auth,
                rotatedAuthDataByFingerprint: ["ready": rotatedAuthData]
            ),
            repository: HydrationCatalogProbe()
        )

        let result = try await useCase.run(
            accounts: [active, inactiveReady, inactiveOther],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        #expect(auth.storedSnapshot(for: inactiveReady.id) == nil)
        #expect(auth.storedSnapshot(for: inactiveOther.id) == nil)
        #expect(result.accounts == [active, inactiveReady, inactiveOther])
    }

    @Test
    func runWritesRotatedAuthBackWhenIsolatedReadFails() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", planType: "pro", usage: makeUsageSnapshot())
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", stableAccountID: "acct-ready", planType: "pro", usage: makeUsageSnapshot())
        let rotatedAuthData = Data("ready-rotated".utf8)
        let auth = HydrationAuthSnapshotProbe(
            currentAuthData: Data("active-auth".utf8),
            identitiesByAuthData: [
                rotatedAuthData: LiveCodexAccountIdentity(stableAccountID: "acct-ready", snapshotFingerprint: "ready-rotated")
            ]
        )
        let repository = HydrationCatalogProbe()
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationFailingSavedStatusProbe(rotatedAuthData: rotatedAuthData),
            repository: repository
        )

        let result = try await useCase.run(
            accounts: [active, inactiveReady],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        let refreshedReady = try #require(result.accounts.first(where: { $0.id == inactiveReady.id }))
        #expect(auth.storedSnapshot(for: inactiveReady.id) == rotatedAuthData)
        #expect(refreshedReady.identity.snapshotFingerprint == "ready-rotated")
        #expect(refreshedReady.usage == inactiveReady.usage)
        #expect(refreshedReady.updatedAt == inactiveReady.updatedAt)
        #expect(result.hydratedAccountIDs.isEmpty)
        #expect(repository.savedAccounts == result.accounts)
    }

    private func makeUseCase(
        auth: HydrationAuthSnapshotProbe,
        savedAccountStatusClient: SavedCodexAccountStatusClient,
        repository: HydrationCatalogProbe
    ) -> HydrateSavedAccountsMetadataUseCase {
        HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            accountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [:], authService: auth),
            savedAccountStatusClient: savedAccountStatusClient,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: LiveIdentityStub(fingerprint: "active"),
                storedAccountReconciler: PassthroughIdentityReconciler()
            ),
            repository: repository
        )
    }

    private func makeUsageSnapshot() -> UsageSnapshot {
        UsageSnapshot.codex(
            planName: "pro",
            primary: (usedPercent: 46, resetsAt: Date(timeIntervalSince1970: 1_776_256_138), durationMinutes: 300),
            secondary: (usedPercent: 7, resetsAt: Date(timeIntervalSince1970: 1_776_842_938), durationMinutes: 10_080),
            fetchedAt: Date(timeIntervalSince1970: 1_776_200_000)
        )
    }
}

private final class HydrationAuthSnapshotProbe: CodexAuthSessionStore, @unchecked Sendable {
    private var currentAuthData: Data
    private var accountsByID: [UUID: CodexAccount] = [:]
    private var snapshotReadIDs: [UUID] = []
    private var storedSnapshotsByAccountID: [UUID: Data] = [:]
    private let identitiesByAuthData: [Data: LiveCodexAccountIdentity]

    init(currentAuthData: Data, identitiesByAuthData: [Data: LiveCodexAccountIdentity] = [:]) {
        self.currentAuthData = currentAuthData
        self.identitiesByAuthData = identitiesByAuthData
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
        return storedSnapshotsByAccountID[account.id] ?? Data((account.identity.snapshotFingerprint ?? "").utf8)
    }

    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
        var account = try #require(existing)
        let identity = liveIdentity(forAuthData: authData)
        account.name = name
        account.updatedAt = .now
        account.identity.stableAccountID = identity.stableAccountID
        account.identity.snapshotFingerprint = identity.snapshotFingerprint
        storedSnapshotsByAccountID[account.id] = authData
        return account
    }

    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity {
        identitiesByAuthData[authData] ?? LiveCodexAccountIdentity(snapshotFingerprint: String(decoding: authData, as: UTF8.self))
    }

    func storedSnapshot(for accountID: UUID) -> Data? {
        storedSnapshotsByAccountID[accountID]
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
    var rotatedAuthDataByFingerprint: [String: Data] = [:]

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        let fingerprint = authService.currentFingerprint()
        guard let status = statusByFingerprint[fingerprint] else {
            throw NSError(domain: "HydrationAccountStatusProbe", code: 1)
        }
        return status
    }

    func readSavedAccountStatus(authData: Data) async -> SavedCodexAccountStatusRead {
        let fingerprint = String(decoding: authData, as: UTF8.self)
        let status: Result<CodexAccountStatus, Error> = statusByFingerprint[fingerprint].map { .success($0) }
            ?? .failure(NSError(domain: "HydrationAccountStatusProbe", code: 1))
        return SavedCodexAccountStatusRead(status: status, rotatedAuthData: rotatedAuthDataByFingerprint[fingerprint])
    }
}

private struct HydrationFailingSavedStatusProbe: SavedCodexAccountStatusClient {
    var rotatedAuthData: Data?

    func readSavedAccountStatus(authData: Data) async -> SavedCodexAccountStatusRead {
        SavedCodexAccountStatusRead(
            status: .failure(NSError(domain: "HydrationFailingSavedStatusProbe", code: 1)),
            rotatedAuthData: rotatedAuthData
        )
    }
}

private final class HydrationCatalogProbe: AccountCatalogStore, @unchecked Sendable {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}
