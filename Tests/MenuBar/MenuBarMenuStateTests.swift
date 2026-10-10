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
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 90, resetsAt: now.addingTimeInterval(7200), durationMinutes: 300),
                secondary: (usedPercent: 100, resetsAt: now.addingTimeInterval(172800), durationMinutes: 10_080),
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
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 0, resetsAt: now.addingTimeInterval(3600), durationMinutes: 300),
                secondary: (usedPercent: 10, resetsAt: now.addingTimeInterval(86400), durationMinutes: 10_080),
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
            activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
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
            isShortcutRevealActive: false,
            isMenuOpen: false,
            keepsStatusTitleWhileMenuOpen: false
        )
        let pinnedMenu = StatusItemTitleVisibilityPolicy(
            displayMode: .iconOnly,
            isStatusItemHovered: false,
            isShortcutRevealActive: false,
            isMenuOpen: true,
            keepsStatusTitleWhileMenuOpen: true
        )
        let shortcutReveal = StatusItemTitleVisibilityPolicy(
            displayMode: .iconOnly,
            isStatusItemHovered: false,
            isShortcutRevealActive: true,
            isMenuOpen: false,
            keepsStatusTitleWhileMenuOpen: false
        )

        #expect(!hovered.shouldShowTitle)
        #expect(!pinnedMenu.shouldShowTitle)
        #expect(shortcutReveal.shouldShowTitle)
    }

    @Test
    func iconAndTextAlwaysShowsStatusItemTitle() {
        let idle = StatusItemTitleVisibilityPolicy(
            displayMode: .iconAndText,
            isStatusItemHovered: false,
            isShortcutRevealActive: false,
            isMenuOpen: false,
            keepsStatusTitleWhileMenuOpen: false
        )
        let menuOpen = StatusItemTitleVisibilityPolicy(
            displayMode: .iconAndText,
            isStatusItemHovered: false,
            isShortcutRevealActive: false,
            isMenuOpen: true,
            keepsStatusTitleWhileMenuOpen: false
        )
        let shortcutReveal = StatusItemTitleVisibilityPolicy(
            displayMode: .iconAndText,
            isStatusItemHovered: false,
            isShortcutRevealActive: true,
            isMenuOpen: false,
            keepsStatusTitleWhileMenuOpen: false
        )

        #expect(idle.shouldShowTitle)
        #expect(menuOpen.shouldShowTitle)
        #expect(shortcutReveal.shouldShowTitle)
    }

    @Test
    func textOnHoverShowsStatusItemTitleWhenHoveredOrPinned() {
        let hovered = StatusItemTitleVisibilityPolicy(
            displayMode: .textOnHover,
            isStatusItemHovered: true,
            isShortcutRevealActive: false,
            isMenuOpen: false,
            keepsStatusTitleWhileMenuOpen: false
        )
        let pinnedMenu = StatusItemTitleVisibilityPolicy(
            displayMode: .textOnHover,
            isStatusItemHovered: false,
            isShortcutRevealActive: false,
            isMenuOpen: true,
            keepsStatusTitleWhileMenuOpen: true
        )
        let idle = StatusItemTitleVisibilityPolicy(
            displayMode: .textOnHover,
            isStatusItemHovered: false,
            isShortcutRevealActive: false,
            isMenuOpen: false,
            keepsStatusTitleWhileMenuOpen: false
        )
        let shortcutReveal = StatusItemTitleVisibilityPolicy(
            displayMode: .textOnHover,
            isStatusItemHovered: false,
            isShortcutRevealActive: true,
            isMenuOpen: false,
            keepsStatusTitleWhileMenuOpen: false
        )

        #expect(hovered.shouldShowTitle)
        #expect(pinnedMenu.shouldShowTitle)
        #expect(shortcutReveal.shouldShowTitle)
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

}
