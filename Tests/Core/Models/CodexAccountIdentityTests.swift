import Foundation
import Testing

@testable import RUsage

struct CodexAccountIdentityTests {
    @Test
    func applyRemoteMetadataRefreshesCachedRemoteIdentity() {
        var account = CodexAccount(
            email: "old@example.com",
            planType: nil,
            usage: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: "fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "old@example.com")
            )
        )

        account.applyRemoteMetadata(
            email: "new@example.com",
            planType: "pro",
            usage: nil
        )

        #expect(account.email == "new@example.com")
        #expect(account.identity.remoteIdentity == CodexRemoteAccountIdentity(emailAddress: "new@example.com"))
    }
}
