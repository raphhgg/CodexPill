import Foundation
import Testing

@testable import CodexPill

struct DeleteSavedAccountUseCaseTests {
    @Test
    func runDeletesSnapshotPersistsFilteredAccountsAndRecomputesActiveAccount() throws {
        let current = makeAccount(name: "Current", fingerprint: "live")
        let other = makeAccount(name: "Other", fingerprint: "other")
        let repository = SnapshotDeletingRepositorySpy()
        let resolver = SavedAccountIdentityResolver(
            liveIdentityReader: CurrentFingerprintStub(fingerprint: "other", stableAccountID: nil),
            storedAccountReconciler: ReconcilePassthrough()
        )
        let useCase = DeleteSavedAccountUseCase(repository: repository, identityResolver: resolver)

        let result = try useCase.run(account: current, accounts: [current, other])

        #expect(repository.deletedAccountIDs == [current.id])
        #expect(repository.savedAccounts == [other])
        #expect(result.accounts == [other])
        #expect(result.activeAccountID == other.id)
    }

    private func makeAccount(name: String, fingerprint: String) -> CodexAccount {
        let id = UUID()
        return CodexAccount(
            id: id,
            name: name,
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "\(name.lowercased())@example.com",
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: nil,
                snapshotFingerprint: fingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com")
            )
        )
    }
}

private final class SnapshotDeletingRepositorySpy: AccountSnapshotDeleting {
    var deletedAccountIDs: [UUID] = []
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }

    func deleteSnapshot(for account: CodexAccount) throws {
        deletedAccountIDs.append(account.id)
    }
}

private struct CurrentFingerprintStub: LiveCodexAccountIdentityReading {
    let fingerprint: String?
    let stableAccountID: String?
    let authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil
    let workspaceIdentity: CodexWorkspaceIdentity? = nil

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(
            stableAccountID: stableAccountID,
            authPrincipalIdentity: authPrincipalIdentity,
            workspaceIdentity: workspaceIdentity,
            snapshotFingerprint: fingerprint
        )
    }
}

private struct ReconcilePassthrough: StoredAccountIdentityReconciling {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
