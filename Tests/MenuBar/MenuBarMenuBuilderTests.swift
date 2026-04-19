import AppKit
import Foundation
import SwiftUI
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

        let display = try #require(snapshot.menuItems.first(where: { $0.title == "Display" }))
        let content = try #require(display.children.first(where: { $0.title == "Content" }))
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
    func visibleAccountsUseNativeSubmenusForSwitching() throws {
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
            menu.items.first(where: { $0.submenu?.title == business3.name })
        )
        let submenu = try #require(visibleRow.submenu)
        let statusItem = try #require(submenu.items.first)
        let localAction = try #require(submenu.items.first(where: { $0.title == "Switch on This Mac" }))

        #expect(visibleRow.view == nil)
        #expect(visibleRow.attributedTitle?.string.contains("S ") == true)
        #expect(visibleRow.attributedTitle?.string.contains("W ") == true)
        #expect(visibleRow.attributedTitle?.string.contains("Local") == false)
        #expect(visibleRow.representedObject as? String == business3.id.uuidString)
        #expect(visibleRow.action != #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(visibleRow.isEnabled == true)
        #expect(statusItem.title == "Not currently in use")
        #expect(statusItem.isEnabled == false)
        #expect(localAction.action == #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(localAction.target === coordinator)
        #expect(localAction.representedObject as? String == business3.id.uuidString)
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
                    makeAccount(name: "Business 2", withRateLimits: true),
                    makeAccount(name: "Business 1", withRateLimits: true)
                ]
            ),
            target: coordinator
        )

        let moreAccounts = try #require(menu.items.first(where: { $0.title == "More Accounts…" }))
        let firstOverflowAccount = try #require(moreAccounts.submenu?.items.first)
        let overflowSwitch = try #require(firstOverflowAccount.submenu?.items.first(where: { $0.title == "Switch on This Mac" }))

        #expect(moreAccounts.image == nil)
        #expect(moreAccounts.submenu?.title == "More Accounts…")
        #expect(!firstOverflowAccount.title.isEmpty)
        #expect(firstOverflowAccount.title.contains("Business 4"))
        #expect(firstOverflowAccount.submenu != nil)
        #expect(firstOverflowAccount.action != #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(overflowSwitch.action == #selector(MenuBarCoordinator.switchAccount(_:)))
    }

    @Test
    func inactiveAccountUsesTargetSubmenuWhenRemoteHostIsPresent() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let inactive = makeAccount(name: "Business 3", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [inactive],
                remoteHosts: [makeRemoteHost(
                    activeAccount: makeAccount(name: "Remote", withRateLimits: true),
                    deployedAccountIDs: [inactive.id]
                )]
            ),
            target: coordinator
        )

        let accountItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(inactive.name) == true }))
        let submenu = try #require(accountItem.submenu)
        let statusItem = try #require(submenu.items.first(where: { $0.title == "Not currently in use" }))
        let localAction = try #require(submenu.items.first(where: { $0.title == "Switch on This Mac" }))
        let remoteAction = try #require(submenu.items.first(where: { $0.title == "Switch on devbox" }))

        #expect(accountItem.submenu === submenu)
        #expect(accountItem.attributedTitle?.string.contains("S ") == true)
        #expect(accountItem.attributedTitle?.string.contains("W ") == true)
        #expect(accountItem.attributedTitle?.string.contains("Remote") == false)
        #expect(statusItem.isEnabled == false)
        #expect(localAction.action == #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(localAction.representedObject as? String == inactive.id.uuidString)
        #expect(localAction.target === coordinator)
        #expect(remoteAction.action == #selector(MenuBarCoordinator.switchAccountOnHost(_:)))
        #expect(remoteAction.target === coordinator)
        let remotePayload = try #require(remoteAction.representedObject as? HostAccountMenuItemPayload)
        #expect(remotePayload.accountID == inactive.id)
        #expect(remotePayload.hostDestination == "user@devbox")
    }

    @Test
    func hostsSubmenuOffersAddHostWhenNoHostIsConfigured() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let hostsMenu = try #require(menu.items.first(where: { $0.title == "Hosts" })?.submenu)
        let addHost = try #require(hostsMenu.items.first(where: { $0.title == "Add Host…" }))

        #expect(addHost.action == #selector(MenuBarCoordinator.addHost(_:)))
        #expect(hostsMenu.items.contains(where: { $0.title == "Remove Host" }) == false)
    }

    @Test
    func hostsSubmenuShowsConfiguredHostAndRemoveAction() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [makeRemoteHost(activeAccount: nil)]
            ),
            target: coordinator
        )

        let hostsMenu = try #require(menu.items.first(where: { $0.title == "Hosts" })?.submenu)
        let hostItem = try #require(hostsMenu.items.first(where: { $0.title == "devbox" }))
        let hostSubmenu = try #require(hostItem.submenu)
        let hostStatus = try #require(hostSubmenu.items.first(where: { $0.title == "devbox (user@devbox)" }))
        let removeHost = try #require(hostSubmenu.items.first(where: { $0.title == "Remove Host" }))

        #expect(hostStatus.isEnabled == false)
        #expect(removeHost.action == #selector(MenuBarCoordinator.removeHost(_:)))
        let removePayload = try #require(removeHost.representedObject as? HostSelectionMenuItemPayload)
        #expect(removePayload.hostDestination == "user@devbox")
    }

    @Test
    func inactiveAccountSubmenuIncludesAllConfiguredHosts() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let inactive = makeAccount(name: "Business 3", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [inactive],
                remoteHosts: [
                    makeRemoteHost(activeAccount: nil),
                    RemoteHostMenuState(
                        name: "buildbox",
                        destination: "user@buildbox",
                        connectionState: .connected,
                        activeAccount: nil,
                        deployedAccountIDs: []
                    )
                ]
            ),
            target: coordinator
        )

        let accountItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(inactive.name) == true }))
        let submenu = try #require(accountItem.submenu)

        #expect(submenu.items.contains(where: { $0.title == "Install on devbox and switch" }))
        #expect(submenu.items.contains(where: { $0.title == "Install on buildbox and switch" }))
    }

    @Test
    func remoteAccountSectionUsesHostedCardInsteadOfPlainTextRow() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [makeRemoteHost(activeAccount: makeAccount(name: "Business 2", withRateLimits: true))]
            ),
            target: coordinator
        )

        #expect(menu.items.contains(where: { $0.title.contains("devbox • Connected") }) == false)
        #expect(menu.items.filter { $0.view != nil }.count >= 4)
    }

    @Test
    func activeAccountHostedViewFitsWithinConfiguredMenuWidth() {
        let view = NSHostingView(
            rootView: ActiveAccountMenuContent(
                account: makeAccount(name: "Business 2", withRateLimits: true),
                progressAccentColor: .blue
            )
        )

        view.frame = NSRect(x: 0, y: 0, width: 372, height: 1)
        view.layoutSubtreeIfNeeded()

        #expect(view.fittingSize.width <= 372)
    }

    @Test
    func remoteAccountHostedViewFitsWithinConfiguredMenuWidth() {
        let view = NSHostingView(
            rootView: RemoteHostMenuContent(
                remoteHost: makeRemoteHost(activeAccount: makeAccount(name: "Personal 1", withRateLimits: true)),
                progressAccentColor: .blue
            )
        )

        view.frame = NSRect(x: 0, y: 0, width: 372, height: 1)
        view.layoutSubtreeIfNeeded()

        #expect(view.fittingSize.width <= 372)
    }

    @Test
    func sectionHeaderAndActiveCardUseSameComputedWidth() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Personal", withRateLimits: true),
                inactiveAccounts: [
                    makeAccount(name: "Business 1", withRateLimits: true),
                    makeAccount(name: "Business 2", withRateLimits: true)
                ]
            ),
            target: coordinator
        )

        let headerWidth = try #require(menu.items.first?.view?.frame.width)
        let cardWidth = try #require(menu.items.dropFirst().first?.view?.frame.width)

        #expect(headerWidth == cardWidth)
        #expect(headerWidth >= 372)
    }

    @Test
    func wideAccountRowsExpandHostedSectionsToMatchMenuBudget() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let wideAccountName = "Extremely Long Business Account Name For Width Regression Coverage"
        let wideAccount = CodexAccount(
            id: UUID(),
            name: wideAccountName,
            snapshotFileName: "wide-account.json",
            createdAt: now,
            updatedAt: now,
            email: "wide@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval((4 * 60 + 59) * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 78,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            )
        )
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Personal", withRateLimits: true),
                inactiveAccounts: [wideAccount]
            ),
            target: coordinator
        )

        let headerWidth = try #require(menu.items.first?.view?.frame.width)
        let widestLocalRow = try #require(
            menu.items.first(where: { $0.submenu?.title == wideAccountName })
        )
        let rowWidth = inactiveAccountTitleWidth(
            for: wideAccount,
            displayName: compactMenuRowDisplayName(for: wideAccountName),
            placement: nil,
            menuContentWidth: headerWidth,
            now: now
        )

        #expect(headerWidth == 372)
        #expect(widestLocalRow.view == nil)
        #expect(widestLocalRow.attributedTitle?.string.contains("…") == true)
        #expect(rowWidth > 0)
    }

    @Test
    func disconnectedRemoteHostDoesNotRenderPrimaryRemoteSection() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [RemoteHostMenuState(
                    name: "devbox",
                    destination: "user@devbox",
                    connectionState: .disconnected,
                    activeAccount: makeAccount(name: "Business 2", withRateLimits: true)
                )]
            ),
            target: coordinator
        )

        #expect(menu.items.contains(where: { $0.title == "Remote Accounts" }) == false)
    }

    @Test
    func inactiveAccountUsesInstallAndSwitchCopyWhenMissingOnRemoteHost() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let inactive = makeAccount(name: "Business 3", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [inactive],
                remoteHosts: [makeRemoteHost(activeAccount: nil, deployedAccountIDs: [])]
            ),
            target: coordinator
        )

        let accountItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(inactive.name) == true }))
        let submenu = try #require(accountItem.submenu)
        let remoteAction = try #require(submenu.items.first(where: { $0.title == "Install on devbox and switch" }))

        #expect(accountItem.attributedTitle?.string.contains("S ") == true)
        #expect(remoteAction.action == #selector(MenuBarCoordinator.switchAccountOnHost(_:)))
        let remotePayload = try #require(remoteAction.representedObject as? HostAccountMenuItemPayload)
        #expect(remotePayload.accountID == inactive.id)
        #expect(remotePayload.hostDestination == "user@devbox")
    }

    @Test
    func remoteAccountsSectionRendersOneHostedCardPerConnectedHost() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [
                    makeRemoteHost(
                        activeAccount: makeAccount(name: "Business 2", withRateLimits: true)
                    ),
                    RemoteHostMenuState(
                        name: "buildbox",
                        destination: "user@buildbox",
                        connectionState: .connected,
                        activeAccount: makeAccount(name: "Business 3", withRateLimits: true),
                        deployedAccountIDs: []
                    )
                ]
            ),
            target: coordinator
        )

        let remoteCards = menu.items.compactMap(\.view).filter {
            String(describing: type(of: $0)).contains("RemoteHostMenuContent")
        }

        #expect(remoteCards.count == 2)
        #expect(menu.items.filter { $0.view != nil }.count == 6)
    }

    @Test
    func statusItemMenuIncludesColorCustomizationAndReset() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let displayMenu = try #require(menu.items.first(where: { $0.title == "Display" })?.submenu)
        let accent = try #require(displayMenu.items.first(where: { $0.title == "Accent Color…" }))
        let reset = try #require(displayMenu.items.first(where: { $0.title == "Use Default" }))

        #expect(accent.action == #selector(MenuBarCoordinator.chooseProgressAccentColor(_:)))
        #expect(accent.image != nil)
        #expect(reset.action == #selector(MenuBarCoordinator.resetProgressAccentColor(_:)))
        #expect(!reset.isEnabled)
    }

    @Test
    func statusItemMenuEnablesUseDefaultWhenCustomAccentColorExists() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                progressAccentColor: NSColor(deviceRed: 0.12, green: 0.45, blue: 0.78, alpha: 1),
                hasCustomProgressAccentColor: true
            ),
            target: coordinator
        )

        let displayMenu = try #require(menu.items.first(where: { $0.title == "Display" })?.submenu)
        let reset = try #require(displayMenu.items.first(where: { $0.title == "Use Default" }))

        #expect(reset.action == #selector(MenuBarCoordinator.resetProgressAccentColor(_:)))
        #expect(reset.isEnabled)
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
        let localAction = try #require(
            visibleRowAfterOpen.submenu?.items.first(where: { $0.title == "Switch on This Mac" })
        )

        #expect(visibleRowAfterOpen === visibleRowBeforeOpen)
        #expect(visibleRowAfterOpen.submenu === visibleRowBeforeOpen.submenu)
        #expect(visibleRowAfterOpen.action != #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(localAction.action == #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(localAction.target === coordinator)
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
            .first(where: { $0.title == "Display" })?
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
        let statusItemRuntime = StatusItemRuntime(statusItem: statusItem)
        let coordinator = MenuBarCoordinator(
            statusItemRuntime: statusItemRuntime,
            store: store,
            settings: settings,
            alertPresenter: MenuBarAlertPresenter()
        )
        return (coordinator, statusItem)
    }

    private func makeState(
        activeAccount: CodexAccount?,
        inactiveAccounts: [CodexAccount] = [],
        remoteHosts: [RemoteHostMenuState] = [],
        progressAccentColor: NSColor = .controlAccentColor,
        hasCustomProgressAccentColor: Bool = false
    ) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: inactiveAccounts,
            remoteHosts: remoteHosts,
            visibleInactiveAccountCount: 2,
            visibleInactiveAccountCountOptions: [2, 3, 5, 0],
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .dualArcBadge,
            statusBarDisplayMode: .textOnHover,
            progressAccentColor: progressAccentColor,
            hasCustomProgressAccentColor: hasCustomProgressAccentColor,
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

    private func makeRemoteHost(activeAccount: CodexAccount? = nil, deployedAccountIDs: [UUID] = []) -> RemoteHostMenuState {
        RemoteHostMenuState(
            name: "devbox",
            destination: "user@devbox",
            connectionState: .connected,
            activeAccount: activeAccount,
            deployedAccountIDs: deployedAccountIDs
        )
    }
}
