import AppKit
import SwiftUI

final class HostSelectionMenuItemPayload: NSObject {
    let hostDestination: String

    init(hostDestination: String) {
        self.hostDestination = hostDestination
    }
}

final class HostAccountMenuItemPayload: NSObject {
    let accountID: UUID
    let hostDestination: String

    init(accountID: UUID, hostDestination: String) {
        self.accountID = accountID
        self.hostDestination = hostDestination
    }
}

@MainActor
struct MenuBarMenuBuilder {
    private let minimumMenuContentWidth: CGFloat = 372
    private let nativeMenuItemPaddingAllowance: CGFloat = 52

    func makeMenu(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenu {
        let menu = NSMenu()
        populate(menu: menu, state: state, target: target)
        return menu
    }

    func populate(menu: NSMenu, state: MenuBarMenuState, target: MenuBarCoordinator) {
        let menuContentWidth = contentWidth(for: state)

        menu.removeAllItems()
        menu.delegate = target

        if let activeAccount = state.activeAccount {
            menu.addItem(sectionHeaderItem("Current Account", width: menuContentWidth, bottomPadding: 4))
            menu.addItem(activeAccountItem(for: activeAccount, state: state, width: menuContentWidth))
        } else {
            menu.addItem(sectionHeaderItem("Current Account", width: menuContentWidth, bottomPadding: 4))
            menu.addItem(disabledInfoItem("No active saved account"))
        }

        if !state.connectedRemoteHosts.isEmpty {
            menu.addItem(.separator())
            menu.addItem(sectionHeaderItem("Remote Accounts", width: menuContentWidth, bottomPadding: 4))
            for remoteHost in state.connectedRemoteHosts {
                menu.addItem(remoteHostItem(for: remoteHost, state: state, width: menuContentWidth))
            }
        }

        if !state.visibleAccountEntries.isEmpty {
            menu.addItem(.separator())
            menu.addItem(sectionHeaderItem("Accounts", width: menuContentWidth, bottomPadding: 4))
            for entry in state.visibleAccountEntries {
                menu.addItem(inactiveAccountItem(for: entry, state: state, target: target, width: menuContentWidth))
            }
        }

        if !state.overflowAccountEntries.isEmpty {
            if state.visibleAccountEntries.isEmpty {
                menu.addItem(.separator())
            }
            menu.addItem(moreAccountsMenuItem(accounts: state.overflowAccountEntries, state: state, target: target))
        }

        menu.addItem(.separator())
        menu.addItem(addAccountMenuItem(state: state, target: target))
        menu.addItem(hostsMenuItem(state: state, target: target))
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

    private func activeAccountItem(for account: CodexAccount, state: MenuBarMenuState, width: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSHostingView(
            rootView: ActiveAccountMenuContent(
                account: account,
                progressAccentColor: Color(nsColor: state.progressAccentColor)
            )
        )
        item.view = configuredHostedMenuView(view, width: width)
        return item
    }

    private func remoteHostItem(for remoteHost: RemoteHostMenuState, state: MenuBarMenuState, width: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSHostingView(
            rootView: RemoteHostMenuContent(
                remoteHost: remoteHost,
                progressAccentColor: Color(nsColor: state.progressAccentColor)
            )
        )
        item.view = configuredHostedMenuView(view, width: width)
        return item
    }

    private func configuredHostedMenuView(_ view: NSHostingView<some View>, width: CGFloat) -> NSView {
        view.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        view.layoutSubtreeIfNeeded()
        let fittingSize = view.fittingSize
        let fittingHeight = max(1, fittingSize.height)
        view.frame = NSRect(x: 0, y: 0, width: width, height: fittingHeight)
        return view
    }

    private func sectionHeaderItem(_ title: String, width: CGFloat, bottomPadding: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSHostingView(rootView: SectionHeaderLabel(title: title, bottomPadding: bottomPadding))
        view.frame = NSRect(x: 0, y: 0, width: width, height: 18 + bottomPadding)
        item.view = view
        return item
    }

    private func contentWidth(for state: MenuBarMenuState) -> CGFloat {
        let widestNativeAccountRow = (state.visibleAccountEntries + state.overflowAccountEntries)
            .map {
                inactiveAccountTitleWidth(
                    for: $0.account,
                    displayName: compactMenuRowDisplayName(for: $0.account.name),
                    placement: nil,
                    menuContentWidth: minimumMenuContentWidth
                ) + nativeMenuItemPaddingAllowance
            }
            .max() ?? 0

        return max(minimumMenuContentWidth, widestNativeAccountRow)
    }

    private func disabledInfoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func inactiveAccountItem(for entry: MenuBarAccountCatalogEntry, state: MenuBarMenuState, target: MenuBarCoordinator, width: CGFloat) -> NSMenuItem {
        let item = NSMenuItem(title: entry.account.name, action: nil, keyEquivalent: "")
        item.representedObject = entry.account.id.uuidString
        item.attributedTitle = inactiveAccountTitle(
            for: entry.account,
            displayName: compactMenuRowDisplayName(for: entry.account.name),
            placement: nil,
            menuContentWidth: width
        )
        item.submenu = inactiveAccountTargetMenu(for: entry, state: state, target: target)
        return item
    }

    private func inactiveAccountTargetMenu(for entry: MenuBarAccountCatalogEntry, state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenu {
        let account = entry.account
        let submenu = configuredMenu(title: account.name)
        submenu.addItem(inactiveAccountUsageStatusItem(for: entry, state: state))
        submenu.addItem(.separator())

        let localItem = NSMenuItem(title: "Switch on This Mac", action: #selector(MenuBarCoordinator.switchAccount(_:)), keyEquivalent: "")
        localItem.target = target
        localItem.representedObject = account.id.uuidString
        localItem.isEnabled = true
        submenu.addItem(localItem)
        for remoteHost in state.remoteHosts {
            submenu.addItem(
                switchTargetMenuItem(
                    title: remoteHost.hasDeployedAccount(account)
                        ? "Switch on \(remoteHost.name)"
                        : "Install on \(remoteHost.name) and switch",
                    account: account,
                    hostDestination: remoteHost.destination,
                    target: target
                )
            )
        }
        submenu.addItem(.separator())
        submenu.addItem(renameAccountMenuItem(for: account, state: state, target: target))
        submenu.addItem(removeAccountMenuItem(for: account, state: state, target: target))
        return submenu
    }

    private func inactiveAccountUsageStatusItem(for entry: MenuBarAccountCatalogEntry, state: MenuBarMenuState) -> NSMenuItem {
        let item = NSMenuItem(title: usageStatusTitle(for: entry, state: state), action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func usageStatusTitle(for entry: MenuBarAccountCatalogEntry, state: MenuBarMenuState) -> String {
        var locations: [String] = []
        if state.activeAccount?.id == entry.account.id {
            locations.append("This Mac")
        }

        locations.append(contentsOf: state.connectedRemoteHosts.compactMap { remoteHost in
            remoteHost.activeAccount?.id == entry.account.id ? remoteHost.name : nil
        })

        guard !locations.isEmpty else {
            return "Not currently in use"
        }

        return "In use on: \(locations.joined(separator: ", "))"
    }

    private func switchTargetMenuItem(
        title: String,
        account: CodexAccount,
        hostDestination: String,
        target: MenuBarCoordinator
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuBarCoordinator.switchAccountOnHost(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = HostAccountMenuItemPayload(accountID: account.id, hostDestination: hostDestination)
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
        let item = NSMenuItem(title: "Add Account…", action: nil, keyEquivalent: "")
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

    private func hostsMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Hosts", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "Hosts")

        let submenu = configuredMenu(title: "Hosts")
        let addHost = NSMenuItem(title: "Add Host…", action: #selector(MenuBarCoordinator.addHost(_:)), keyEquivalent: "")
        addHost.target = target
        addHost.isEnabled = state.canConfigureHosts
        submenu.addItem(addHost)

        if !state.remoteHosts.isEmpty {
            submenu.addItem(.separator())
            for remoteHost in state.remoteHosts {
                submenu.addItem(configuredHostMenuItem(remoteHost, state: state, target: target))
            }
        }

        item.submenu = submenu
        return item
    }

    private func configuredHostMenuItem(_ remoteHost: RemoteHostMenuState, state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: remoteHost.name, action: nil, keyEquivalent: "")
        let submenu = configuredMenu(title: remoteHost.name)

        let status = NSMenuItem(title: "\(remoteHost.name) (\(remoteHost.destination))", action: nil, keyEquivalent: "")
        status.isEnabled = false
        submenu.addItem(status)

        let connection = NSMenuItem(title: "Status: \(remoteHost.connectionState.menuTitle)", action: nil, keyEquivalent: "")
        connection.isEnabled = false
        submenu.addItem(connection)

        let removeHost = NSMenuItem(title: "Remove Host", action: #selector(MenuBarCoordinator.removeHost(_:)), keyEquivalent: "")
        removeHost.target = target
        removeHost.representedObject = HostSelectionMenuItemPayload(hostDestination: remoteHost.destination)
        removeHost.isEnabled = state.canConfigureHosts
        submenu.addItem(removeHost)

        item.submenu = submenu
        return item
    }

    private func removeAccountMenuItem(for account: CodexAccount, state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Remove…", action: #selector(MenuBarCoordinator.removeAccount(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = account.id.uuidString
        item.isEnabled = state.canRemoveSavedAccounts
        return item
    }

    private func moreAccountsMenuItem(accounts: [MenuBarAccountCatalogEntry], state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "More Accounts…", action: nil, keyEquivalent: "")

        let submenu = configuredMenu(title: "More Accounts…")
        for account in accounts {
            submenu.addItem(inactiveAccountItem(for: account, state: state, target: target, width: minimumMenuContentWidth))
        }

        item.submenu = submenu
        return item
    }

    private func renameAccountMenuItem(for account: CodexAccount, state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Rename…", action: #selector(MenuBarCoordinator.renameAccount(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = account.id.uuidString
        item.isEnabled = state.canRenameSavedAccounts
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
        let item = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Display")

        let submenu = configuredMenu(title: "Display")
        submenu.addItem(statusBarDisplayMenuItem(state: state, target: target))
        submenu.addItem(statusBarStyleMenuItem(state: state, target: target))
        submenu.addItem(.separator())
        submenu.addItem(progressAccentColorItem(state: state, target: target))
        submenu.addItem(resetProgressAccentColorItem(state: state, target: target))

        item.submenu = submenu
        return item
    }

    private func progressAccentColorItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Accent Color…", action: #selector(MenuBarCoordinator.chooseProgressAccentColor(_:)), keyEquivalent: "")
        item.target = target
        item.image = colorSwatchImage(for: state.progressAccentColor)
        return item
    }

    private func resetProgressAccentColorItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Use Default", action: #selector(MenuBarCoordinator.resetProgressAccentColor(_:)), keyEquivalent: "")
        item.target = target
        item.isEnabled = state.hasCustomProgressAccentColor
        return item
    }

    private func statusBarStyleMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Indicator", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "square.2.layers.3d.top.filled", accessibilityDescription: "Indicator")

        let submenu = configuredMenu(title: "Indicator")
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

    private func configuredMenu(title: String) -> NSMenu {
        NSMenu(title: title)
    }

    private func colorSwatchImage(for color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        color.setFill()
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

private struct SectionHeaderLabel: View {
    let title: String
    let bottomPadding: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, bottomPadding)
    }
}
