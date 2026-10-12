import Foundation
import Testing

@testable import CodexPill

struct SavedAccountIdentityResolverTests {
    @Test
    func resolveUsesCurrentAuthFingerprintByDefault() {
        let account = makeAccount(name: "Work", email: "work@example.com", fingerprint: "live-fingerprint")
        let resolver = SavedAccountIdentityResolver(
            liveIdentitySource: LiveIdentityStub(fingerprint: "live-fingerprint"),
            storedAccountReconciler: PassthroughIdentityReconciler()
        )

        let result = resolver.resolve(accounts: [account])

        #expect(result == .exactSnapshot(account.id))
    }

    @Test
    func resolveFallsBackToRemoteIdentityWhenFingerprintDoesNotMatch() {
        let account = makeAccount(name: "Work", email: "work@example.com", fingerprint: "stale-fingerprint")
        let resolver = SavedAccountIdentityResolver(
            liveIdentitySource: LiveIdentityStub(fingerprint: "live-fingerprint"),
            storedAccountReconciler: PassthroughIdentityReconciler()
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
            email: "admin@example.com",
            fingerprint: "business-one-fingerprint",
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
            email: "team@example.com",
            fingerprint: "business-four-fingerprint",
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
            liveIdentitySource: LiveIdentityStub(
                stableAccountID: "acct-team",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|business-4",
                    chatGPTUserID: "user-business-4"
                )
            ),
            storedAccountReconciler: PassthroughIdentityReconciler()
        )

        let result = resolver.resolve(accounts: [businessOne, businessFour])

        #expect(result == .exactScopedStableAccountID(businessFour.id))
    }

    @Test
    func resolveDoesNotFallbackToRemoteIdentityWhenScopedStableCandidatesDisagree() {
        let businessOne = makeAccount(
            name: "Business 1",
            email: "admin@example.com",
            fingerprint: "business-one-fingerprint",
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
            email: "team@example.com",
            fingerprint: "business-four-fingerprint",
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
            liveIdentitySource: LiveIdentityStub(
                stableAccountID: "acct-team",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|other-business",
                    chatGPTUserID: "user-other-business"
                )
            ),
            storedAccountReconciler: PassthroughIdentityReconciler()
        )

        let result = resolver.resolve(
            accounts: [businessOne, businessFour],
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "admin@example.com")
        )

        #expect(result == .noMatch)
    }
}
