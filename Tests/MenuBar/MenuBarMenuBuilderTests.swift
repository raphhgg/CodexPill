import AppKit
import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarMenuBuilderTests {
    @Test
    func statusItemContentOptionsAreDisabledWhenNoStatusDataExists() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: false)),
            target: coordinator
        )

        let contentMenu = try #require(statusItemContentMenu(in: menu))
        let iconOnly = try #require(contentMenu.items.first(where: { $0.title == "Icon Only" }))
        let iconAndText = try #require(contentMenu.items.first(where: { $0.title == "Icon + Text" }))
        let textOnHover = try #require(contentMenu.items.first(where: { $0.title == "Text on Hover" }))

        #expect(iconOnly.isEnabled)
        #expect(iconOnly.action != nil)
        #expect(iconAndText.state == .off)
        #expect(!iconAndText.isEnabled)
        #expect(iconAndText.action == nil)
        #expect(textOnHover.state == .off)
        #expect(!textOnHover.isEnabled)
        #expect(textOnHover.action == nil)
    }

    @Test
    func liveValidationSnapshotCapturesStatusItemContentMetadata() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let state = makeState(activeAccount: makeAccount(name: "Active", withRateLimits: false))
        let menu = builder.makeMenu(state: state, target: coordinator)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, menu: menu)

        let statusItem = try #require(snapshot.menuItems.first(where: { $0.title == "Status Item" }))
        let content = try #require(statusItem.children.first(where: { $0.title == "Content" }))
        let iconOnly = try #require(content.children.first(where: { $0.title == "Icon Only" }))
        let iconAndText = try #require(content.children.first(where: { $0.title == "Icon + Text" }))
        let textOnHover = try #require(content.children.first(where: { $0.title == "Text on Hover" }))

        #expect(iconOnly.isEnabled)
        #expect(iconOnly.hasAction)
        #expect(iconOnly.actionSelector == "selectStatusBarDisplayMode:")
        #expect(iconOnly.state == "on")
        #expect(!iconAndText.isEnabled)
        #expect(!iconAndText.hasAction)
        #expect(iconAndText.actionSelector == nil)
        #expect(iconAndText.state == "off")
        #expect(!textOnHover.isEnabled)
        #expect(!textOnHover.hasAction)
        #expect(textOnHover.actionSelector == nil)
        #expect(textOnHover.state == "off")
    }

    @Test
    func statusItemContentOptionsStaySelectableWhenStatusDataExists() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let contentMenu = try #require(statusItemContentMenu(in: menu))
        let iconAndText = try #require(contentMenu.items.first(where: { $0.title == "Icon + Text" }))
        let textOnHover = try #require(contentMenu.items.first(where: { $0.title == "Text on Hover" }))

        #expect(iconAndText.isEnabled)
        #expect(iconAndText.action != nil)
        #expect(textOnHover.isEnabled)
        #expect(textOnHover.action != nil)
    }

    @Test
    func saveCurrentAccountRemainsEnabledForActiveSavedAccount() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let addAccountMenu = try #require(
            menu.items
                .first(where: { $0.title == "Accounts" })?
                .submenu?
                .items
                .first(where: { $0.title == "Add Account" })?
                .submenu
        )
        let saveCurrent = try #require(addAccountMenu.items.first(where: { $0.title == "Save Current Account" }))

        #expect(saveCurrent.isEnabled)
        #expect(saveCurrent.action == #selector(MenuBarCoordinator.addCurrentAccount))
    }

    @Test
    func visibleInactiveAccountsRemainNativeClickableMenuItems() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let business3 = makeAccount(name: "Business 3", withRateLimits: true)
        let business4 = makeAccount(name: "Business 4", withRateLimits: true)
        let business2 = makeAccount(name: "Business 2", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [business3, business4, business2]
            ),
            target: coordinator
        )

        let visibleRow = try #require(
            menu.items.first(where: { ($0.representedObject as? String) == business3.id.uuidString })
        )

        #expect(visibleRow.view == nil)
        #expect(!visibleRow.title.isEmpty)
        #expect(visibleRow.title.contains("Business 3"))
        #expect(visibleRow.attributedTitle?.string.contains("Business 3") == true)
        #expect(visibleRow.action == #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(visibleRow.target === coordinator)
        #expect(visibleRow.isEnabled)
        #expect(menu.autoenablesItems)
    }

    @Test
    func moreAccountsRowUsesTextOnlyDisclosureLabel() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [
                    makeAccount(name: "Business 3", withRateLimits: true),
                    makeAccount(name: "Business 4", withRateLimits: true),
                    makeAccount(name: "Business 2", withRateLimits: true)
                ]
            ),
            target: coordinator
        )

        let moreAccounts = try #require(menu.items.first(where: { $0.title == "More Accounts…" }))
        let firstOverflowAccount = try #require(moreAccounts.submenu?.items.first)

        #expect(moreAccounts.image == nil)
        #expect(moreAccounts.submenu?.title == "More Accounts…")
        #expect(!firstOverflowAccount.title.isEmpty)
        #expect(firstOverflowAccount.title.contains("Business 2"))
        #expect(firstOverflowAccount.action == #selector(MenuBarCoordinator.switchAccount(_:)))
    }

    @Test
    func openingMenuKeepsTheSameMenuInstanceAttachedToStatusItem() throws {
        let builder = MenuBarMenuBuilder()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [makeAccount(name: "Business 3", withRateLimits: true)]
            ),
            target: coordinator
        )

        statusItem.menu = menu
        coordinator.menuWillOpen(menu)

        #expect(statusItem.menu === menu)
    }

    @Test
    func openingMenuDoesNotReplaceInactiveAccountRowsDuringOpen() throws {
        let builder = MenuBarMenuBuilder()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        let inactive = makeAccount(name: "Business 3", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [inactive]
            ),
            target: coordinator
        )

        statusItem.menu = menu
        let visibleRowBeforeOpen = try #require(
            menu.items.first(where: { ($0.representedObject as? String) == inactive.id.uuidString })
        )

        coordinator.menuWillOpen(menu)

        let visibleRowAfterOpen = try #require(
            menu.items.first(where: { ($0.representedObject as? String) == inactive.id.uuidString })
        )

        #expect(visibleRowAfterOpen === visibleRowBeforeOpen)
        #expect(visibleRowAfterOpen.action == #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(visibleRowAfterOpen.target === coordinator)
    }

    @Test
    func menuNeedsUpdateRepopulatesExistingMenuInstance() throws {
        let builder = MenuBarMenuBuilder()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [makeAccount(name: "Business 3", withRateLimits: true)]
            ),
            target: coordinator
        )

        statusItem.menu = menu

        coordinator.menuNeedsUpdate(menu)

        #expect(statusItem.menu === menu)
        #expect(menu.delegate === coordinator)
        #expect(!menu.items.isEmpty)
        #expect(menu.items.contains(where: { $0.title == "Accounts" }))
    }

    private func statusItemContentMenu(in menu: NSMenu) -> NSMenu? {
        menu.items
            .first(where: { $0.title == "Status Item" })?
            .submenu?
            .items
            .first(where: { $0.title == "Content" })?
            .submenu
    }

    private func makeCoordinator() throws -> MenuBarCoordinator {
        try makeCoordinatorWithStatusItem().0
    }

    private func makeCoordinatorWithStatusItem() throws -> (MenuBarCoordinator, NSStatusItem) {
        let repository = try AccountRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        let suiteName = "MenuBarMenuBuilderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let coordinator = MenuBarCoordinator(
            statusItem: statusItem,
            store: store,
            settings: settings,
            alertPresenter: MenuBarAlertPresenter()
        )
        return (coordinator, statusItem)
    }

    private func makeState(activeAccount: CodexAccount?, inactiveAccounts: [CodexAccount] = []) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: inactiveAccounts,
            visibleInactiveAccountCount: 2,
            visibleInactiveAccountCountOptions: [2, 3, 5, 0],
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .dualArcBadge,
            statusBarDisplayMode: .textOnHover,
            isBusy: false,
            statusMessage: "Ready"
        )
    }

    private func makeAccount(name: String, withRateLimits: Bool) -> CodexAccount {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        return CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: now,
            updatedAt: now,
            email: "\(name.lowercased())@example.com",
            planType: "pro",
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
