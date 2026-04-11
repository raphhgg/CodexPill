import Foundation
import Testing

@testable import CodexPill

struct CodexAccountMatcherTests {
    private let matcher = CodexAccountMatcher()

    @Test
    func exactSnapshotMatchWinsOverRemoteIdentityFallback() {
        let exact = makeAccount(
            email: "exact@example.com",
            snapshotFingerprint: "live-fingerprint"
        )
        let fallback = makeAccount(
            email: "current@example.com",
            snapshotFingerprint: "other-fingerprint"
        )

        let outcome = matcher.match(
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
            snapshotFingerprint: "saved-fingerprint"
        )

        let outcome = matcher.match(
            liveAuthFingerprint: "different-fingerprint",
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "PERSON@example.com"),
            accounts: [account]
        )

        #expect(outcome == .uniqueRemoteIdentity(account.id))
    }

    @Test
    func ambiguousRemoteIdentityIsExplicit() {
        let first = makeAccount(email: "shared@example.com", snapshotFingerprint: "one")
        let second = makeAccount(email: "shared@example.com", snapshotFingerprint: "two")

        let outcome = matcher.match(
            liveAuthFingerprint: nil,
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "shared@example.com"),
            accounts: [first, second]
        )

        #expect(outcome == .ambiguousRemoteIdentity([first.id, second.id].sorted { $0.uuidString < $1.uuidString }))
    }

    @Test
    func noMatchIsExplicitWhenNoTrustedSignalMatches() {
        let account = makeAccount(email: "saved@example.com", snapshotFingerprint: "saved-fingerprint")

        let outcome = matcher.match(
            liveAuthFingerprint: "other-fingerprint",
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: "other@example.com"),
            accounts: [account]
        )

        #expect(outcome == .noMatch)
    }

    private func makeAccount(
        email: String,
        snapshotFingerprint: String
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
                snapshotFingerprint: snapshotFingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}
