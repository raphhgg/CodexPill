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
            liveAuthFingerprint: "different-fingerprint",
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "other@example.com"),
            accounts: [account]
        )

        #expect(outcome == .exactStableAccountID(account.id))
    }

    private func makeAccount(
        email: String,
        snapshotFingerprint: String,
        stableAccountID: String?
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
                snapshotFingerprint: snapshotFingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}
