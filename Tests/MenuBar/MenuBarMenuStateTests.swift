import Foundation
import Testing

@testable import CodexPill

struct MenuBarMenuStateTests {
    @Test
    func allSavedAccountsFollowRankedAccountsOrder() {
        let accounts = [
            makeAccount(name: "A"),
            makeAccount(name: "B"),
            makeAccount(name: "C")
        ]

        let state = makeState(inactiveAccounts: accounts)

        #expect(state.allSavedAccounts.map(\.name) == ["A", "B", "C"])
    }

    @Test
    func visibleAndOverflowAccountsUseConfiguredNonActiveLimit() {
        let accounts = [
            makeAccount(name: "A"),
            makeAccount(name: "B"),
            makeAccount(name: "C"),
            makeAccount(name: "D")
        ]
        let state = makeState(inactiveAccounts: accounts, visibleInactiveAccountCount: 2)

        #expect(state.visibleAccountEntries.map(\.account.name) == ["A", "B"])
        #expect(state.overflowAccountEntries.map(\.account.name) == ["C", "D"])
    }

    @Test
    func zeroVisibleInactiveAccountCountShowsAllAccountsWithoutOverflow() {
        let accounts = [
            makeAccount(name: "A"),
            makeAccount(name: "B"),
            makeAccount(name: "C")
        ]
        let state = makeState(inactiveAccounts: accounts, visibleInactiveAccountCount: 0)

        #expect(state.visibleAccountEntries.map(\.account.name) == ["A", "B", "C"])
        #expect(state.overflowAccountEntries.isEmpty)
    }

