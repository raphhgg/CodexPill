import Foundation
import Testing

@testable import CodexPill

struct CodexAccountMatcherTests {
    private let matcher = CodexAccountMatcher()

    @Test
    func exactSnapshotMatchWinsOverRemoteIdentityFallback() {
        let exact = makeAccount(
            email: "exact@example.com",
            snapshotFingerprint: "live-fingerprint",
            stableAccountID: nil
        )
        let fallback = makeAccount(
            email: "current@example.com",
            snapshotFingerprint: "other-fingerprint",
            stableAccountID: nil
        )

        let outcome = matcher.match(
            liveStableAccountID: nil,
            liveAuthPrincipalIdentity: nil,
            liveWorkspaceIdentity: nil,
            liveAuthFingerprint: "live-fingerprint",
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "current@example.com"),
            accounts: [exact, fallback]
        )

        #expect(outcome == .exactSnapshot(exact.id))
    }

    @Test
    func uniqueRemoteIdentityMatchIsUsedWhenNoSnapshotMatchExists() {
        let account = makeAccount(
            email: "person@example.com",
            snapshotFingerprint: "saved-fingerprint",
            stableAccountID: nil
        )

        let outcome = matcher.match(
            liveStableAccountID: nil,
            liveAuthPrincipalIdentity: nil,
            liveWorkspaceIdentity: nil,
            liveAuthFingerprint: "different-fingerprint",
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "PERSON@example.com"),
            accounts: [account]
        )

        #expect(outcome == .uniqueRemoteIdentity(account.id))
    }

    @Test
    func ambiguousRemoteIdentityIsExplicit() {
        let first = makeAccount(email: "shared@example.com", snapshotFingerprint: "one", stableAccountID: nil)
        let second = makeAccount(email: "shared@example.com", snapshotFingerprint: "two", stableAccountID: nil)

        let outcome = matcher.match(
            liveStableAccountID: nil,
            liveAuthPrincipalIdentity: nil,
            liveWorkspaceIdentity: nil,
            liveAuthFingerprint: nil,
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "shared@example.com"),
            accounts: [first, second]
        )

        #expect(outcome == .ambiguousRemoteIdentity([first.id, second.id].sorted { $0.uuidString < $1.uuidString }))
    }

    @Test
    func noMatchIsExplicitWhenNoTrustedSignalMatches() {
        let account = makeAccount(email: "saved@example.com", snapshotFingerprint: "saved-fingerprint", stableAccountID: nil)

        let outcome = matcher.match(
            liveStableAccountID: nil,
            liveAuthPrincipalIdentity: nil,
            liveWorkspaceIdentity: nil,
            liveAuthFingerprint: "other-fingerprint",
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "other@example.com"),
            accounts: [account]
        )

        #expect(outcome == .noMatch)
    }

    @Test
    func stableAccountIDMatchWinsOverFingerprintMismatch() {
        let account = makeAccount(
            email: "saved@example.com",
            snapshotFingerprint: "stale-fingerprint",
            stableAccountID: "acct-123"
        )

        let outcome = matcher.match(
            liveStableAccountID: "acct-123",
            liveAuthPrincipalIdentity: nil,
            liveWorkspaceIdentity: nil,
            liveAuthFingerprint: "different-fingerprint",
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "other@example.com"),
            accounts: [account]
        )

        #expect(outcome == .exactStableAccountID(account.id))
    }

    @Test
    func scopedStableAccountIDMatchWinsWhenWorkspaceIdentityDiffers() {
        let personal = makeAccount(
            email: "shared@example.com",
            snapshotFingerprint: "personal-fingerprint",
            stableAccountID: "acct-123",
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-personal",
                workspaceLabel: "Personal"
            )
        )
        let team = makeAccount(
            email: "shared@example.com",
            snapshotFingerprint: "team-fingerprint",
            stableAccountID: "acct-123",
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-team",
                workspaceLabel: "Team"
            )
        )

        let outcome = matcher.match(
            liveStableAccountID: "acct-123",
            liveAuthPrincipalIdentity: nil,
            liveWorkspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-team",
                workspaceLabel: "Team"
            ),
            liveAuthFingerprint: "different-fingerprint",
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "shared@example.com"),
            accounts: [personal, team]
        )

        #expect(outcome == .exactScopedStableAccountID(team.id))
    }

    @Test
    func scopedStableAccountIDMatchWinsWhenAuthPrincipalDiffers() {
        let businessOne = makeAccount(
            email: "admin@example.com",
            snapshotFingerprint: "business-one",
            stableAccountID: "acct-team",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-1",
                chatGPTUserID: "user-business-1"
            )
        )
        let businessTwo = makeAccount(
            email: "user@example.com",
            snapshotFingerprint: "business-two",
            stableAccountID: "acct-team",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2"
            )
        )

        let outcome = matcher.match(
            liveStableAccountID: "acct-team",
            liveAuthPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2"
            ),
            liveWorkspaceIdentity: nil,
            liveAuthFingerprint: "different-fingerprint",
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "user@example.com"),
            accounts: [businessOne, businessTwo]
        )

        #expect(outcome == .exactScopedStableAccountID(businessTwo.id))
    }

    @Test
    func stableAccountIDDoesNotFallbackWhenScopedPrincipalDoesNotMatch() {
        let businessOne = makeAccount(
            email: "admin@example.com",
            snapshotFingerprint: "business-one",
            stableAccountID: "acct-team",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-1",
                chatGPTUserID: "user-business-1"
            )
        )

        let outcome = matcher.match(
            liveStableAccountID: "acct-team",
            liveAuthPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2"
            ),
            liveWorkspaceIdentity: nil,
            liveAuthFingerprint: "different-fingerprint",
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "user@example.com"),
            accounts: [businessOne]
        )

        #expect(outcome == .noMatch)
    }

    @Test
    func scopedStableMismatchDoesNotFallBackToRemoteIdentity() {
        let personal = makeAccount(
            email: "admin@example.com",
            snapshotFingerprint: "personal-fingerprint",
            stableAccountID: "acct-team",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|personal",
                chatGPTUserID: "user-personal"
            )
        )
        let business = makeAccount(
            email: "user@example.com",
            snapshotFingerprint: "business-fingerprint",
            stableAccountID: "acct-team",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business",
                chatGPTUserID: "user-business"
            )
        )

        let outcome = matcher.match(
            liveStableAccountID: "acct-team",
            liveAuthPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|missing",
                chatGPTUserID: "user-missing"
            ),
            liveWorkspaceIdentity: nil,
            liveAuthFingerprint: "different-fingerprint",
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "user@example.com"),
            accounts: [personal, business]
        )

        #expect(outcome == .noMatch)
    }

    private func makeAccount(
        email: String,
        snapshotFingerprint: String,
        stableAccountID: String?,
        authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil,
        workspaceIdentity: CodexWorkspaceIdentity? = nil
    ) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: email,
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
                snapshotFingerprint: snapshotFingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}
