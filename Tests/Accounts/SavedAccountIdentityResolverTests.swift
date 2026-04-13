import Foundation
import Testing

@testable import CodexPill

struct SavedAccountIdentityResolverTests {
    @Test
    func resolveUsesCurrentAuthFingerprintByDefault() {
        let account = makeAccount(name: "Work", fingerprint: "live-fingerprint", email: "work@example.com")
        let resolver = SavedAccountIdentityResolver(
            liveIdentityReader: LiveIdentitySpy(currentFingerprint: "live-fingerprint", stableAccountID: nil),
            storedAccountReconciler: ReconcilePassthrough()
        )

        let result = resolver.resolve(accounts: [account])

        #expect(result == .exactSnapshot(account.id))
    }

    @Test
    func resolveFallsBackToRemoteIdentityWhenFingerprintDoesNotMatch() {
        let account = makeAccount(name: "Work", fingerprint: "stale-fingerprint", email: "work@example.com")
        let resolver = SavedAccountIdentityResolver(
            liveIdentityReader: LiveIdentitySpy(currentFingerprint: "live-fingerprint", stableAccountID: nil),
            storedAccountReconciler: ReconcilePassthrough()
        )

        let result = resolver.resolve(
            accounts: [account],
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "work@example.com")
        )

        #expect(result == .uniqueRemoteIdentity(account.id))
    }

    private func makeAccount(name: String, fingerprint: String, email: String) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: email,
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: nil,
                snapshotFingerprint: fingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}

private struct LiveIdentitySpy: LiveCodexAccountIdentityReading {
    let currentFingerprint: String?
    let stableAccountID: String?
    let authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil
    let workspaceIdentity: CodexWorkspaceIdentity? = nil

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(
            stableAccountID: stableAccountID,
            authPrincipalIdentity: authPrincipalIdentity,
            workspaceIdentity: workspaceIdentity,
            snapshotFingerprint: currentFingerprint
        )
    }
}

private struct ReconcilePassthrough: StoredAccountIdentityReconciling {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
