import AppKit
import SwiftUI

/// The main menu: one card per tool, then the app's own items and Quit. Account actions live in each card's side menu.
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

        for (index, section) in state.toolSections.enumerated() {
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

        if let tokenUsage = state.tokenUsage {
            addSeparatorIfNeeded(to: menu)
            let item = NSMenuItem(title: "Token Usage", action: nil, keyEquivalent: "")
            item.view = hostedView(TokenUsageMenuContent(model: tokenUsage).padding(.vertical, 8), width: Self.menuContentWidth)
            menu.addItem(item)
        }

        addSeparatorIfNeeded(to: menu)
        menu.addItem(addAccountMenuItem(state: state, target: target))
        menu.addItem(.separator())
        let settings = actionItem("Settings…", action: #selector(MenuBarCoordinator.openSettings), target: target)
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(actionItem("Diagnostics…", action: #selector(MenuBarCoordinator.exportDiagnosticReport), isEnabled: !state.isBusy, target: target))
        menu.addItem(actionItem("About", action: #selector(MenuBarCoordinator.showAbout), isEnabled: !state.isBusy, target: target))

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
        let palette = ThemePalette(theme: state.theme)
        item.view = MenuCardItemView(
            ToolCardView(
                section: section,
                sessionAccentColor: Color(nsColor: state.sessionAccentColor ?? palette.sessionColor(for: section.provider.tokenUsageTool)),
                weeklyAccentColor: Color(nsColor: state.weeklyAccentColor ?? palette.weeklyColor(for: section.provider.tokenUsageTool)),
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
        if let source = section.signInSourceLabel {
            menu.addItem(disabledItem(source))
        }
        for other in section.otherAccounts {
            let actions = NSMenu(title: other.label)
            actions.addItem(providerItem(title: "Use", .switchAccount(other.id), for: provider, target: target))
            actions.addItem(providerItem(title: "Remove…", .removeAccount(other.id), for: provider, target: target))
            actions.items.forEach { $0.isEnabled = accountActionsEnabled }
            menu.addItem(accountItem(other, submenu: actions))
        }
        addSeparatorIfNeeded(to: menu)

        if let signIn = section.signInItem {
            menu.addItem(providerItem(title: signIn.title, signIn.action, for: provider, target: target))
            addSeparatorIfNeeded(to: menu)
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

        if let title = modelLimitsToggleTitle(section.modelLimitNames) {
            addSeparatorIfNeeded(to: menu)
            menu.addItem(toggleItem(title, isOn: state.showsModelLimits, action: #selector(MenuBarCoordinator.toggleShowsModelLimits(_:)), target: target))
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

    /// One toggle for every model limit in the reading: "Show Fable Limits", "Show Fable, Opus and Sonnet Limits".
    private func modelLimitsToggleTitle(_ names: [String]) -> String? {
        guard let last = names.last else { return nil }
        let models = names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
        return "Show \(models) Limits"
    }

    /// Only Codex has accounts to add. Claude and Cursor show the account their own app is signed in to, and
    /// `Show Tools` connects them.
    private func addAccountMenuItem(state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenuItem {
        let menu = NSMenu(title: "Add Account")
        let codex = providerItem(title: "\(UsageProvider.codex.copy.sectionTitle)…", .addAccount, for: .codex, target: target)
        codex.isEnabled = !state.isBusy
        menu.addItem(codex)
        return submenuItem(menu)
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
