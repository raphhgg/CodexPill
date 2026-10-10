import AppKit
import SwiftUI

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

        if !state.activeAccountCards.isEmpty {
            menu.addItem(sectionHeaderItem(state.activeAccountsSectionTitle, width: menuContentWidth, bottomPadding: 4))
            for (index, activeAccountCard) in state.activeAccountCards.enumerated() {
                if index > 0 {
                    menu.addItem(activeAccountDividerItem(width: menuContentWidth))
                }
                let tokenUsageCard = index == 0 ? state.tokenUsageCard : nil
                menu.addItem(activeAccountItem(
                    for: activeAccountCard,
                    state: state,
                    tokenUsageCard: tokenUsageCard,
                    width: menuContentWidth
                ))
            }
        } else {
            menu.addItem(sectionHeaderItem("Active Account", width: menuContentWidth, bottomPadding: 4))
            menu.addItem(disabledInfoItem("No active saved account"))
        }

        if !state.visibleDisplayAccountEntries.isEmpty {
            menu.addItem(.separator())
            menu.addItem(sectionHeaderItem(state.accountListSectionTitle, width: menuContentWidth, bottomPadding: 4))
            for entry in state.visibleDisplayAccountEntries {
                menu.addItem(inactiveAccountItem(for: entry, state: state, target: target, width: menuContentWidth))
            }
        }

        if !state.overflowDisplayAccountEntries.isEmpty {
            if state.visibleDisplayAccountEntries.isEmpty {
                menu.addItem(.separator())
            }
            menu.addItem(moreAccountsMenuItem(accounts: state.overflowDisplayAccountEntries, state: state, target: target))
        }

        menu.addItem(.separator())
        if state.shouldShowSingleAccountManagementMenu {
            menu.addItem(accountManagementMenuItem(state: state, target: target, includesAddAccount: true))
        } else if state.shouldShowActiveAccountManagementMenu {
            menu.addItem(accountManagementMenuItem(state: state, target: target, includesAddAccount: true))
        } else {
            menu.addItem(addAccountMenuItem(state: state, target: target))
        }
        menu.addItem(refreshIntervalMenuItem(state: state, target: target))
        menu.addItem(statusBarMenuItem(state: state, target: target))
        menu.addItem(actionItem(title: "Diagnostics…", systemImage: "doc.badge.gearshape", action: #selector(MenuBarCoordinator.exportDiagnosticReport), state: state, target: target))
        menu.addItem(actionItem(title: "About", systemImage: "info.circle", action: #selector(MenuBarCoordinator.showAbout), state: state, target: target))

        if state.shouldShowStatusMessage {
            menu.addItem(.separator())
            menu.addItem(disabledInfoItem(state.statusMessage))
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(MenuBarCoordinator.quitApp), keyEquivalent: "q")
        quit.image = menuIconSpacerImage()
        quit.target = target
        menu.addItem(quit)
    }

    private func activeAccountItem(
        for card: ActiveAccountCard,
        state: MenuBarMenuState,
        tokenUsageCard: TokenUsageMenuCard?,
        width: CGFloat
    ) -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSHostingView(
            rootView: ActiveAccountMenuContent(
                account: card.account,
                locations: card.locations,
                showsUpdatedTime: card.showsUpdatedTime,
                sessionAccentColor: Color(nsColor: state.sessionAccentColor),
                weeklyAccentColor: Color(nsColor: state.weeklyAccentColor),
                percentMode: state.usagePercentMode,
                meterLayout: state.usageMeterLayout,
                showsPacingMarkers: state.pacingMarkersEnabled,
                tokenUsageCard: tokenUsageCard,
                now: state.now
            )
        )
        item.view = configuredHostedMenuView(view, width: width)
        return item
    }

    private func activeAccountDividerItem(width: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSHostingView(rootView: ActiveAccountCardDivider())
        view.frame = NSRect(x: 0, y: 0, width: width, height: 17)
        item.view = view
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
        let widestNativeAccountRow = (state.visibleDisplayAccountEntries + state.overflowDisplayAccountEntries)
            .map {
                inactiveAccountTitleWidth(
                    for: $0.account,
                    displayName: compactMenuRowDisplayName(for: $0.account.name),
                    menuContentWidth: minimumMenuContentWidth,
                    percentMode: state.usagePercentMode,
                    now: state.now
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
            menuContentWidth: width,
            percentMode: state.usagePercentMode,
            now: state.now
        )
        item.submenu = inactiveAccountTargetMenu(for: entry, state: state, target: target)
        return item
    }

    private func inactiveAccountTargetMenu(for entry: MenuBarAccountCatalogEntry, state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenu {
        let account = entry.account
        let submenu = configuredMenu(title: account.name)
        submenu.addItem(inactiveAccountEmailItem(for: account))
        submenu.addItem(inactiveAccountUsageStatusItem(for: entry, state: state))
        submenu.addItem(.separator())

        let localItem = NSMenuItem(title: "Switch on This Mac", action: #selector(MenuBarCoordinator.switchAccount(_:)), keyEquivalent: "")
        localItem.target = target
        localItem.representedObject = account.id.uuidString
        localItem.isEnabled = true
        submenu.addItem(localItem)
        submenu.addItem(.separator())
        submenu.addItem(renameAccountMenuItem(for: account, state: state, target: target))
        submenu.addItem(removeAccountMenuItem(for: account, state: state, target: target))
        return submenu
    }

    private func inactiveAccountEmailItem(for account: CodexAccount) -> NSMenuItem {
        let email = account.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = email.flatMap { $0.isEmpty ? nil : $0 } ?? "No email"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func inactiveAccountUsageStatusItem(for entry: MenuBarAccountCatalogEntry, state: MenuBarMenuState) -> NSMenuItem {
        let item = NSMenuItem(title: usageStatusTitle(for: entry, state: state), action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func usageStatusTitle(for entry: MenuBarAccountCatalogEntry, state: MenuBarMenuState) -> String {
        state.activeAccount?.id == entry.account.id ? "In use on This Mac" : "Not currently in use"
    }

    private func actionItem(title: String, systemImage: String, action: Selector, state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        item.isEnabled = !state.isBusy
        return item
    }

    private func menuIconSpacerImage() -> NSImage {
        // Keep text-only rows aligned with icon-bearing native menu items.
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }

    private func addAccountMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Add Account…", action: #selector(MenuBarCoordinator.addAccount), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "Add Account")
        item.target = target
        item.isEnabled = state.canAddAccount
        return item
    }

    private func accountManagementMenuItem(
        state: MenuBarMenuState,
        target: MenuBarCoordinator,
        includesAddAccount: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: "Account", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "Account")

        let submenu = configuredMenu(title: "Account")
        if includesAddAccount {
            submenu.addItem(addAccountMenuItem(state: state, target: target))
            if state.accountForAccountManagementMenu != nil {
                submenu.addItem(.separator())
            }
        }

        if let account = state.accountForAccountManagementMenu {
            submenu.addItem(renameAccountMenuItem(for: account, state: state, target: target))
            submenu.addItem(removeAccountMenuItem(for: account, state: state, target: target))
        }

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
        let item = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Preferences")

        let submenu = configuredMenu(title: "Preferences")
        submenu.addItem(statusBarDisplayMenuItem(state: state, target: target))
        submenu.addItem(statusBarStyleMenuItem(state: state, target: target))
        submenu.addItem(usageBarsPreferencesMenuItem(state: state, target: target))
        submenu.addItem(tokenUsagePreferencesMenuItem(state: state, target: target))
        submenu.addItem(.separator())
        submenu.addItem(launchAtLoginMenuItem(state: state, target: target))

        item.submenu = submenu
        return item
    }

    private func launchAtLoginMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(
            title: state.loginItemState.menuTitle,
            action: launchAtLoginAction(for: state.loginItemState),
            keyEquivalent: ""
        )
        item.target = target
        item.state = state.loginItemState.isChecked ? .on : .off
        item.isEnabled = !state.isBusy
        return item
    }

    private func launchAtLoginAction(for state: LoginItemState) -> Selector? {
        switch state {
        case .enabled, .disabled:
            return #selector(MenuBarCoordinator.toggleLaunchAtLogin(_:))
        case .requiresApproval, .unavailable:
            return #selector(MenuBarCoordinator.openLoginItemsSettings(_:))
        }
    }

    private func usageBarsPreferencesMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Usage Bars", action: nil, keyEquivalent: "")
        let submenu = configuredMenu(title: "Usage Bars")
        for mode in UsagePercentMode.allCases {
            let option = NSMenuItem(title: mode.menuTitle, action: #selector(MenuBarCoordinator.selectUsagePercentMode(_:)), keyEquivalent: "")
            option.target = target
            option.representedObject = mode.rawValue
            option.state = state.usagePercentMode == mode ? .on : .off
            submenu.addItem(option)
        }
        submenu.addItem(.separator())
        for layout in UsageMeterLayout.allCases {
            let option = NSMenuItem(title: layout.menuTitle, action: #selector(MenuBarCoordinator.selectUsageMeterLayout(_:)), keyEquivalent: "")
            option.target = target
            option.representedObject = layout.rawValue
            option.state = state.usageMeterLayout == layout ? .on : .off
            submenu.addItem(option)
        }
        submenu.addItem(.separator())
        submenu.addItem(pacingMarkersMenuItem(state: state, target: target))
        submenu.addItem(.separator())
        submenu.addItem(usageColorItem(title: "Session Color…", action: #selector(MenuBarCoordinator.chooseSessionAccentColor(_:)), target: target))
        submenu.addItem(usageColorItem(title: "Weekly Color…", action: #selector(MenuBarCoordinator.chooseWeeklyAccentColor(_:)), target: target))
        submenu.addItem(oneUsageColorMenuItem(state: state, target: target))
        submenu.addItem(resetUsageColorsItem(state: state, target: target))
        item.submenu = submenu
        return item
    }

    private func tokenUsagePreferencesMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Token Usage", action: nil, keyEquivalent: "")
        let submenu = configuredMenu(title: "Token Usage")
        submenu.addItem(showTokenUsageMenuItem(state: state, target: target))
        submenu.addItem(tokenUsagePeakScopeMenuItem(state: state, target: target))
        submenu.addItem(tokenUsageChartStyleMenuItem(state: state, target: target))
        submenu.addItem(tokenUsageLoadingAnimationStyleMenuItem(state: state, target: target))
        item.submenu = submenu
        return item
    }

    private func showTokenUsageMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Show Token Usage", action: #selector(MenuBarCoordinator.toggleTokenUsage(_:)), keyEquivalent: "")
        item.target = target
        item.state = state.tokenUsageEnabled ? .on : .off
        return item
    }

    private func tokenUsagePeakScopeMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Peak Day", action: nil, keyEquivalent: "")
        let submenu = configuredMenu(title: "Peak Day")
        for scope in TokenUsagePeakScope.allCases {
            let option = NSMenuItem(title: scope.menuTitle, action: #selector(MenuBarCoordinator.selectTokenUsagePeakScope(_:)), keyEquivalent: "")
            option.target = target
            option.representedObject = scope.rawValue
            option.state = state.tokenUsagePeakScope == scope ? .on : .off
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    private func tokenUsageChartStyleMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Chart Style", action: nil, keyEquivalent: "")
        let submenu = configuredMenu(title: "Chart Style")
        for style in TokenUsageChartStyle.allCases {
            let option = NSMenuItem(title: style.menuTitle, action: #selector(MenuBarCoordinator.selectTokenUsageChartStyle(_:)), keyEquivalent: "")
            option.target = target
            option.representedObject = style.rawValue
            option.state = state.tokenUsageChartStyle == style ? .on : .off
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    private func tokenUsageLoadingAnimationStyleMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Loading Animation", action: nil, keyEquivalent: "")
        let submenu = configuredMenu(title: "Loading Animation")
        for style in TokenUsageLoadingAnimationStyle.allCases {
            let option = NSMenuItem(title: style.menuTitle, action: #selector(MenuBarCoordinator.selectTokenUsageLoadingAnimationStyle(_:)), keyEquivalent: "")
            option.target = target
            option.representedObject = style.rawValue
            option.state = state.tokenUsageLoadingAnimationStyle == style ? .on : .off
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    private func usageColorItem(title: String, action: Selector, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }

    private func oneUsageColorMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Same Color for Both", action: #selector(MenuBarCoordinator.toggleOneUsageColor(_:)), keyEquivalent: "")
        item.target = target
        item.state = state.usesOneUsageColor ? .on : .off
        return item
    }

    private func pacingMarkersMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Show Pace Markers", action: #selector(MenuBarCoordinator.togglePacingMarkers(_:)), keyEquivalent: "")
        item.target = target
        item.state = state.pacingMarkersEnabled ? .on : .off
        return item
    }

    private func resetUsageColorsItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Use Default Colors", action: #selector(MenuBarCoordinator.resetUsageColors(_:)), keyEquivalent: "")
        item.target = target
        item.isEnabled = state.hasCustomUsageColors
        return item
    }

    private func statusBarStyleMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: "Icon Style", action: nil, keyEquivalent: "")

        let submenu = configuredMenu(title: "Icon Style")
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
        let item = NSMenuItem(title: "Menu Bar Label", action: nil, keyEquivalent: "")

        let submenu = configuredMenu(title: "Menu Bar Label")
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
        submenu.addItem(.separator())
        submenu.addItem(revealShortcutMenuItem(state: state, target: target))

        item.submenu = submenu
        return item
    }

    private func revealShortcutMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(
            title: "Reveal Shortcut…",
            action: #selector(MenuBarCoordinator.configureRevealStatusItemTitleShortcut(_:)),
            keyEquivalent: ""
        )
        item.keyEquivalentModifierMask = []
        if let shortcut = state.revealStatusItemTitleShortcut {
            let presentation = KeyboardShortcutPresentation(shortcut: shortcut)
            if let keyEquivalent = presentation.keyEquivalent {
                item.keyEquivalent = keyEquivalent
                item.keyEquivalentModifierMask = presentation.modifierFlags
            }
        }
        item.target = target
        item.isEnabled = !state.isBusy
        return item
    }

    private func configuredMenu(title: String) -> NSMenu {
        NSMenu(title: title)
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
