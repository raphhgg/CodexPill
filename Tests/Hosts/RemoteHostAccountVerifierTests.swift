import Foundation
import Testing

@testable import CodexPill

struct RemoteHostAccountVerifierTests {
    private let verifier = RemoteHostAccountVerifier()

    @Test
    func verifyIncludesExpectedAccountWhenItIsMissingFromCandidateAccounts() {
        let expected = makeAccount(
            name: "Business 2",
            email: "business-2@example.com"
        )
        let status = CodexAccountStatus(
            email: "business-2@example.com",
            planType: "team",
            rateLimits: nil
        )

        let result = verifier.verify(
            status: status,
            expectedAccount: expected,
            among: []
        )

        #expect(result == .verified(status))
    }

    @Test
    func verifyReturnsNotVerifiedWhenRemoteMatchesDifferentSavedAccount() {
        let target = makeAccount(
            name: "Business 4",
            email: "business-4@example.com"
        )
        let other = makeAccount(
            name: "Business 2",
            email: "business-2@example.com"
        )
        let status = CodexAccountStatus(
            email: "business-2@example.com",
            planType: "team",
            rateLimits: nil
        )

        let result = verifier.verify(
            status: status,
            expectedAccount: target,
            among: [target, other]
        )

        #expect(result == .notVerified(.uniqueRemoteIdentity(other.id)))
        #expect(
            verifier.failureMessage(
                for: target,
                on: RemoteHost(destination: "user@buildbox", displayName: "buildbox"),
                among: [target, other],
                matchOutcome: .uniqueRemoteIdentity(other.id)
            ) == "buildbox is using Business 2, not Business 4."
        )
    }

    private func makeAccount(name: String, email: String) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: email,
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}
