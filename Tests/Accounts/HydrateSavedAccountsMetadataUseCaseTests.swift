import Foundation
import Testing

@testable import rusage

struct HydrateSavedAccountsMetadataUseCaseTests {
    @Test
    func accountIDsToRefreshSkipsTheActiveAccountAndOnlyIncludesFilledAccountsWhenRefreshingExisting() {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: false)
        let missing = makeAccount(name: "Missing", fingerprint: "missing", withRateLimits: false)
        let ready = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [:]),
            repository: HydrationCatalogProbe()
        )

        let missingOnly = useCase.accountIDsToRefresh(
            in: [active, missing, ready],
            activeAccountID: active.id,
            refreshExistingMetadata: false
        )
        let allInactive = useCase.accountIDsToRefresh(
            in: [active, missing, ready],
            activeAccountID: active.id,
            refreshExistingMetadata: true
        )

        #expect(missingOnly == [missing.id])
        #expect(allInactive == [missing.id, ready.id])
    }

    @Test
    func refreshBackfillsMissingMetadataWithoutTouchingLiveAuth() async throws {
        let missing = makeAccount(name: "Missing", fingerprint: "missing", withRateLimits: false)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "missing": CodexAccountStatus(
                    email: "missing@example.com",
                    planType: "pro",
                    usage: makeUsageSnapshot()
                )
            ]),
            repository: HydrationCatalogProbe()
        )

        let update = try #require(await useCase.refresh(missing, among: [missing]))

        #expect(update.accountID == missing.id)
        #expect(update.usage?.window(.session)?.usedPercent == 46)
        #expect(update.email == "missing@example.com")
        #expect(update.planType == "pro")
        #expect(auth.currentAuthDataString() == "active-auth")
    }

    @Test
    func refreshReplacesExistingRateLimitsWithFreshOnes() async throws {
        let ready = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let refreshedRateLimits = UsageSnapshot.codex(
            planName: "team",
            primary: (usedPercent: 12, resetsAt: Date(timeIntervalSince1970: 1_776_256_138), durationMinutes: 300),
            secondary: (usedPercent: 3, resetsAt: Date(timeIntervalSince1970: 1_776_842_938), durationMinutes: 10_080),
            fetchedAt: Date(timeIntervalSince1970: 1_776_300_000)
        )
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "ready": CodexAccountStatus(
                    email: "fresh-ready@example.com",
                    planType: "team",
                    usage: refreshedRateLimits
                )
            ]),
            repository: HydrationCatalogProbe()
        )

        let update = try #require(await useCase.refresh(ready, among: [ready]))

        #expect(update.usage == refreshedRateLimits)
        #expect(update.email == "fresh-ready@example.com")
        #expect(update.planType == "team")
        #expect(update.identity.snapshotFingerprint == "ready")
        #expect(auth.storedSnapshot(for: ready.id) == nil)
        #expect(auth.currentAuthDataString() == "active-auth")
    }

    @Test
    func refreshBackfillsWeeklyOnlyRateLimits() async throws {
        let missing = makeAccount(name: "Missing", fingerprint: "missing", withRateLimits: false)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let primaryOnlyRateLimits = UsageSnapshot.codex(
            planName: "free",
            primary: (usedPercent: 9, resetsAt: Date(timeIntervalSince1970: 1_776_256_138), durationMinutes: 10_080),
            secondary: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_776_200_000)
        )
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: [
                "missing": CodexAccountStatus(
                    email: "missing@example.com",
                    planType: "free",
                    usage: primaryOnlyRateLimits
                )
            ]),
            repository: HydrationCatalogProbe()
        )

        let update = try #require(await useCase.refresh(missing, among: [missing]))

        #expect(update.usage == primaryOnlyRateLimits)
        #expect(update.email == "missing@example.com")
        #expect(update.planType == "free")
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
    func refreshKeepsPreviousRateLimitsWhenIsolatedReadIsNotUsable(status: CodexAccountStatus) async throws {
        let ready = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationAccountStatusProbe(statusByFingerprint: ["ready": status]),
            repository: HydrationCatalogProbe()
        )

        let update = await useCase.refresh(ready, among: [ready])

        #expect(update == nil)
        #expect(auth.currentAuthDataString() == "active-auth")
    }

    @Test
    func refreshKeepsPreviousRateLimitsWhenIsolatedReadFails() async {
        let ready = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let auth = HydrationAuthSnapshotProbe(currentAuthData: Data("active-auth".utf8))
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationFailingSavedStatusProbe(),
            repository: HydrationCatalogProbe()
        )

        let update = await useCase.refresh(ready, among: [ready])

        #expect(update == nil)
        #expect(auth.currentAuthDataString() == "active-auth")
    }

    @Test
    func refreshWritesRotatedAuthBackToTheMatchingSavedAccount() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: true)
        let ready = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true, stableAccountID: "acct-ready")
        let rotatedAuthData = Data("ready-rotated".utf8)
        let auth = HydrationAuthSnapshotProbe(
            currentAuthData: Data("active-auth".utf8),
            identitiesByAuthData: [
                rotatedAuthData: LiveCodexAccountIdentity(stableAccountID: "acct-ready", snapshotFingerprint: "ready-rotated")
            ]
        )
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationAccountStatusProbe(
                statusByFingerprint: ["ready": CodexAccountStatus(
                    email: "ready@example.com",
                    planType: "pro",
                    usage: makeUsageSnapshot()
                )],
                rotatedAuthDataByFingerprint: ["ready": rotatedAuthData]
            ),
            repository: HydrationCatalogProbe()
        )

        let update = try #require(await useCase.refresh(ready, among: [active, ready]))

        #expect(auth.storedSnapshot(for: ready.id) == rotatedAuthData)
        #expect(update.identity.snapshotFingerprint == "ready-rotated")
        #expect(update.usage == makeUsageSnapshot())
    }

    @Test(arguments: ["acct-other", "acct-unknown"])
    func refreshDiscardsRotatedAuthThatDoesNotResolveToTheReadAccount(rotatedStableAccountID: String) async {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: true)
        let ready = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true, stableAccountID: "acct-ready")
        let other = makeAccount(name: "Other", fingerprint: "other", withRateLimits: true, stableAccountID: "acct-other")
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
                rotatedAuthDataByFingerprint: ["ready": rotatedAuthData]
            ),
            repository: HydrationCatalogProbe()
        )

        let update = await useCase.refresh(ready, among: [active, ready, other])

        #expect(update == nil)
        #expect(auth.storedSnapshot(for: ready.id) == nil)
        #expect(auth.storedSnapshot(for: other.id) == nil)
    }

    @Test
    func refreshWritesRotatedAuthBackWhenIsolatedReadFails() async throws {
        let ready = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true, stableAccountID: "acct-ready")
        let rotatedAuthData = Data("ready-rotated".utf8)
        let auth = HydrationAuthSnapshotProbe(
            currentAuthData: Data("active-auth".utf8),
            identitiesByAuthData: [
                rotatedAuthData: LiveCodexAccountIdentity(stableAccountID: "acct-ready", snapshotFingerprint: "ready-rotated")
            ]
        )
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationFailingSavedStatusProbe(rotatedAuthData: rotatedAuthData),
            repository: HydrationCatalogProbe()
        )

        let update = try #require(await useCase.refresh(ready, among: [ready]))

        #expect(auth.storedSnapshot(for: ready.id) == rotatedAuthData)
        #expect(update.identity.snapshotFingerprint == "ready-rotated")
        #expect(update.usage == ready.usage)
        #expect(update.updatedAt == ready.updatedAt)
    }

    @Test
    func refreshDiscardsRotatedAuthWhenTheSavedSnapshotChangedDuringTheRead() async {
        let ready = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true, stableAccountID: "acct-ready")
        let rotatedAuthData = Data("ready-rotated".utf8)
        let resavedAuthData = Data("ready-resaved".utf8)
        let auth = HydrationAuthSnapshotProbe(
            currentAuthData: Data("active-auth".utf8),
            identitiesByAuthData: [
                rotatedAuthData: LiveCodexAccountIdentity(stableAccountID: "acct-ready", snapshotFingerprint: "ready-rotated")
            ]
        )
        let useCase = makeUseCase(
            auth: auth,
            savedAccountStatusClient: HydrationFailingSavedStatusProbe(
                rotatedAuthData: rotatedAuthData,
                duringRead: { auth.storeSnapshot(resavedAuthData, for: ready.id) }
            ),
            repository: HydrationCatalogProbe()
        )

        let update = await useCase.refresh(ready, among: [ready])

        #expect(update == nil)
        #expect(auth.storedSnapshot(for: ready.id) == resavedAuthData)
    }

    @Test
    func saveMergesTheUpdateIntoTheCurrentAccountAndKeepsItsOtherFields() throws {
        let ready = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: false)
        var current = ready
        current.snapshotFileName = "current.json"
        var refreshed = ready
        refreshed.email = "fresh@example.com"
        let repository = HydrationCatalogProbe()
        let useCase = makeUseCase(
            auth: HydrationAuthSnapshotProbe(currentAuthData: Data()),
            savedAccountStatusClient: HydrationFailingSavedStatusProbe(),
            repository: repository
        )

        let saved = try useCase.save(SavedAccountMetadataUpdate(refreshed), into: [current])

        #expect(saved?.map(\.snapshotFileName) == ["current.json"])
        #expect(saved?.map(\.email) == ["fresh@example.com"])
        #expect(repository.savedAccounts?.map(\.snapshotFileName) == ["current.json"])
    }

    @Test
    func saveSkipsAnAccountRemovedSinceTheRefreshStarted() throws {
        let ready = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: false)
        let other = makeAccount(name: "Other", fingerprint: "other", withRateLimits: false)
        let repository = HydrationCatalogProbe()
        let useCase = makeUseCase(
            auth: HydrationAuthSnapshotProbe(currentAuthData: Data()),
            savedAccountStatusClient: HydrationFailingSavedStatusProbe(),
            repository: repository
        )

        let saved = try useCase.save(SavedAccountMetadataUpdate(ready), into: [other])

        #expect(saved == nil)
        #expect(repository.savedAccounts == nil)
    }

    private func makeUseCase(
        auth: HydrationAuthSnapshotProbe,
        savedAccountStatusClient: SavedCodexAccountStatusClient,
        repository: HydrationCatalogProbe
    ) -> HydrateSavedAccountsMetadataUseCase {
        HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            savedAccountStatusClient: savedAccountStatusClient,
            repository: repository
        )
    }

    private func makeAccount(
        name: String,
        fingerprint: String,
        withRateLimits: Bool,
        stableAccountID: String? = nil
    ) -> CodexAccount {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        return CodexAccount(
            id: UUID(),
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: now,
            updatedAt: now,
            email: withRateLimits ? "\(name.lowercased())@example.com" : nil,
            planType: withRateLimits ? "pro" : nil,
            usage: withRateLimits ? makeUsageSnapshot() : nil,
            identity: CodexAccountIdentity(
                stableAccountID: stableAccountID,
                snapshotFingerprint: fingerprint,
                remoteIdentity: withRateLimits ? CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com") : nil
            )
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
        storedSnapshotsByAccountID[account.id] ?? Data((account.identity.snapshotFingerprint ?? "").utf8)
    }

    func replaceAuthSnapshot(_ authData: Data, ifUnchangedFrom expected: Data, for account: CodexAccount) throws -> CodexAccount? {
        guard try readAuthSnapshot(for: account) == expected else { return nil }
        var replaced = account
        let identity = liveIdentity(forAuthData: authData)
        replaced.updatedAt = .now
        replaced.identity.stableAccountID = identity.stableAccountID
        replaced.identity.snapshotFingerprint = identity.snapshotFingerprint
        storedSnapshotsByAccountID[account.id] = authData
        return replaced
    }

    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity {
        identitiesByAuthData[authData] ?? LiveCodexAccountIdentity(snapshotFingerprint: String(decoding: authData, as: UTF8.self))
    }

    func activate(_ account: CodexAccount) throws {
        currentAuthData = try readAuthSnapshot(for: account)
    }

    func storeSnapshot(_ authData: Data, for accountID: UUID) {
        storedSnapshotsByAccountID[accountID] = authData
    }

    func storedSnapshot(for accountID: UUID) -> Data? {
        storedSnapshotsByAccountID[accountID]
    }

    func currentAuthDataString() -> String {
        String(decoding: currentAuthData, as: UTF8.self)
    }
}

private struct HydrationAccountStatusProbe: SavedCodexAccountStatusClient {
    let statusByFingerprint: [String: CodexAccountStatus]
    var rotatedAuthDataByFingerprint: [String: Data] = [:]

    func readSavedAccountStatus(authData: Data) async -> SavedCodexAccountStatusRead {
        let fingerprint = String(decoding: authData, as: UTF8.self)
        let status: Result<CodexAccountStatus, Error> = statusByFingerprint[fingerprint].map { .success($0) }
            ?? .failure(NSError(domain: "HydrationAccountStatusProbe", code: 1))
        return SavedCodexAccountStatusRead(status: status, rotatedAuthData: rotatedAuthDataByFingerprint[fingerprint])
    }
}

private struct HydrationFailingSavedStatusProbe: SavedCodexAccountStatusClient {
    var rotatedAuthData: Data?
    var duringRead: @Sendable () -> Void = {}

    func readSavedAccountStatus(authData: Data) async -> SavedCodexAccountStatusRead {
        duringRead()
        return SavedCodexAccountStatusRead(
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
