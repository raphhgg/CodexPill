import Foundation
import Testing

@testable import CodexPill

struct MenuBarAccountCatalogProjectionTests {
    @Test
    func relinksStaleVerifiedRemoteAccountToSavedAccount() {
        let now = Date(timeIntervalSince1970: 1_745_241_200)
        let saved = makeAccount(
            name: "Business 2",
            email: "user@example.com",
            stableAccountID: "acct-team",
            rateLimits: makeRateLimits(sessionUsedPercent: 100, sessionResetsAt: now.addingTimeInterval(25 * 60))
        )
        let staleRemote = makeAccount(
            name: "Business 2",
            email: "user@example.com",
            stableAccountID: "stale-team",
            rateLimits: makeRateLimits(
                sessionUsedPercent: 100,
                sessionResetsAt: now.addingTimeInterval(-45 * 60),
                fetchedAt: now.addingTimeInterval(-3600)
            ),
            updatedAt: now.addingTimeInterval(-3600)
        )

        let projection = MenuBarAccountCatalogProjection(
            activeAccount: nil,
            inactiveAccounts: [saved],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "debian-vm",
                    destination: "debian-vm",
                    connectionState: .connected,
                    desiredAccount: staleRemote,
                    activeAccount: staleRemote,
                    verificationStatus: .verified
                )
            ]
        )

        let resolved = try! #require(projection.connectedRemoteHosts.first?.activeAccount)
        #expect(resolved.id == saved.id)
        #expect(resolved.rateLimits?.primary?.resetsAt == saved.rateLimits?.primary?.resetsAt)
    }

    @Test
    func catalogEntryPrefersRemoteDisplayValuesForRemoteOnlyActiveAccount() {
        let now = Date()
        let local = makeAccount(name: "Business 4", rateLimits: makeRateLimits(sessionUsedPercent: 42))
        var remote = local
        remote.applyRemoteMetadata(
            email: local.email,
            planType: local.planType,
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval(3 * 60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: nil,
                fetchedAt: now
            )
        )

        let projection = MenuBarAccountCatalogProjection(
            activeAccount: nil,
            inactiveAccounts: [local],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "debian-vm",
                    destination: "debian-vm",
                    connectionState: .connected,
                    desiredAccount: local,
                    activeAccount: remote,
                    verificationStatus: .verified,
                    deployedAccountIDs: [local.id]
                )
            ]
        )

        let entry = try! #require(projection.accountCatalogEntries.first)
        #expect(entry.account.id == local.id)
        #expect(entry.displayAccount.rateLimits?.primary?.displayedUsedPercent(at: now) == 100)
        #expect(entry.placement == .remote)
    }

    @Test
    func availabilitySnapshotsIncludeDisconnectedRemoteTargetsWithoutMarkingCatalogActive() {
        let local = makeAccount(name: "Business 2", rateLimits: makeRateLimits(sessionUsedPercent: 25))
        let projection = MenuBarAccountCatalogProjection(
            activeAccount: nil,
            inactiveAccounts: [local],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "buildbox",
                    destination: "user@buildbox",
                    connectionState: .disconnected,
                    desiredAccount: local,
                    activeAccount: nil,
                    verificationStatus: .failed,
                    deployedAccountIDs: [local.id]
                )
            ]
        )

        #expect(projection.connectedRemoteHosts.isEmpty)
        #expect(projection.remoteTargetAvailabilities["user@buildbox"]?.status == .unavailable(reason: .disconnected))
        #expect(projection.accountCatalogEntries.first?.placement == nil)
        #expect(projection.availabilitySnapshots.first?.remoteAvailabilities.first?.status == .unavailable(reason: .disconnected))
    }
}
