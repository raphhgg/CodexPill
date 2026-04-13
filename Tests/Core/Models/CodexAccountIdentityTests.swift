import Foundation
import Testing

@testable import CodexPill

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
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: "fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "old@example.com")
            )
        )

        account.applyRemoteMetadata(
            email: "new@example.com",
            planType: "pro",
            rateLimits: nil
        )

        #expect(account.email == "new@example.com")
        #expect(account.resolvedRemoteIdentity == CodexRemoteAccountIdentity(emailAddress: "new@example.com"))
    }
}
