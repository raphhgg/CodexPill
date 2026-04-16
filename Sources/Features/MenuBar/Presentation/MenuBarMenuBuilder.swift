import AppKit
import SwiftUI

@MainActor
struct MenuBarMenuBuilder {
    func makeMenu(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenu {
        let menu = NSMenu()
        populate(menu: menu, state: state, target: target)
        return menu
    }

    func populate(menu: NSMenu, state: MenuBarMenuState, target: MenuBarCoordinator) {
        menu.removeAllItems()
        menu.delegate = target

        if let activeAccount = state.activeAccount {
            menu.addItem(sectionHeaderItem("Current Account", bottomPadding: 4))
            menu.addItem(activeAccountItem(for: activeAccount))
        } else {
            menu.addItem(sectionHeaderItem("Current Account", bottomPadding: 4))
            menu.addItem(disabledInfoItem("No active saved account"))
        }

        if !state.visibleInactiveAccounts.isEmpty {
            menu.addItem(.separator())
            menu.addItem(sectionHeaderItem("Other Accounts", bottomPadding: 4))
            for account in state.visibleInactiveAccounts {
                menu.addItem(inactiveAccountItem(for: account, target: target))
            }
        }

        if !state.overflowInactiveAccounts.isEmpty {
            if state.visibleInactiveAccounts.isEmpty {
                menu.addItem(.separator())
            }
            menu.addItem(moreAccountsMenuItem(accounts: state.overflowInactiveAccounts, target: target))
        }

        menu.addItem(.separator())
        menu.addItem(manageAccountsMenuItem(state: state, target: target))
        menu.addItem(refreshIntervalMenuItem(state: state, target: target))
        menu.addItem(statusBarMenuItem(state: state, target: target))
        menu.addItem(actionItem(title: "About", systemImage: "info.circle", action: #selector(MenuBarCoordinator.showAbout), state: state, target: target))

        if state.shouldShowStatusMessage {
            menu.addItem(.separator())
            menu.addItem(disabledInfoItem(state.statusMessage))
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(MenuBarCoordinator.quitApp), keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)
    }

    private func activeAccountItem(for account: CodexAccount) -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSHostingView(rootView: ActiveAccountMenuContent(account: account))
        view.frame = NSRect(x: 0, y: 0, width: 340, height: 1)
        view.layoutSubtreeIfNeeded()
        let fittingHeight = max(1, view.fittingSize.height)
        view.frame = NSRect(x: 0, y: 0, width: 340, height: fittingHeight)
        item.view = view
        return item
    }

    private func sectionHeaderItem(_ title: String, bottomPadding: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSHostingView(rootView: SectionHeaderLabel(title: title, bottomPadding: bottomPadding))
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 18 + bottomPadding)
        item.view = view
        return item
    }

    private func disabledInfoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func inactiveAccountItem(for account: CodexAccount, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: account.name, action: #selector(MenuBarCoordinator.switchAccount(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = account.id.uuidString
        item.attributedTitle = inactiveAccountTitle(for: account)
        item.isEnabled = true
        return item
    }

    private func actionItem(title: String, systemImage: String, action: Selector, state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        item.isEnabled = !state.isBusy
        return item
    }

    private func addAccountMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Add Account", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "Add Account")

        let submenu = configuredMenu(title: "Add Account")
        let saveCurrent = NSMenuItem(title: "Save Current Account", action: #selector(MenuBarCoordinator.addCurrentAccount), keyEquivalent: "")
        saveCurrent.target = target
        saveCurrent.isEnabled = state.canSaveCurrentAccount
        submenu.addItem(saveCurrent)

        let signInAnother = NSMenuItem(title: "Sign In Another Account…", action: #selector(MenuBarCoordinator.signInAnotherAccount), keyEquivalent: "")
        signInAnother.target = target
        signInAnother.isEnabled = state.canSignInAnotherAccount
        submenu.addItem(signInAnother)

        item.submenu = submenu
        return item
    }

    private func manageAccountsMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Accounts", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "person.2.circle", accessibilityDescription: "Accounts")

        let submenu = configuredMenu(title: "Accounts")
        submenu.addItem(addAccountMenuItem(state: state, target: target))
        submenu.addItem(visibleAccountsMenuItem(state: state, target: target))
        submenu.addItem(renameAccountMenuItem(state: state, target: target))
        submenu.addItem(removeAccountMenuItem(state: state, target: target))

        item.submenu = submenu
        return item
    }

    private func removeAccountMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Remove Account", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove Account")
        item.isEnabled = state.canRemoveSavedAccounts

        let submenu = configuredMenu(title: "Remove Account")
        for account in state.allSavedAccounts {
            let option = NSMenuItem(
                title: isLocallyActive(account: account, state: state) ? "\(account.name) (Current)" : account.name,
                action: #selector(MenuBarCoordinator.removeAccount(_:)),
                keyEquivalent: ""
            )
            option.target = target
            option.representedObject = account.id.uuidString
            option.isEnabled = state.canRemoveSavedAccounts
            submenu.addItem(option)
        }

