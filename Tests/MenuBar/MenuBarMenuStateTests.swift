import Foundation
import Testing

@testable import RUsage

struct MenuBarMenuStateTests {
    @Test
    func statusMessageOnlyShowsWhileBusy() {
        let hidden = makeState(isBusy: false, statusMessage: "Refreshing...")
        let shown = makeState(isBusy: true, statusMessage: "Refreshing...")

        #expect(!hidden.shouldShowStatusMessage)
        #expect(shown.shouldShowStatusMessage)
    }

    @Test
    func emptyStateForcesStatusItemContentToIconOnly() {
        let state = makeState(isBusy: false)

        #expect(!state.hasStatusItemContentData)
        #expect(state.effectiveStatusBarDisplayMode == .iconOnly)
    }

    @Test
    func activeAccountUsesStoredStatusItemContentMode() {
        let state = makeState(
            activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
            isBusy: false
        )

        #expect(state.hasStatusItemContentData)
        #expect(state.effectiveStatusBarDisplayMode == .textOnHover)
    }

    @Test
    func activeAccountWithoutRateLimitsStillForcesIconOnly() {
        let state = makeState(
            activeAccount: makeAccount(name: "Active"),
            isBusy: false
        )

        #expect(!state.hasStatusItemContentData)
        #expect(state.effectiveStatusBarDisplayMode == .iconOnly)
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
        isBusy: Bool = false,
        statusMessage: String = "Ready"
    ) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            refreshIntervalMinutes: 5,
            statusBarIndicatorStyle: .moon,
            statusBarDisplayMode: .textOnHover,
            isBusy: isBusy,
            statusMessage: statusMessage
        )
    }
}
