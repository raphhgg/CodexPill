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
        let accountActionsEnabled = provider != .codex || !state.isBusy
        let menu = NSMenu(title: title)

        if let active = section.activeAccount {
            menu.addItem(disabledItem(active.label))
            menu.addItem(.separator())
        }

        let others = section.otherAccounts
        if others.count == 1, let other = others.first {
            let item = providerItem(title: "Use \(other.label)", .switchAccount(other.id), for: provider, target: target)
            item.isEnabled = accountActionsEnabled
            menu.addItem(item)
        } else if others.count > 1 {
            let accounts = NSMenu(title: "Use Another \(title) Account")
            for other in others {
                let item = providerItem(title: other.label, .switchAccount(other.id), for: provider, target: target)
                item.isEnabled = accountActionsEnabled
                accounts.addItem(item)
            }
            menu.addItem(submenuItem(accounts))
        }

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

        addSeparatorIfNeeded(to: menu)
        let add = providerItem(title: "Add \(title) Account…", .addAccount, for: provider, target: target)
        add.isEnabled = accountActionsEnabled
        menu.addItem(add)
        if !section.accounts.isEmpty {
            let remove = NSMenu(title: "Remove \(title) Account")
            for account in section.accounts {
                let item = providerItem(title: "\(account.label)…", .removeAccount(account.id), for: provider, target: target)
                item.isEnabled = accountActionsEnabled
                remove.addItem(item)
            }
            menu.addItem(submenuItem(remove))
        }

        if provider != .codex {
            menu.addItem(.separator())
            menu.addItem(providerItem(title: "Disconnect \(title)", .disconnect, for: provider, target: target))
        }
        return menu
    }

    private func settingsMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let menu = NSMenu(title: "Settings")
        menu.addItem(addAccountMenuItem(state: state, target: target))
        menu.addItem(.separator())

        let appearance = NSMenu(title: "Appearance")
        appearance.addItem(statusBarDisplayMenuItem(state: state, target: target))
        appearance.addItem(statusBarStyleMenuItem(state: state, target: target))
        appearance.addItem(usageBarsMenuItem(state: state, target: target))
        appearance.addItem(.separator())
        appearance.addItem(toggleItem("Show Token Usage", isOn: state.tokenUsageEnabled, action: #selector(MenuBarCoordinator.toggleTokenUsage(_:)), target: target))
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

    /// Adds an account for any tool. A tool that is not connected yet connects instead.
    private func addAccountMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let menu = NSMenu(title: "Add Account")
        for provider in [UsageProvider.codex, .claude, .cursor] {
            let isConnected = provider == .codex || state.providerUsage.contains { $0.provider == provider && $0.status != .notConnected }
            let item = providerItem(title: "\(provider.copy.sectionTitle)…", isConnected ? .addAccount : .connect, for: provider, target: target)
            item.isEnabled = provider != .codex || !state.isBusy
            menu.addItem(item)
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
