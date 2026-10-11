import Foundation
import Testing

@testable import Refill

struct CodexAccountIdentityTests {
    @Test
    func applyRemoteMetadataRefreshesCachedRemoteIdentity() {
        var account = CodexAccount(
            id: UUID(),
            name: "Work",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
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
        #expect(account.resolvedRemoteIdentity == CodexRemoteAccountIdentity(emailAddress: "new@example.com"))
    }
}
