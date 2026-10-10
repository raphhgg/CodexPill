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
}
