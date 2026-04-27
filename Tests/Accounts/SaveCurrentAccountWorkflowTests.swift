import Foundation
import Testing

@testable import CodexPill

struct SaveCurrentAccountWorkflowTests {
    @Test
    func runReadsStatusSavesSnapshotPersistsAccountAndReturnsActiveID() async throws {
        let remote = CodexAccountStatus(
            email: "person@example.com",
            planType: "pro",
            rateLimits: makeRateLimitsSnapshot()
        )
        let saved = makeAccount(name: "Work", fingerprint: "live-fingerprint")

        let appServer = AccountStatusProbe(status: remote)
        let auth = AuthSnapshotProbe(savedAccount: saved)
        let repository = AccountCatalogProbe()
        let workflow = SaveCurrentAccountWorkflow(
            accountStatusClient: appServer,
            authService: auth,
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: ConstantIdentitySource(identity: LiveCodexAccountIdentity(account: saved)),
                storedAccountReconciler: IdentityReconcilerAdapter()
            )
        )

        let result = try await workflow.run(
            customName: "Work",
            existingAccounts: []
        )

        #expect(appServer.readCount == 1)
        #expect(auth.savedNames == ["Work"])
        #expect(repository.savedAccounts?.count == 1)
        #expect(repository.savedAccounts?.first?.email == "person@example.com")
        #expect(repository.savedAccounts?.first?.rateLimits == remote.rateLimits)
        #expect(result.savedAccount.resolvedRemoteIdentity == CodexRemoteAccountIdentity(emailAddress: "person@example.com"))
        #expect(result.activeAccountID == saved.id)
    }

    @Test
    func runRejectsDuplicateNameCaseInsensitively() async {
        let existing = makeAccount(name: "Work", fingerprint: "existing")
        let workflow = SaveCurrentAccountWorkflow(
            accountStatusClient: AccountStatusProbe(status: CodexAccountStatus(email: "new@example.com", planType: nil, rateLimits: nil)),
            authService: AuthSnapshotProbe(savedAccount: makeAccount(name: "work", fingerprint: "new")),
            repository: AccountCatalogProbe(),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: ConstantIdentitySource(identity: .empty),
                storedAccountReconciler: IdentityReconcilerAdapter()
            )
        )

        await #expect(throws: SaveCurrentAccountWorkflowError.duplicateAccountName) {
            try await workflow.run(
                customName: "work",
                existingAccounts: [existing]
            )
        }
    }

    @Test
    func runFallsBackToRemoteEmailWhenCustomNameIsBlank() async throws {
        let remote = CodexAccountStatus(
            email: "person@example.com",
            planType: nil,
            rateLimits: nil
        )
        let auth = AuthSnapshotProbe(savedAccount: makeAccount(name: "ignored", fingerprint: "live-fingerprint"))
        let workflow = SaveCurrentAccountWorkflow(
            accountStatusClient: AccountStatusProbe(status: remote),
            authService: auth,
            repository: AccountCatalogProbe(),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: ConstantIdentitySource(identity: LiveCodexAccountIdentity(account: auth.savedAccount)),
                storedAccountReconciler: IdentityReconcilerAdapter()
            )
        )

        _ = try await workflow.run(
            customName: "   ",
            existingAccounts: []
        )

        #expect(auth.savedNames == ["person@example.com"])
    }

    @Test
    func runUpdatesMatchedExistingAccountInsteadOfCreatingDuplicate() async throws {
        let existing = makeAccount(
            name: "Business 5",
            email: "raphaelgrau@proton.me",
            fingerprint: "stale-fingerprint",
            stableAccountID: "stable-business",
            subject: "auth0|business-5",
            chatGPTUserID: "user-business-5",
            workspaceAccountID: "org-business-5"
        )
        let remote = CodexAccountStatus(
            email: "raphaelgrau@proton.me",
            planType: "team",
            rateLimits: makeRateLimitsSnapshot()
        )
        let refreshed = makeAccount(
            id: existing.id,
            name: "Business 5",
            email: nil,
            fingerprint: "fresh-fingerprint",
            stableAccountID: "stable-business",
            subject: "auth0|business-5",
            chatGPTUserID: "user-business-5",
            workspaceAccountID: "org-business-5"
        )

        let auth = AuthSnapshotProbe(savedAccount: refreshed)
        let repository = AccountCatalogProbe()
        let workflow = SaveCurrentAccountWorkflow(
            accountStatusClient: AccountStatusProbe(status: remote),
            authService: auth,
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: ConstantIdentitySource(identity: LiveCodexAccountIdentity(account: existing)),
                storedAccountReconciler: IdentityReconcilerAdapter()
            )
        )

        let result = try await workflow.run(
            customName: "Business 5",
            existingAccounts: [existing]
        )

        #expect(auth.savedExistingAccountIDs == [existing.id])
        #expect(repository.savedAccounts?.count == 1)
        #expect(repository.savedAccounts?.first?.id == existing.id)
        #expect(repository.savedAccounts?.first?.email == "raphaelgrau@proton.me")
        #expect(repository.savedAccounts?.first?.planType == "team")
        #expect(repository.savedAccounts?.first?.identity.snapshotFingerprint == "fresh-fingerprint")
        #expect(result.savedAccount.id == existing.id)
        #expect(result.activeAccountID == existing.id)
    }

    @Test
    func runDoesNotReuseExistingAccountBasedOnlyOnSharedEmail() async throws {
        let personal = makeAccount(
            name: "Personal",
            email: "raphaelgrau@gmail.com",
            fingerprint: "personal-fingerprint",
            stableAccountID: "personal-account",
            subject: "auth0|personal",
            chatGPTUserID: "user-personal",
            workspaceAccountID: "org-personal"
        )
        let business = makeAccount(
            name: "Business 2",
            email: nil,
            fingerprint: "business-fingerprint",
            stableAccountID: "business-account",
            subject: "auth0|business",
            chatGPTUserID: "user-business",
            workspaceAccountID: "org-business"
        )
        let remote = CodexAccountStatus(
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: makeRateLimitsSnapshot()
        )

        let auth = AuthSnapshotProbe(savedAccount: business)
        let repository = AccountCatalogProbe()
        let workflow = SaveCurrentAccountWorkflow(
            accountStatusClient: AccountStatusProbe(status: remote),
            authService: auth,
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: ConstantIdentitySource(
                    identity: LiveCodexAccountIdentity(
                        stableAccountID: nil,
                        authPrincipalIdentity: nil,
                        workspaceIdentity: nil,
                        snapshotFingerprint: nil,
                        remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@gmail.com")
                    )
                ),
                storedAccountReconciler: IdentityReconcilerAdapter()
            )
        )

        let result = try await workflow.run(
            customName: "Business 2",
            existingAccounts: [personal]
        )

        #expect(auth.savedExistingAccountIDs == [nil])
        #expect(repository.savedAccounts?.count == 2)
        #expect(repository.savedAccounts?.contains(where: { $0.id == personal.id && $0.name == "Personal" }) == true)
        #expect(repository.savedAccounts?.contains(where: { $0.id == business.id && $0.name == "Business 2" }) == true)
        #expect(result.activeAccountID == business.id)
    }

    @Test
    func runRejectsRenameWhenMatchedExistingWouldCollideWithAnotherSavedAccount() async {
        let existing = makeAccount(
            name: "Business 5",
            email: "raphaelgrau@proton.me",
            fingerprint: "stale-fingerprint",
            stableAccountID: "stable-business",
            subject: "auth0|business-5",
            chatGPTUserID: "user-business-5",
            workspaceAccountID: "org-business-5"
        )
        let other = makeAccount(
            name: "Business 4",
            email: "raphaelgrau@icloud.com",
            fingerprint: "other-fingerprint"
        )
        let workflow = SaveCurrentAccountWorkflow(
            accountStatusClient: AccountStatusProbe(status: CodexAccountStatus(email: "raphaelgrau@proton.me", planType: "team", rateLimits: nil)),
            authService: AuthSnapshotProbe(savedAccount: existing),
            repository: AccountCatalogProbe(),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentitySource: ConstantIdentitySource(identity: LiveCodexAccountIdentity(account: existing)),
                storedAccountReconciler: IdentityReconcilerAdapter()
            )
        )

        await #expect(throws: SaveCurrentAccountWorkflowError.duplicateAccountName) {
            try await workflow.run(
                customName: "Business 4",
                existingAccounts: [existing, other]
            )
        }
    }

    private func makeAccount(
        id: UUID = UUID(),
        name: String,
        email: String? = nil,
        fingerprint: String,
        stableAccountID: String? = nil,
        subject: String? = nil,
        chatGPTUserID: String? = nil,
        workspaceAccountID: String? = nil
    ) -> CodexAccount {
        CodexAccount(
            id: id,
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: email ?? "\(name.lowercased())@example.com",
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: stableAccountID,
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: subject,
                    chatGPTUserID: chatGPTUserID
                ),
                workspaceIdentity: CodexWorkspaceIdentity(
                    workspaceAccountID: workspaceAccountID,
                    workspaceLabel: nil
                ),
                snapshotFingerprint: fingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email ?? "\(name.lowercased())@example.com")
            )
        )
    }

    private func makeRateLimitsSnapshot() -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "pro",
            primary: CodexRateLimitWindow(
                usedPercent: 40,
                resetsAt: Date(timeIntervalSince1970: 1_776_256_138),
                windowDurationMinutes: 300
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 6,
                resetsAt: Date(timeIntervalSince1970: 1_776_842_938),
                windowDurationMinutes: 10_080
            ),
            fetchedAt: Date(timeIntervalSince1970: 1_776_200_000)
        )
    }
}

private final class AccountStatusProbe: CodexAccountStatusClient {
    let status: CodexAccountStatus
    var readCount = 0

    init(status: CodexAccountStatus) {
        self.status = status
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        readCount += 1
        return status
    }
}

private final class AuthSnapshotProbe: CodexAuthSnapshotStore {
    let savedAccount: CodexAccount
    var savedNames: [String] = []
    var savedExistingAccountIDs: [UUID?] = []

    init(savedAccount: CodexAccount) {
        self.savedAccount = savedAccount
    }

    func saveCurrentAuthSnapshot(named name: String, existing: CodexAccount?) throws -> CodexAccount {
        savedNames.append(name)
        savedExistingAccountIDs.append(existing?.id)
        return savedAccount
    }
}

private final class AccountCatalogProbe: AccountCatalogStore {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}

private struct ConstantIdentitySource: LiveCodexAccountIdentitySource {
    let identity: LiveCodexAccountIdentity

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        identity
    }
}

private struct IdentityReconcilerAdapter: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
