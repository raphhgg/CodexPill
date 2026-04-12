import Foundation
import Testing

@testable import CodexPill

struct ActiveAccountResolverTests {
    @Test
    func resolveUsesCurrentAuthFingerprintByDefault() {
        let account = makeAccount(name: "Work", fingerprint: "live-fingerprint", email: "work@example.com")
        let resolver = ActiveAccountResolver(
            authService: AuthFingerprintSpy(currentFingerprint: "live-fingerprint", stableAccountID: nil)
        )

        let result = resolver.resolve(accounts: [account])

        #expect(result == .exactSnapshot(account.id))
    }

    @Test
    func resolveFallsBackToRemoteIdentityWhenFingerprintDoesNotMatch() {
        let account = makeAccount(name: "Work", fingerprint: "stale-fingerprint", email: "work@example.com")
        let resolver = ActiveAccountResolver(
            authService: AuthFingerprintSpy(currentFingerprint: "live-fingerprint", stableAccountID: nil)
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

private struct AuthFingerprintSpy: CodexAuthFingerprintReading {
    let currentFingerprint: String?
    let stableAccountID: String?

    func currentAuthFingerprint() -> String? {
        currentFingerprint
    }

    func currentStableAccountID() -> String? {
        stableAccountID
    }
}
