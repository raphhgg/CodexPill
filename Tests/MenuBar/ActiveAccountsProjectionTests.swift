import Foundation
import Testing

@testable import CodexPill

struct ActiveAccountsProjectionTests {
    @Test
    func singleLocalAccountRendersOneUpdatedLocalCard() {
        let local = makeAccount(name: "Personal")
        let projection = makeProjection(activeAccount: local)

        #expect(projection.sectionTitle == "Active Account")
        #expect(projection.activeAccountCards == [
            ActiveAccountCard(account: local, locations: [], showsUpdatedTime: true)
        ])
    }

    private func makeProjection(activeAccount: CodexAccount? = nil) -> ActiveAccountsProjection {
        ActiveAccountsProjection(activeAccount: activeAccount)
    }

    private func makeAccount(name: String) -> CodexAccount {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        return CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: now,
            updatedAt: now,
            email: "\(name.lowercased())@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com")
            )
        )
    }
}
