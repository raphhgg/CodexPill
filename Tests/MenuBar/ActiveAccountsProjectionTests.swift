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

    @Test
    func localPlusSameRemoteAccountRendersOneLocationCard() {
        let local = makeAccount(name: "Personal")
        var remote = local
        remote.updatedAt = local.updatedAt.addingTimeInterval(60)
        let projection = makeProjection(
            activeAccount: local,
            remoteHosts: [makeHost(name: "debian-vm", account: remote)]
        )

        #expect(projection.sectionTitle == "Active Account")
        #expect(projection.activeAccountCards == [
            ActiveAccountCard(account: local, locations: ["This Mac", "debian-vm"], showsUpdatedTime: false)
        ])
    }

    @Test
    func localPlusDifferentRemoteAccountRendersSeparateCards() {
        let local = makeAccount(name: "Personal")
        let remote = makeAccount(name: "Work")
        let projection = makeProjection(
            activeAccount: local,
            remoteHosts: [makeHost(name: "buildbox", account: remote)]
        )

        #expect(projection.sectionTitle == "Active Accounts")
        #expect(projection.activeAccountCards == [
            ActiveAccountCard(account: local, locations: ["This Mac"], showsUpdatedTime: false),
            ActiveAccountCard(account: remote, locations: ["buildbox"], showsUpdatedTime: false)
        ])
    }

    @Test
    func remoteOnlyActiveAccountRendersRemoteCard() {
        let remote = makeAccount(name: "Work")
        let projection = makeProjection(
            remoteHosts: [makeHost(name: "buildbox", account: remote)]
        )

        #expect(projection.sectionTitle == "Active Account")
        #expect(projection.activeAccountCards == [
            ActiveAccountCard(account: remote, locations: ["buildbox"], showsUpdatedTime: false)
        ])
    }

    @Test
    func multipleRemoteHostsUsingSameAccountRenderOneCard() {
        let remote = makeAccount(name: "Work")
        let projection = makeProjection(
            remoteHosts: [
                makeHost(name: "buildbox", account: remote),
                makeHost(name: "debian-vm", account: remote)
            ]
        )

        #expect(projection.sectionTitle == "Active Account")
        #expect(projection.activeAccountCards == [
            ActiveAccountCard(account: remote, locations: ["buildbox", "debian-vm"], showsUpdatedTime: false)
        ])
    }

    @Test
    func updatedTimeOnlyShowsForSingleLocalOnlyCard() {
        let local = makeAccount(name: "Personal")
        let remote = makeAccount(name: "Work")

        let localOnly = makeProjection(activeAccount: local)
        let localAndRemoteSame = makeProjection(
            activeAccount: local,
            remoteHosts: [makeHost(name: "debian-vm", account: local)]
        )
        let localAndRemoteDifferent = makeProjection(
            activeAccount: local,
            remoteHosts: [makeHost(name: "buildbox", account: remote)]
        )
        let remoteOnly = makeProjection(
            remoteHosts: [makeHost(name: "buildbox", account: remote)]
        )

        #expect(localOnly.activeAccountCards.map(\.showsUpdatedTime) == [true])
        #expect(localAndRemoteSame.activeAccountCards.map(\.showsUpdatedTime) == [false])
        #expect(localAndRemoteDifferent.activeAccountCards.map(\.showsUpdatedTime) == [false, false])
        #expect(remoteOnly.activeAccountCards.map(\.showsUpdatedTime) == [false])
    }

    private func makeProjection(
        activeAccount: CodexAccount? = nil,
        remoteHosts: [RemoteHostMenuState] = []
    ) -> ActiveAccountsProjection {
        ActiveAccountsProjection(
            activeAccount: activeAccount,
            connectedRemoteHosts: remoteHosts
        )
    }

    private func makeHost(name: String, account: CodexAccount) -> RemoteHostMenuState {
        RemoteHostMenuState(
            name: name,
            destination: name,
            connectionState: .connected,
            desiredAccount: account,
            activeAccount: account,
            verificationStatus: .verified,
            deployedAccountIDs: [account.id]
        )
    }
}
