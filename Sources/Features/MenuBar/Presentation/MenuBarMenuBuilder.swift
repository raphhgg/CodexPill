import AppKit
import SwiftUI

/// The main menu: one card per tool, Settings and Quit. Account actions live in each card's side menu.
@MainActor
struct MenuBarMenuBuilder {
    static let menuContentWidth: CGFloat = 372
    var locale: Locale = .autoupdatingCurrent
    var timeZone: TimeZone = .autoupdatingCurrent

    func makeMenu(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenu {
        let menu = NSMenu()
        populate(menu: menu, state: state, target: target)
        return menu
    }

    func populate(menu: NSMenu, state: MenuBarMenuState, target: MenuBarCoordinator) {
        menu.removeAllItems()
        menu.delegate = target

        let sections = state.toolSections
        if sections.isEmpty {
            menu.addItem(addAccountMenuItem(state: state, target: target))
        }
        for (index, section) in sections.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            menu.addItem(cardItem(for: section, state: state, target: target))
            if let followUp = section.followUp {
                let item = providerItem(title: followUp.title, followUp.action, for: section.provider, target: target)
                item.image = NSImage(systemSymbolName: followUp.systemImage, accessibilityDescription: followUp.title)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(settingsMenuItem(state: state, target: target))

        if state.shouldShowStatusMessage {
            menu.addItem(.separator())
            menu.addItem(disabledItem(state.statusMessage))
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(MenuBarCoordinator.quitApp), keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)
    }

    private func cardItem(for section: ToolSection, state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: section.provider.copy.sectionTitle, action: nil, keyEquivalent: "")
        item.view = MenuCardItemView(
            ToolCardView(
                section: section,
                sessionAccentColor: Color(nsColor: state.sessionAccentColor),
                weeklyAccentColor: Color(nsColor: state.weeklyAccentColor),
                percentMode: state.usagePercentMode,
                meterLayout: state.usageMeterLayout,
                showsPacingMarkers: state.pacingMarkersEnabled,
                now: state.now
            ),
            width: Self.menuContentWidth
        )
        item.submenu = sideMenu(for: section, state: state, target: target)
        return item
    }

    private func sideMenu(for section: ToolSection, state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenu {
        let provider = section.provider
        let title = provider.copy.sectionTitle
        let accountActionsEnabled = !state.isBusy
        let menu = NSMenu(title: title)

        if let activeLabel = section.activeLabel {
            let item = disabledItem(activeLabel)
            item.state = .on
            menu.addItem(item)
        }
        for other in section.otherAccounts {
            let actions = NSMenu(title: other.label)
            actions.addItem(providerItem(title: "Use", .switchAccount(other.id), for: provider, target: target))
            actions.addItem(providerItem(title: "Remove…", .removeAccount(other.id), for: provider, target: target))
            actions.items.forEach { $0.isEnabled = accountActionsEnabled }
            menu.addItem(accountItem(other, submenu: actions))
        }
        addSeparatorIfNeeded(to: menu)

        if let credits = section.card.resetCredits {
            let use = providerItem(title: "Use a Reset…", .useResetCredit, for: provider, target: target)
            use.isEnabled = accountActionsEnabled
            menu.addItem(use)
            for credit in (credits.credits ?? []).sorted(by: { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }) {
                let expiry = disabledItem(credit.expiresAt.map { "Expires \(shortDate($0, locale: locale, timeZone: timeZone))" } ?? "No expiry")
                expiry.indentationLevel = 1
                menu.addItem(expiry)
            }
        }

        if provider == .codex, let tokenUsageCard = state.tokenUsageCard {
            let tokenUsage = NSMenu(title: "Token Usage")
            let chart = NSMenuItem()
            chart.view = hostedView(TokenUsageMenuContent(card: tokenUsageCard).padding(.vertical, 12), width: 340)
            tokenUsage.addItem(chart)
            menu.addItem(submenuItem(tokenUsage))
        }

        let moves = ToolSectionMove.allCases.map { move in
            let item = NSMenuItem(title: move.title, action: #selector(MenuBarCoordinator.reorderTools(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = state.toolOrder(moving: provider, move)
            item.isEnabled = item.representedObject != nil
            return item
        }
        if moves.contains(where: \.isEnabled) {
            addSeparatorIfNeeded(to: menu)
            moves.forEach(menu.addItem)
        }

        if provider == .codex {
            addSeparatorIfNeeded(to: menu)
            let add = providerItem(title: "Add \(title) Account…", .addAccount, for: provider, target: target)
            add.isEnabled = accountActionsEnabled
            menu.addItem(add)
        }
        if menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.numberOfItems - 1)
        }
        return menu
    }

    private func settingsMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let menu = NSMenu(title: "Settings")
        menu.addItem(addAccountMenuItem(state: state, target: target))
        for usage in state.providerUsage where usage.status != .notConnected {
            menu.addItem(providerItem(title: "Disconnect \(usage.provider.copy.sectionTitle)", .disconnect, for: usage.provider, target: target))
        }
        menu.addItem(.separator())

        let appearance = NSMenu(title: "Appearance")
        appearance.addItem(statusBarDisplayMenuItem(state: state, target: target))
        appearance.addItem(statusBarStyleMenuItem(state: state, target: target))
        appearance.addItem(usageBarsMenuItem(state: state, target: target))
        appearance.addItem(.separator())
        appearance.addItem(toggleItem("Show Token Usage", isOn: state.tokenUsageEnabled, action: #selector(MenuBarCoordinator.toggleTokenUsage(_:)), target: target))
        appearance.addItem(toggleItem("Show Model Limits", isOn: state.showsModelLimits, action: #selector(MenuBarCoordinator.toggleShowsModelLimits(_:)), target: target))
        menu.addItem(submenuItem(appearance))
        menu.addItem(toggleItem("Hide Emails", isOn: state.masksEmails, action: #selector(MenuBarCoordinator.toggleMasksEmails(_:)), target: target))
        menu.addItem(refreshIntervalMenuItem(state: state, target: target))
        menu.addItem(launchAtLoginMenuItem(state: state, target: target))

        menu.addItem(.separator())
        menu.addItem(actionItem("Diagnostics…", action: #selector(MenuBarCoordinator.exportDiagnosticReport), isEnabled: !state.isBusy, target: target))
        menu.addItem(actionItem("About", action: #selector(MenuBarCoordinator.showAbout), isEnabled: !state.isBusy, target: target))

        let item = submenuItem(menu)
        item.keyEquivalent = ","
        return item
    }

    /// Adds a Codex account, or connects Claude or Cursor while they are not connected. Those two show only the
    /// account their own app is signed in to.
    private func addAccountMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let menu = NSMenu(title: "Add Account")
        let codex = providerItem(title: "\(UsageProvider.codex.copy.sectionTitle)…", .addAccount, for: .codex, target: target)
        codex.isEnabled = !state.isBusy
        menu.addItem(codex)
        for provider in [UsageProvider.claude, .cursor]
        where !state.providerUsage.contains(where: { $0.provider == provider && $0.status != .notConnected }) {
            menu.addItem(providerItem(title: "\(provider.copy.sectionTitle)…", .connect, for: provider, target: target))
        }
        return submenuItem(menu)
    }

    private func refreshIntervalMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let menu = NSMenu(title: "Refresh Every")
        for minutes in state.refreshIntervalOptions {
            let option = NSMenuItem(title: minutes == 1 ? "1 minute" : "\(minutes) minutes", action: #selector(MenuBarCoordinator.selectRefreshInterval(_:)), keyEquivalent: "")
            option.target = target
            option.representedObject = minutes
            option.state = state.refreshIntervalMinutes == minutes ? .on : .off
            menu.addItem(option)
        }
        return submenuItem(menu)
    }

    private func launchAtLoginMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let action = switch state.loginItemState {
        case .enabled, .disabled: #selector(MenuBarCoordinator.toggleLaunchAtLogin(_:))
        case .requiresApproval, .unavailable: #selector(MenuBarCoordinator.openLoginItemsSettings(_:))
        }
        let item = actionItem(state.loginItemState.menuTitle, action: action, isEnabled: !state.isBusy, target: target)
        item.state = state.loginItemState.isChecked ? .on : .off
        return item
    }

    private func usageBarsMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let menu = NSMenu(title: "Usage Bars")
        for mode in UsagePercentMode.allCases {
            menu.addItem(optionItem(mode.menuTitle, value: mode.rawValue, isOn: state.usagePercentMode == mode, action: #selector(MenuBarCoordinator.selectUsagePercentMode(_:)), target: target))
        }
        menu.addItem(.separator())
        for layout in UsageMeterLayout.allCases {
            menu.addItem(optionItem(layout.menuTitle, value: layout.rawValue, isOn: state.usageMeterLayout == layout, action: #selector(MenuBarCoordinator.selectUsageMeterLayout(_:)), target: target))
        }
        menu.addItem(.separator())
        menu.addItem(toggleItem("Show Pace Markers", isOn: state.pacingMarkersEnabled, action: #selector(MenuBarCoordinator.togglePacingMarkers(_:)), target: target))
        menu.addItem(.separator())
        menu.addItem(actionItem("Session Color…", action: #selector(MenuBarCoordinator.chooseSessionAccentColor(_:)), target: target))
        menu.addItem(actionItem("Weekly Color…", action: #selector(MenuBarCoordinator.chooseWeeklyAccentColor(_:)), target: target))
        menu.addItem(toggleItem("Same Color for Both", isOn: state.usesOneUsageColor, action: #selector(MenuBarCoordinator.toggleOneUsageColor(_:)), target: target))
        menu.addItem(actionItem("Use Default Colors", action: #selector(MenuBarCoordinator.resetUsageColors(_:)), isEnabled: state.hasCustomUsageColors, target: target))
        return submenuItem(menu)
    }

    private func statusBarStyleMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let menu = NSMenu(title: "Icon Style")
        menu.addItem(toggleItem("Monochrome", isOn: state.statusBarMonochrome, action: #selector(MenuBarCoordinator.toggleStatusBarMonochrome(_:)), target: target))
        menu.addItem(.separator())
        for style in StatusBarIndicatorStyle.allCases {
            menu.addItem(optionItem(style.menuTitle, value: style.rawValue, isOn: state.statusBarIndicatorStyle == style, action: #selector(MenuBarCoordinator.selectStatusBarStyle(_:)), target: target))
        }
        return submenuItem(menu)
    }

    private func statusBarDisplayMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let menu = NSMenu(title: "Menu Bar Label")
        for mode in StatusBarDisplayMode.allCases {
            let option = state.canSelectStatusBarDisplayMode(mode)
                ? optionItem(mode.menuTitle, value: mode.rawValue, isOn: false, action: #selector(MenuBarCoordinator.selectStatusBarDisplayMode(_:)), target: target)
                : disabledItem(mode.menuTitle)
            option.state = state.effectiveStatusBarDisplayMode == mode ? .on : .off
            menu.addItem(option)
        }
        menu.addItem(.separator())
        menu.addItem(revealShortcutMenuItem(state: state, target: target))
        return submenuItem(menu)
    }

    private func revealShortcutMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let item = actionItem("Reveal Shortcut…", action: #selector(MenuBarCoordinator.configureRevealStatusItemTitleShortcut(_:)), isEnabled: !state.isBusy, target: target)
        item.keyEquivalentModifierMask = []
        if let shortcut = state.revealStatusItemTitleShortcut {
            let presentation = KeyboardShortcutPresentation(shortcut: shortcut)
            if let keyEquivalent = presentation.keyEquivalent {
                item.keyEquivalent = keyEquivalent
                item.keyEquivalentModifierMask = presentation.modifierFlags
            }
        }
        return item
    }

    /// A saved account that is not in use, with its last limits on a second, smaller line.
    private func accountItem(_ account: ToolAccount, submenu: NSMenu) -> NSMenuItem {
        let item = submenuItem(submenu)
        if let usageLine = account.usageLine {
            let attributed = NSMutableAttributedString(string: account.label, attributes: [.font: NSFont.menuFont(ofSize: 0)])
            attributed.append(NSAttributedString(
                string: "\n" + usageLine,
                attributes: [.font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]
            ))
            item.attributedTitle = attributed
        }
        return item
    }

    private func providerItem(title: String, _ action: ProviderAction, for provider: UsageProvider, target: MenuBarCoordinator) -> NSMenuItem {
        let item = actionItem(title, action: #selector(MenuBarCoordinator.performProviderAction(_:)), target: target)
        item.representedObject = ProviderMenuAction(provider: provider, action: action)
        return item
    }

    private func actionItem(_ title: String, action: Selector, isEnabled: Bool = true, target: MenuBarCoordinator) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.isEnabled = isEnabled
        return item
    }

    private func toggleItem(_ title: String, isOn: Bool, action: Selector, target: MenuBarCoordinator) -> NSMenuItem {
        let item = actionItem(title, action: action, target: target)
        item.state = isOn ? .on : .off
        return item
    }

    private func optionItem(_ title: String, value: String, isOn: Bool, action: Selector, target: MenuBarCoordinator) -> NSMenuItem {
        let item = toggleItem(title, isOn: isOn, action: action, target: target)
        item.representedObject = value
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func submenuItem(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func addSeparatorIfNeeded(to menu: NSMenu) {
        guard let last = menu.items.last, !last.isSeparatorItem else { return }
        menu.addItem(.separator())
    }

    private func hostedView(_ content: some View, width: CGFloat) -> NSView {
        let view = NSHostingView(rootView: content.frame(width: width))
        view.frame = NSRect(x: 0, y: 0, width: width, height: max(1, view.fittingSize.height))
        return view
    }
}
