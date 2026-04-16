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

    @Test
    func resolvePrefersScopedPrincipalIdentityWhenStableAccountIDIsShared() {
        let businessOne = makeAccount(
            name: "Business 1",
            fingerprint: "business-one-fingerprint",
            email: "admin@raphh.me",
            stableAccountID: "acct-team",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-1",
                chatGPTUserID: "user-business-1"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-1",
                workspaceLabel: "Personal"
            )
        )
        let businessFour = makeAccount(
            name: "Business 4",
            fingerprint: "business-four-fingerprint",
            email: "raphaelgrau@icloud.com",
            stableAccountID: "acct-team",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-4",
                chatGPTUserID: "user-business-4"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-4",
                workspaceLabel: "Personal"
            )
        )
        let resolver = SavedAccountIdentityResolver(
            liveIdentityReader: LiveIdentitySpy(
                currentFingerprint: nil,
                stableAccountID: "acct-team",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|business-4",
                    chatGPTUserID: "user-business-4"
                )
            ),
            storedAccountReconciler: ReconcilePassthrough()
        )

        let result = resolver.resolve(accounts: [businessOne, businessFour])

        #expect(result == .exactScopedStableAccountID(businessFour.id))
    }

    @Test
    func resolveDoesNotFallbackToRemoteIdentityWhenScopedStableCandidatesDisagree() {
        let businessOne = makeAccount(
            name: "Business 1",
            fingerprint: "business-one-fingerprint",
            email: "admin@raphh.me",
            stableAccountID: "acct-team",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-1",
                chatGPTUserID: "user-business-1"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-1",
                workspaceLabel: "Personal"
            )
        )
        let businessFour = makeAccount(
            name: "Business 4",
            fingerprint: "business-four-fingerprint",
            email: "raphaelgrau@icloud.com",
            stableAccountID: "acct-team",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-4",
                chatGPTUserID: "user-business-4"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-4",
                workspaceLabel: "Personal"
            )
        )
        let resolver = SavedAccountIdentityResolver(
            liveIdentityReader: LiveIdentitySpy(
                currentFingerprint: nil,
                stableAccountID: "acct-team",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|other-business",
                    chatGPTUserID: "user-other-business"
                )
            ),
            storedAccountReconciler: ReconcilePassthrough()
        )

        let result = resolver.resolve(
            accounts: [businessOne, businessFour],
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "admin@raphh.me")
        )

        #expect(result == .noMatch)
    }

    private func makeAccount(
        name: String,
        fingerprint: String,
        email: String,
        stableAccountID: String? = nil,
        authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil,
        workspaceIdentity: CodexWorkspaceIdentity? = nil
    ) -> CodexAccount {
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
                stableAccountID: stableAccountID,
                authPrincipalIdentity: authPrincipalIdentity,
                workspaceIdentity: workspaceIdentity,
                snapshotFingerprint: fingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}

private struct LiveIdentitySpy: LiveCodexAccountIdentityReading {
    let currentFingerprint: String?
    let stableAccountID: String?
    let authPrincipalIdentity: CodexAuthPrincipalIdentity?
    let workspaceIdentity: CodexWorkspaceIdentity? = nil

    init(
        currentFingerprint: String?,
        stableAccountID: String?,
        authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil
    ) {
        self.currentFingerprint = currentFingerprint
        self.stableAccountID = stableAccountID
        self.authPrincipalIdentity = authPrincipalIdentity
    }

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