        if submenu.items.isEmpty {
            let empty = NSMenuItem(title: "No saved accounts", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }

        item.submenu = submenu
        return item
    }

    private func visibleAccountsMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Visible Other Accounts", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: "Visible Other Accounts")

        let submenu = configuredMenu(title: "Visible Other Accounts")
        for count in state.visibleInactiveAccountCountOptions {
            let title = count == 0 ? "All" : "\(count)"
            let option = NSMenuItem(title: title, action: #selector(MenuBarCoordinator.selectVisibleInactiveAccountCount(_:)), keyEquivalent: "")
            option.target = target
            option.representedObject = count
            option.state = state.visibleInactiveAccountCount == count ? .on : .off
            submenu.addItem(option)
        }

        item.submenu = submenu
        return item
    }

    private func moreAccountsMenuItem(accounts: [CodexAccount], target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "More Accounts…", action: nil, keyEquivalent: "")

        let submenu = configuredMenu(title: "More Accounts…")
        for account in accounts {
            submenu.addItem(inactiveAccountItem(for: account, target: target))
        }

        item.submenu = submenu
        return item
    }

    private func renameAccountMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Rename Account", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Rename Account")
        item.isEnabled = state.canRenameSavedAccounts

        let submenu = configuredMenu(title: "Rename Account")
        for account in state.allSavedAccounts {
            let option = NSMenuItem(
                title: isLocallyActive(account: account, state: state) ? "\(account.name) (Current)" : account.name,
                action: #selector(MenuBarCoordinator.renameAccount(_:)),
                keyEquivalent: ""
            )
            option.target = target
            option.representedObject = account.id.uuidString
            option.isEnabled = state.canRenameSavedAccounts
            submenu.addItem(option)
        }

        if submenu.items.isEmpty {
            let empty = NSMenuItem(title: "No saved accounts", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }

        item.submenu = submenu
        return item
    }

    private func refreshIntervalMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Refresh Time", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Refresh Time")

        let submenu = configuredMenu(title: "Refresh Time")
        for minutes in state.refreshIntervalOptions {
            let option = NSMenuItem(title: "\(minutes) minutes", action: #selector(MenuBarCoordinator.selectRefreshInterval(_:)), keyEquivalent: "")
            option.target = target
            option.representedObject = minutes
            option.state = state.refreshIntervalMinutes == minutes ? .on : .off
            submenu.addItem(option)
        }

        item.submenu = submenu
        return item
    }

    private func statusBarMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Status Item", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Status Item")

        let submenu = configuredMenu(title: "Status Item")
        submenu.addItem(statusBarDisplayMenuItem(state: state, target: target))
        submenu.addItem(statusBarStyleMenuItem(state: state, target: target))

        item.submenu = submenu
        return item
    }

    private func statusBarStyleMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "square.2.layers.3d.top.filled", accessibilityDescription: "Appearance")

        let submenu = configuredMenu(title: "Appearance")
        let monochrome = NSMenuItem(title: "Monochrome", action: #selector(MenuBarCoordinator.toggleStatusBarMonochrome(_:)), keyEquivalent: "")
        monochrome.target = target
        monochrome.state = state.statusBarMonochrome ? .on : .off
        submenu.addItem(monochrome)
        submenu.addItem(.separator())

        for style in StatusBarIndicatorStyle.allCases {
            let option = NSMenuItem(title: style.menuTitle, action: #selector(MenuBarCoordinator.selectStatusBarStyle(_:)), keyEquivalent: "")
            option.target = target
            option.representedObject = style.rawValue
            option.state = state.statusBarIndicatorStyle == style ? .on : .off
            submenu.addItem(option)
        }

        item.submenu = submenu
        return item
    }

    private func statusBarDisplayMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Content", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "character.textbox", accessibilityDescription: "Content")

        let submenu = configuredMenu(title: "Content")
        for mode in StatusBarDisplayMode.allCases {
            let option: NSMenuItem
            if state.canSelectStatusBarDisplayMode(mode) {
                option = NSMenuItem(title: mode.menuTitle, action: #selector(MenuBarCoordinator.selectStatusBarDisplayMode(_:)), keyEquivalent: "")
                option.target = target
                option.representedObject = mode.rawValue
            } else {
                option = disabledInfoItem(mode.menuTitle)
            }
            option.state = state.effectiveStatusBarDisplayMode == mode ? .on : .off
            submenu.addItem(option)
        }

        item.submenu = submenu
        return item
    }

    private func isLocallyActive(account: CodexAccount, state: MenuBarMenuState) -> Bool {
        state.activeAccount?.id == account.id
    }

    private func configuredMenu(title: String) -> NSMenu {
        NSMenu(title: title)
    }
}

private struct SectionHeaderLabel: View {
    let title: String
    let bottomPadding: CGFloat

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, bottomPadding)
    }
}
