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
    func visibleAndOverflowInactiveAccountsSplitBySetting() {
        let accounts = [
            makeAccount(name: "A"),
            makeAccount(name: "B"),
            makeAccount(name: "C")
        ]
        let state = makeState(inactiveAccounts: accounts, visibleInactiveAccountCount: 2)

        #expect(state.visibleInactiveAccounts.map(\.name) == ["A", "B"])
        #expect(state.overflowInactiveAccounts.map(\.name) == ["C"])
    }

    @Test
    func busyStateDisablesInteractiveActions() {
        let state = makeState(inactiveAccounts: [], isBusy: true)

        #expect(!state.canSaveCurrentAccount)
        #expect(!state.canSignInAnotherAccount)
        #expect(!state.canShowAbout)
    }

    @Test
    func activeSavedAccountStillAllowsSaveCurrentAccount() {
        let state = makeState(
            activeAccount: makeAccount(name: "Active"),
            inactiveAccounts: [],
            isBusy: false
        )

        #expect(state.canSaveCurrentAccount)
        #expect(state.canSignInAnotherAccount)
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
    func emptyStateAllowsSavingCurrentAccount() {
        let state = makeState(inactiveAccounts: [], isBusy: false)

        #expect(state.canSaveCurrentAccount)
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
        visibleInactiveAccountCount: Int = 2,
        isBusy: Bool = false,
        statusMessage: String = "Ready"
    ) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: inactiveAccounts,
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
}
