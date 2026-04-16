import Foundation
import Testing

@testable import CodexPill

struct HydrateSavedAccountsMetadataUseCaseTests {
    @Test
    func runBackfillsInactiveAccountsMissingRateLimitsAndRestoresOriginalAuth() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: true)
        let inactiveMissing = makeAccount(name: "Missing", fingerprint: "missing", withRateLimits: false)
        let inactiveReady = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let auth = HydrationAuthSpy(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationRepositorySpy()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            appServerClient: HydrationAppServerSpy(statusByFingerprint: [
                "missing": CodexAccountStatus(
                    email: "missing@example.com",
                    planType: "pro",
                    rateLimits: makeRateLimitsSnapshot()
                )
            ], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentityReader: HydrationIdentityReader(activeFingerprint: "active"),
                storedAccountReconciler: HydrationReconcilePassthrough()
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
        #expect(auth.recordedActivations() == [inactiveMissing.id])
        #expect(auth.currentAuthDataString() == "active-auth")
        #expect(result.activeAccountID == active.id)
        #expect(result.hydratedAccountIDs == [inactiveMissing.id])
        #expect(repository.savedAccounts == result.accounts)
    }

    @Test
    func runSkipsWhenNoInactiveAccountsNeedHydration() async throws {
        let active = makeAccount(name: "Active", fingerprint: "active", withRateLimits: true)
        let inactive = makeAccount(name: "Ready", fingerprint: "ready", withRateLimits: true)
        let auth = HydrationAuthSpy(currentAuthData: Data("active-auth".utf8))
        let repository = HydrationRepositorySpy()
        let useCase = HydrateSavedAccountsMetadataUseCase(
            authService: auth,
            appServerClient: HydrationAppServerSpy(statusByFingerprint: [:], authService: auth),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentityReader: HydrationIdentityReader(activeFingerprint: "active"),
                storedAccountReconciler: HydrationReconcilePassthrough()
            ),
            repository: repository
        )

        let result = try await useCase.run(accounts: [active, inactive], activeAccountID: active.id)

        #expect(result.accounts == [active, inactive])
        #expect(result.activeAccountID == active.id)
        #expect(result.hydratedAccountIDs.isEmpty)
        #expect(repository.savedAccounts == nil)
        #expect(auth.recordedActivations().isEmpty)
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

private final class HydrationAuthSpy: CodexAuthDataRestoring {
    private var currentAuthData: Data
    private var accountsByID: [UUID: CodexAccount] = [:]
    private var activationIDs: [UUID] = []

    init(currentAuthData: Data) {
        self.currentAuthData = currentAuthData
    }

    func readCurrentAuthData() throws -> Data {
        currentAuthData
    }

    func restoreCurrentAuthData(_ data: Data) throws {
        currentAuthData = data
    }

    func activate(_ account: CodexAccount) throws {
        accountsByID[account.id] = account
        activationIDs.append(account.id)
        currentAuthData = Data((account.identity.snapshotFingerprint ?? "").utf8)
    }

    func currentFingerprint() -> String {
        String(decoding: currentAuthData, as: UTF8.self)
    }

    func recordedActivations() -> [UUID] {
        activationIDs
    }

    func currentAuthDataString() -> String {
        String(decoding: currentAuthData, as: UTF8.self)
    }
}

private struct HydrationAppServerSpy: CodexAccountStatusReading {
    let statusByFingerprint: [String: CodexAccountStatus]
    let authService: HydrationAuthSpy

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        let fingerprint = authService.currentFingerprint()
        guard let status = statusByFingerprint[fingerprint] else {
            throw NSError(domain: "HydrationAppServerSpy", code: 1)
        }
        return status
    }
}

private final class HydrationRepositorySpy: AccountCatalogPersisting {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}

private struct HydrationIdentityReader: LiveCodexAccountIdentityReading {
    let activeFingerprint: String

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: activeFingerprint)
    }
}

private struct HydrationReconcilePassthrough: StoredAccountIdentityReconciling {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
