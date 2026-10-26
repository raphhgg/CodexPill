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
            menu.addItem(tokenUsageItem(for: tokenUsage))
        }

        addSeparatorIfNeeded(to: menu)
        let settings = actionItem("Settings…", action: #selector(MenuBarCoordinator.openSettings), target: target)
        settings.keyEquivalent = ","
        // No other item has an icon, so the gear macOS adds to Settings… stays off. The API needs the macOS 27 SDK,
        // which ships with Swift 6.4.
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            settings.preferredImageVisibility = .hidden
        }
        #endif
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

    /// The whole card, or with the breakdown on hover, the chart with the breakdown in its side menu.
    private func tokenUsageItem(for model: TokenUsageCardModel) -> NSMenuItem {
        let item = NSMenuItem(title: "Token Usage", action: nil, keyEquivalent: "")
        guard model.settings.tokenUsage.display == .graphWithBreakdownOnHover else {
            item.view = hostedView(TokenUsageMenuContent(model: model).padding(.vertical, 8), width: Self.menuContentWidth)
            return item
        }
        item.view = MenuCardItemView(TokenUsageMenuContent(model: model, part: .graph).padding(.vertical, 8), width: Self.menuContentWidth)
        let submenu = NSMenu(title: "Token Usage")
        let breakdown = NSMenuItem(title: "Breakdown", action: nil, keyEquivalent: "")
        breakdown.view = hostedView(TokenUsageMenuContent(model: model, part: .breakdown).padding(.vertical, 8), width: Self.menuContentWidth)
        submenu.addItem(breakdown)
        item.submenu = submenu
        return item
    }

    /// The account in use and, for Codex, its resets. Everything else about accounts lives in Settings › Accounts.
    private func sideMenu(for section: ToolSection, state: MenuBarMenuState, target: MenuBarCoordinator) -> NSMenu {
        let menu = NSMenu(title: section.provider.copy.sectionTitle)

        if let activeLabel = section.activeLabel {
            let item = disabledItem(activeLabel)
            item.state = .on
            menu.addItem(item)
        }

        if let credits = section.card.resetCredits {
            addSeparatorIfNeeded(to: menu)
            let use = providerItem(title: "Use a Reset…", .useResetCredit, for: section.provider, target: target)
            use.isEnabled = !state.isBusy
            menu.addItem(use)
            for credit in (credits.credits ?? []).sorted(by: { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }) {
                let expiry = disabledItem(credit.expiresAt.map { "Expires \(shortDate($0, locale: locale, timeZone: timeZone))" } ?? "No expiry")
                expiry.indentationLevel = 1
                menu.addItem(expiry)
            }
        }
        return menu
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

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
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