    @Test
    func visibleAccountEntriesUseSharedInactiveAvailabilityRanking() {
        let now = Date()
        let constrained = CodexAccount(
            id: UUID(),
            name: "Constrained",
            snapshotFileName: "constrained.json",
            createdAt: now,
            updatedAt: now,
            email: "constrained@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(usedPercent: 90, resetsAt: now.addingTimeInterval(7200), windowDurationMinutes: 300),
                secondary: CodexRateLimitWindow(usedPercent: 100, resetsAt: now.addingTimeInterval(172800), windowDurationMinutes: 10_080),
                fetchedAt: now
            ),
            identity: .empty
        )
        let preferred = CodexAccount(
            id: UUID(),
            name: "Preferred",
            snapshotFileName: "preferred.json",
            createdAt: now,
            updatedAt: now,
            email: "preferred@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(usedPercent: 0, resetsAt: now.addingTimeInterval(3600), windowDurationMinutes: 300),
                secondary: CodexRateLimitWindow(usedPercent: 10, resetsAt: now.addingTimeInterval(86400), windowDurationMinutes: 10_080),
                fetchedAt: now
            ),
            identity: .empty
        )

        let state = makeState(inactiveAccounts: [constrained, preferred])

        #expect(state.visibleAccountEntries.map { $0.account.name } == ["Preferred", "Constrained"])
    }

    @Test
    func busyStateDisablesInteractiveActions() {
        let state = makeState(inactiveAccounts: [], isBusy: true)

        #expect(!state.canAddAccount)
        #expect(!state.canShowAbout)
    }

    @Test
    func activeSavedAccountStillAllowsAddAccount() {
        let state = makeState(
            activeAccount: makeAccount(name: "Active"),
            inactiveAccounts: [],
            isBusy: false
        )

        #expect(state.canAddAccount)
    }

    @Test
    func activeAccountAppearsInManageAccountOrdering() {
        let state = makeState(
            activeAccount: makeAccount(name: "Active"),
            inactiveAccounts: [],
        )

        #expect(state.allSavedAccounts.map(\.name) == ["Active"])
    }

    @Test
    func statusMessageOnlyShowsWhileBusy() {
        let hidden = makeState(inactiveAccounts: [], isBusy: false, statusMessage: "Refreshing...")
        let shown = makeState(inactiveAccounts: [], isBusy: true, statusMessage: "Refreshing...")

        #expect(!hidden.shouldShowStatusMessage)
        #expect(shown.shouldShowStatusMessage)
    }

    @Test
    func remoteHostDoesNotChangeTheLocalSavedAccountCatalog() {
        let active = makeAccount(name: "Active")
        let inactive = makeAccount(name: "Other")
        let hostOnly = makeAccount(name: "Host Only")
        let state = makeState(
            activeAccount: active,
            inactiveAccounts: [inactive],
            remoteHosts: [makeRemoteHost(activeAccount: hostOnly)]
        )

        #expect(state.allSavedAccounts.map(\.name) == ["Active", "Other"])
        #expect(state.remoteHosts.first?.activeAccount?.name == "Host Only")
    }

    @Test
    func remoteHostCardVisibilityTracksReachability() {
        let connected = makeRemoteHost(activeAccount: makeAccount(name: "Host Only"))
        let disconnected = RemoteHostMenuState(
            name: connected.name,
            connectionState: .disconnected,
            activeAccount: connected.activeAccount
        )
        let empty = makeRemoteHost(activeAccount: nil)

        #expect(connected.shouldShowRemoteAccountCard)
        #expect(!disconnected.shouldShowRemoteAccountCard)
        #expect(!empty.shouldShowRemoteAccountCard)
    }

    @Test
    func unverifiedRemoteHostDoesNotMarkAccountAsRemoteActive() {
        let local = makeAccount(name: "Business 2", withRateLimits: true)
        let state = makeState(
            activeAccount: nil,
            inactiveAccounts: [local],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "buildbox",
                    destination: "user@buildbox",
                    connectionState: .syncing,
                    desiredAccount: local,
                    activeAccount: nil,
                    verificationStatus: .verifying,
                    deployedAccountIDs: [local.id]
                )
            ]
        )

        #expect(state.connectedRemoteHosts.count == 1)
        #expect(state.connectedRemoteHosts.first?.desiredAccount?.id == local.id)
        #expect(state.connectedRemoteHosts.first?.activeAccount == nil)
        #expect(state.remoteTargetAvailabilities["user@buildbox"]?.status == .unavailable(reason: .syncing))
        #expect(state.accountCatalogEntries.first?.account.id == local.id)
        #expect(state.accountCatalogEntries.first?.placement == nil)
    }

    @Test
    func disconnectedFailedRemoteHostDoesNotShowPrimaryCardOrMarkAccountActive() {
        let local = makeAccount(name: "Business 2", withRateLimits: true)
        let detected = makeAccount(name: "Business 1", withRateLimits: true)
        let state = makeState(
            activeAccount: nil,
            inactiveAccounts: [local],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "buildbox",
                    destination: "user@buildbox",
                    connectionState: .disconnected,
                    desiredAccount: local,
                    activeAccount: nil,
                    detectedAccount: detected,
                    verificationStatus: .failed,
                    lastVerificationError: "buildbox is using Business 1, not Business 2.",
                    deployedAccountIDs: [local.id]
                )
            ]
        )

        #expect(state.connectedRemoteHosts.isEmpty)
        #expect(state.remoteTargetAvailabilities["user@buildbox"]?.status == .unavailable(reason: .disconnected))
        #expect(state.accountCatalogEntries.first?.account.id == local.id)
        #expect(state.accountCatalogEntries.first?.placement == nil)
    }

    @Test
    func detectedRemoteAccountDoesNotReplaceSavedAccountCatalog() {
        let desired = makeAccount(name: "Business 2", withRateLimits: true)
        let detected = makeAccount(name: "Business 1", withRateLimits: true)
        let state = makeState(
            activeAccount: nil,
            inactiveAccounts: [desired],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "buildbox",
                    destination: "user@buildbox",
                    connectionState: .connected,
                    desiredAccount: desired,
                    activeAccount: nil,
                    detectedAccount: detected,
                    verificationStatus: .failed,
                    lastVerificationError: "buildbox is using Business 1, not Business 2.",
                    deployedAccountIDs: [desired.id]
                )
            ]
        )

        #expect(state.connectedRemoteHosts.count == 1)
        #expect(state.connectedRemoteHosts.first?.displayAccount?.id == detected.id)
        #expect(state.remoteTargetAvailabilities["user@buildbox"]?.status == .unavailable(reason: .verificationFailed))
        #expect(state.allSavedAccounts.map(\.id) == [desired.id])
    }

    @Test
    func remoteHostCardRelinksStaleVerifiedAccountToUniqueSavedDisplayMatch() {
        let now = Date(timeIntervalSince1970: 1_745_241_200)
        let currentSavedAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: now,
            updatedAt: now,
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval(25 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 16,
                    resetsAt: now.addingTimeInterval(5 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ),
            identity: CodexAccountIdentity(
                stableAccountID: "acct-team",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|business-2",
                    chatGPTUserID: "user-business-2"
                ),
                workspaceIdentity: CodexWorkspaceIdentity(
                    workspaceAccountID: "org-business-2",
                    workspaceLabel: "Personal"
                ),
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@gmail.com")
            )
        )
        let staleRemoteAccount = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "stale-business-2.json",
            createdAt: now.addingTimeInterval(-3600),
            updatedAt: now.addingTimeInterval(-3600),
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval(-45 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 16,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now.addingTimeInterval(-3600)
            ),
            identity: CodexAccountIdentity(
                stableAccountID: "d8422eb7-1cdf-4c9f-af05-736ffb0ec845",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|63892cb90f565d7364529cd1",
                    chatGPTUserID: "user-v1Xnksr7Nc6WNNVd8Z9HkaSL"
                ),
                workspaceIdentity: CodexWorkspaceIdentity(
                    workspaceAccountID: "org-dE46tuoTzGzCaGdw0YP0CZpz",
                    workspaceLabel: "Personal"
                ),
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@gmail.com")
            )
        )

        let state = makeState(
            activeAccount: nil,
            inactiveAccounts: [currentSavedAccount],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "debian-vm",
                    destination: "debian-vm",
                    connectionState: .connected,
                    desiredAccount: staleRemoteAccount,
                    activeAccount: staleRemoteAccount,
                    verificationStatus: .verified,
                    deployedAccountIDs: []
                )
            ]
        )

        let resolvedRemoteAccount = try! #require(state.connectedRemoteHosts.first?.activeAccount)
        #expect(resolvedRemoteAccount.id == currentSavedAccount.id)
        #expect(resolvedRemoteAccount.rateLimits?.primary?.displayedUsedPercent(at: now) == 100)
        #expect(resolvedRemoteAccount.rateLimits?.primary?.resetsAt == currentSavedAccount.rateLimits?.primary?.resetsAt)
    }

    @Test
    func accountCatalogEntryPrefersLiveRemoteDisplayValuesForRemoteActiveAccount() {
        let local = makeAccount(name: "Business 4", withRateLimits: true)
        var remote = local
        let now = Date()
        remote.applyRemoteMetadata(
            email: local.email,
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval(3 * 60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 16,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            )
        )

        let state = makeState(
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

        let entry = try! #require(state.accountCatalogEntries.first)
        #expect(entry.account.id == local.id)
        #expect(entry.displayAccount.rateLimits?.primary?.displayedUsedPercent(at: now) == 100)
        #expect(entry.displayAccount.rateLimits?.secondary?.displayedUsedPercent(at: now) == 16)
        #expect(entry.placement == .remote)
    }

    @Test
    func accountCatalogEntryPrefersLocalDisplayValuesWhenAccountIsActiveLocallyAndRemotely() {
        let now = Date()
        let local = makeAccount(name: "Business 4", withRateLimits: true)
        var remote = local
        remote.applyRemoteMetadata(
            email: local.email,
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval(3 * 60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 16,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            )
        )

        let state = makeState(
            activeAccount: local,
            inactiveAccounts: [],
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

        let entry = try! #require(state.accountCatalogEntries.first)
        #expect(entry.account.id == local.id)
        #expect(entry.displayAccount.rateLimits?.primary?.displayedUsedPercent(at: now) == local.rateLimits?.primary?.displayedUsedPercent(at: now))
        #expect(entry.displayAccount.rateLimits?.secondary?.displayedUsedPercent(at: now) == local.rateLimits?.secondary?.displayedUsedPercent(at: now))
        #expect(entry.placement == .localAndRemote)
    }

    @Test
    func sameVerifiedLocalAndRemoteAccountCollapsesRemotePrimaryCard() {
        let local = makeAccount(name: "Business 4", withRateLimits: true)
        var remote = local
        remote.updatedAt = local.updatedAt.addingTimeInterval(60)
        let state = makeState(
            activeAccount: local,
            inactiveAccounts: [],
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

        #expect(state.connectedRemoteHosts.count == 1)
        #expect(state.primaryRemoteAccountHosts.isEmpty)
        #expect(state.activeAccountRemoteLocations == ["debian-vm"])
        #expect(state.accountCatalogEntries.first?.placement == .localAndRemote)
    }

    @Test
    func sameVerifiedRemoteAccountWithDifferentInspectableDataKeepsRemotePrimaryCard() {
        let now = Date()
        let local = makeAccount(name: "Business 4", withRateLimits: true)
        var remote = local
        remote.applyRemoteMetadata(
            email: "remote-business@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 82,
                    resetsAt: now.addingTimeInterval(2 * 60 * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 44,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            )
        )
        let state = makeState(
            activeAccount: local,
            inactiveAccounts: [],
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

        #expect(state.primaryRemoteAccountHosts.map(\.name) == ["debian-vm"])
        #expect(state.activeAccountRemoteLocations.isEmpty)
        #expect(state.accountCatalogEntries.first?.placement == .localAndRemote)
    }

    @Test
    func differentVerifiedRemoteAccountKeepsRemotePrimaryCard() {
        let local = makeAccount(name: "Business 4", withRateLimits: true)
        let remote = makeAccount(name: "Business 5", withRateLimits: true)
        let state = makeState(
            activeAccount: local,
            inactiveAccounts: [remote],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "debian-vm",
                    destination: "debian-vm",
                    connectionState: .connected,
                    desiredAccount: remote,
                    activeAccount: remote,
                    verificationStatus: .verified,
                    deployedAccountIDs: [remote.id]
                )
            ]
        )

        #expect(state.primaryRemoteAccountHosts.map(\.name) == ["debian-vm"])
        #expect(state.activeAccountRemoteLocations.isEmpty)
    }

    @Test
    func failedSameRemoteAccountKeepsRemotePrimaryCardVisibleForRecovery() {
        let local = makeAccount(name: "Business 4", withRateLimits: true)
        let state = makeState(
            activeAccount: local,
            inactiveAccounts: [],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "debian-vm",
                    destination: "debian-vm",
                    connectionState: .connected,
                    desiredAccount: local,
                    activeAccount: local,
                    verificationStatus: .failed,
                    lastVerificationError: "Verification failed.",
                    deployedAccountIDs: [local.id]
                )
            ]
        )

        #expect(state.primaryRemoteAccountHosts.map(\.name) == ["debian-vm"])
        #expect(state.activeAccountRemoteLocations.isEmpty)
    }

    @Test
    func removeAccountsIsAvailableWhenSavedAccountsExist() {
        let state = makeState(
            activeAccount: makeAccount(name: "Active"),
            inactiveAccounts: [makeAccount(name: "Other")],
        )

        #expect(state.canRemoveSavedAccounts)
        #expect(state.canRenameSavedAccounts)
        #expect(state.allSavedAccounts.map(\.name) == ["Active", "Other"])
    }

    @Test
    func emptyStateAllowsAddAccount() {
        let state = makeState(inactiveAccounts: [], isBusy: false)

        #expect(state.canAddAccount)
        #expect(state.allSavedAccounts.isEmpty)
    }

    @Test
    func emptyStateForcesStatusItemContentToIconOnly() {
        let state = makeState(inactiveAccounts: [], isBusy: false)

        #expect(!state.hasStatusItemContentData)
        #expect(state.effectiveStatusBarDisplayMode == .iconOnly)
        #expect(state.canSelectStatusBarDisplayMode(.iconOnly))
        #expect(!state.canSelectStatusBarDisplayMode(.iconAndText))
        #expect(!state.canSelectStatusBarDisplayMode(.textOnHover))
    }

    @Test
    func activeAccountUsesStoredStatusItemContentMode() {
        let state = makeState(
            activeAccount: makeAccount(name: "Active", withRateLimits: true),
            inactiveAccounts: [],
            isBusy: false
        )

        #expect(state.hasStatusItemContentData)
        #expect(state.effectiveStatusBarDisplayMode == .textOnHover)
        #expect(state.canSelectStatusBarDisplayMode(.iconOnly))
        #expect(state.canSelectStatusBarDisplayMode(.iconAndText))
        #expect(state.canSelectStatusBarDisplayMode(.textOnHover))
    }

    @Test
    func activeAccountWithoutRateLimitsStillForcesIconOnly() {
        let state = makeState(
            activeAccount: makeAccount(name: "Active"),
            inactiveAccounts: [],
            isBusy: false
        )

        #expect(!state.hasStatusItemContentData)
        #expect(state.effectiveStatusBarDisplayMode == .iconOnly)
        #expect(state.canSelectStatusBarDisplayMode(.iconOnly))
        #expect(!state.canSelectStatusBarDisplayMode(.iconAndText))
        #expect(!state.canSelectStatusBarDisplayMode(.textOnHover))
    }

    @Test
    func iconOnlyNeverShowsStatusItemTitle() {
        let hovered = StatusItemTitleVisibilityPolicy(
            displayMode: .iconOnly,
            isStatusItemHovered: true,
            isMenuOpen: false,
            keepsStatusTitleWhileMenuOpen: false
        )
        let pinnedMenu = StatusItemTitleVisibilityPolicy(
            displayMode: .iconOnly,
            isStatusItemHovered: false,
            isMenuOpen: true,
            keepsStatusTitleWhileMenuOpen: true
        )

        #expect(!hovered.shouldShowTitle)
        #expect(!pinnedMenu.shouldShowTitle)
    }

    @Test
    func iconAndTextAlwaysShowsStatusItemTitle() {
        let idle = StatusItemTitleVisibilityPolicy(
            displayMode: .iconAndText,
            isStatusItemHovered: false,
            isMenuOpen: false,
            keepsStatusTitleWhileMenuOpen: false
        )
        let menuOpen = StatusItemTitleVisibilityPolicy(
            displayMode: .iconAndText,
            isStatusItemHovered: false,
            isMenuOpen: true,
            keepsStatusTitleWhileMenuOpen: false
        )

        #expect(idle.shouldShowTitle)
        #expect(menuOpen.shouldShowTitle)
    }

    @Test
    func textOnHoverShowsStatusItemTitleWhenHoveredOrPinned() {
        let hovered = StatusItemTitleVisibilityPolicy(
            displayMode: .textOnHover,
            isStatusItemHovered: true,
            isMenuOpen: false,
            keepsStatusTitleWhileMenuOpen: false
        )
        let pinnedMenu = StatusItemTitleVisibilityPolicy(
            displayMode: .textOnHover,
            isStatusItemHovered: false,
            isMenuOpen: true,
            keepsStatusTitleWhileMenuOpen: true
        )
        let idle = StatusItemTitleVisibilityPolicy(
            displayMode: .textOnHover,
            isStatusItemHovered: false,
            isMenuOpen: false,
            keepsStatusTitleWhileMenuOpen: false
        )

        #expect(hovered.shouldShowTitle)
        #expect(pinnedMenu.shouldShowTitle)
        #expect(!idle.shouldShowTitle)
    }

    private func makeState(
        activeAccount: CodexAccount? = nil,
        inactiveAccounts: [CodexAccount],
        remoteHosts: [RemoteHostMenuState] = [],
        visibleInactiveAccountCount: Int = 2,
        isBusy: Bool = false,
        statusMessage: String = "Ready"
    ) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: inactiveAccounts,
            remoteHosts: remoteHosts,
            visibleInactiveAccountCount: visibleInactiveAccountCount,
            visibleInactiveAccountCountOptions: [0, 2, 4],
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [1, 5, 10],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .dualArcBadge,
            statusBarDisplayMode: .textOnHover,
            isBusy: isBusy,
            statusMessage: statusMessage
        )
    }

    private func makeAccount(name: String, withRateLimits: Bool = false) -> CodexAccount {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        return CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: now,
            updatedAt: now,
            email: "\(name.lowercased())@example.com",
            planType: nil,
            rateLimits: withRateLimits ? CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "pro",
                primary: CodexRateLimitWindow(
                    usedPercent: 42,
                    resetsAt: now.addingTimeInterval(3_600),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 68,
                    resetsAt: now.addingTimeInterval(86_400),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ) : nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com")
            )
        )
    }

    private func makeRemoteHost(
        activeAccount: CodexAccount? = nil,
        detectedAccount: CodexAccount? = nil
    ) -> RemoteHostMenuState {
        RemoteHostMenuState(
            name: "devbox",
            connectionState: .connected,
            activeAccount: activeAccount,
            detectedAccount: detectedAccount
        )
    }
}
