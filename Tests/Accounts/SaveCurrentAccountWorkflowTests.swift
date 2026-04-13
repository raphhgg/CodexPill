import Foundation
import Testing

@testable import CodexPill

struct SaveCurrentAccountWorkflowTests {
    @Test
    func runReadsStatusSavesSnapshotPersistsAccountAndReturnsActiveID() async throws {
        let remote = CodexAccountStatus(
            email: "person@example.com",
            planType: "pro",
            rateLimits: nil
        )
        let saved = makeAccount(name: "Work", fingerprint: "live-fingerprint")

        let appServer = AppServerSpy(status: remote)
        let auth = SnapshotSaveSpy(savedAccount: saved)
        let repository = RepositorySpy()
        let workflow = SaveCurrentAccountWorkflow(
            appServerClient: appServer,
            authService: auth,
            repository: repository,
            identityResolver: SavedAccountIdentityResolver(
                liveIdentityReader: FixedIdentityReader(identity: LiveCodexAccountIdentity(account: saved)),
                storedAccountReconciler: ReconcilePassthrough()
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
        #expect(result.savedAccount.resolvedRemoteIdentity == CodexRemoteAccountIdentity(emailAddress: "person@example.com"))
        #expect(result.activeAccountID == saved.id)
    }

    @Test
    func runRejectsDuplicateNameCaseInsensitively() async {
        let existing = makeAccount(name: "Work", fingerprint: "existing")
        let workflow = SaveCurrentAccountWorkflow(
            appServerClient: AppServerSpy(status: CodexAccountStatus(email: "new@example.com", planType: nil, rateLimits: nil)),
            authService: SnapshotSaveSpy(savedAccount: makeAccount(name: "work", fingerprint: "new")),
            repository: RepositorySpy(),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentityReader: FixedIdentityReader(identity: .empty),
                storedAccountReconciler: ReconcilePassthrough()
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
        let auth = SnapshotSaveSpy(savedAccount: makeAccount(name: "ignored", fingerprint: "live-fingerprint"))
        let workflow = SaveCurrentAccountWorkflow(
            appServerClient: AppServerSpy(status: remote),
            authService: auth,
            repository: RepositorySpy(),
            identityResolver: SavedAccountIdentityResolver(
                liveIdentityReader: FixedIdentityReader(identity: LiveCodexAccountIdentity(account: auth.savedAccount)),
                storedAccountReconciler: ReconcilePassthrough()
            )
        )

        _ = try await workflow.run(
            customName: "   ",
            existingAccounts: []
        )

        #expect(auth.savedNames == ["person@example.com"])
    }

    private func makeAccount(name: String, fingerprint: String) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "\(name.lowercased())@example.com",
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: fingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com")
            )
        )
    }
}

private final class AppServerSpy: CodexAccountStatusReading {
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

private final class SnapshotSaveSpy: CodexAuthSnapshotSaving {
    let savedAccount: CodexAccount
    var savedNames: [String] = []

    init(savedAccount: CodexAccount) {
        self.savedAccount = savedAccount
    }

    func saveCurrentAuthSnapshot(named name: String, existing: CodexAccount?) throws -> CodexAccount {
        savedNames.append(name)
        return savedAccount
    }
}

private final class RepositorySpy: AccountCatalogPersisting {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}

private struct FixedIdentityReader: LiveCodexAccountIdentityReading {
    let identity: LiveCodexAccountIdentity

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        identity
    }
}

private struct ReconcilePassthrough: StoredAccountIdentityReconciling {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
