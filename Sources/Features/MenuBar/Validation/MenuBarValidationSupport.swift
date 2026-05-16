import AppKit
import CryptoKit
import SwiftUI

struct MenuBarValidationSnapshot: Codable, Equatable {
    struct Rect: Codable, Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Point: Codable, Equatable {
        let x: Double
        let y: Double
    }

    struct Section: Codable, Equatable {
        let title: String
        let items: [String]
    }

    struct AccountIdentity: Codable, Equatable {
        let name: String
        let email: String?
        let planType: String?
        let identityDigest: String?
    }

    struct RemoteHostState: Codable, Equatable {
        let name: String
        let connectionState: String
        let desiredAccount: AccountIdentity?
        let activeAccount: AccountIdentity?
        let detectedAccount: AccountIdentity?
        let verificationStatus: String
        let lastVerificationError: String?
    }

    struct MenuItem: Codable, Equatable {
        let title: String
        let isEnabled: Bool
        let state: String
        let hasAction: Bool
        let actionSelector: String?
        let isSeparator: Bool
        let viewFrameWidth: Double?
        let children: [MenuItem]
    }

    struct StatusItemState: Codable, Equatable {
        let isHovered: Bool
        let isPointerInsideButton: Bool
        let isTitleVisible: Bool
        let displayedTitle: String?
        let imagePosition: String
        let buttonFrame: Rect?
        let pointerLocation: Point?
    }

    struct ActionTrace: Codable, Equatable {
        let lastMenuAction: String?
        let lastSwitchTargetName: String?
        let lastConfirmationRequest: String?
        let lastConfirmationAccepted: Bool?
    }

    let sections: [Section]
    let statusMessage: String?
    let currentAccount: AccountIdentity?
    let remoteHosts: [RemoteHostState]
    let hasStatusItemContentData: Bool
    let effectiveStatusBarDisplayMode: String
    let statusItem: StatusItemState?
    let actionTrace: ActionTrace?
    let menuItems: [MenuItem]
}

@MainActor
enum MenuBarValidationSupport {
    static func makeSnapshot(
        state: MenuBarMenuState,
        menu: NSMenu? = nil,
        statusItemState: StatusItemRuntimeSnapshot? = nil,
        actionTrace: MenuBarValidationSnapshot.ActionTrace? = nil,
        now: Date = .now
    ) -> MenuBarValidationSnapshot {
        var sections: [MenuBarValidationSnapshot.Section] = []

        sections.append(contentsOf: accountSections(for: state, now: now))

        sections.append(.init(
            title: "Manage Accounts",
            items: managementSectionItems(for: state)
        ))

        sections.append(.init(
            title: "Preferences",
            items: [
                "Refresh Time: \(state.refreshIntervalMinutes) minutes",
                "Menu Bar Label: \(state.effectiveStatusBarDisplayMode.menuTitle)",
                "Reveal Shortcut: \(state.revealStatusItemTitleShortcut.map { KeyboardShortcutPresentation(shortcut: $0).displayTitle } ?? "None")",
                "Icon Style: \(state.statusBarIndicatorStyle.menuTitle)",
                "Usage Bar Display: \(state.usageBarDisplayMode.menuTitle)",
                "Usage Bar Layout: \(state.usageBarLayout.menuTitle)",
                state.pacingMarkersEnabled ? "Show Pace Markers: On" : "Show Pace Markers: Off",
                "Accent Color: \(colorHexString(for: state.progressAccentColor))",
                state.statusBarMonochrome ? "Monochrome: On" : "Monochrome: Off",
                "Launch at Login: \(launchAtLoginSummary(for: state.loginItemState))",
                state.canShowAbout ? "About" : "About (disabled)"
            ]
        ))

        if state.showsPacingPrototypeMenu {
            sections.append(.init(
                title: "Pacing Prototypes",
                items: PacingPrototypeVariant.allCases.map { variant in
                    pacingPrototypeSummary(for: variant)
                }
            ))
        }

        return MenuBarValidationSnapshot(
            sections: sections,
            statusMessage: state.shouldShowStatusMessage ? state.statusMessage : nil,
            currentAccount: state.activeAccount.map(accountIdentity(for:)),
            remoteHosts: state.connectedRemoteHosts.map(remoteHostState(for:)),
            hasStatusItemContentData: state.hasStatusItemContentData,
            effectiveStatusBarDisplayMode: state.effectiveStatusBarDisplayMode.rawValue,
            statusItem: statusItemState.map(statusItemState(from:)),
            actionTrace: actionTrace,
            menuItems: menuItems(from: menu)
        )
    }

    private static func accountSections(for state: MenuBarMenuState, now: Date) -> [MenuBarValidationSnapshot.Section] {
        var sections: [MenuBarValidationSnapshot.Section] = []

        if !state.activeAccountCards.isEmpty {
            sections.append(.init(
                title: state.activeAccountsSectionTitle,
                items: state.activeAccountCards.map { card in
                    accountSummary(
                        for: card.account,
                        location: activeAccountLocationLine(for: card, now: now),
                        usageBarDisplayMode: state.usageBarDisplayMode,
                        now: now
                    )
                }
            ))
        } else {
            sections.append(.init(title: "Active Account", items: ["No active saved account"]))
        }

        if !state.visibleDisplayAccountEntries.isEmpty {
            sections.append(.init(
                title: state.accountListSectionTitle,
                items: state.visibleDisplayAccountEntries.map {
                    inactiveAccountSummary(for: $0, usageBarDisplayMode: state.usageBarDisplayMode, now: now)
                }
            ))
        }

        if !state.overflowDisplayAccountEntries.isEmpty {
            sections.append(.init(
                title: "More Accounts…",
                items: state.overflowDisplayAccountEntries.map {
                    inactiveAccountSummary(for: $0, usageBarDisplayMode: state.usageBarDisplayMode, now: now)
                }
            ))
        }

        return sections
    }

    static func makeHostedValidationView(state: MenuBarMenuState, now: Date = .now) -> some View {
        let snapshot = makeSnapshot(state: state, now: now)

        return Group {
            if state.showsPacingPrototypeMenu {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pacing Active Account Card Prototypes")
                        .font(.system(size: 16, weight: .semibold))
                    ForEach(PacingPrototypeVariant.allCases) { variant in
                        PacingPrototypeMenuContent(
                            variant: variant,
                            accentColor: Color(nsColor: state.progressAccentColor)
                        )
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(snapshot.sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                Text(item)
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 3)
                            }
                        }
                    }

                    if let statusMessage = snapshot.statusMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Divider()
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: state.showsPacingPrototypeMenu ? 720 : 360, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func accountSummary(
        for account: CodexAccount,
        location: String? = nil,
        usageBarDisplayMode: UsageBarDisplayMode,
        now: Date
    ) -> String {
        let plan = menuPlanDisplayName(account.effectivePlanType)
        let session = usageLine(
            title: "Session",
            window: account.rateLimits?.sessionWindow,
            usageBarDisplayMode: usageBarDisplayMode,
            now: now
        )
        let weekly = usageLine(
            title: "Weekly",
            window: account.rateLimits?.weeklyWindow,
            usageBarDisplayMode: usageBarDisplayMode,
            now: now
        )
        return ([account.name, plan, location, session, weekly].compactMap { $0 }).joined(separator: " • ")
    }

    private static func inactiveAccountSummary(
        for entry: MenuBarAccountCatalogEntry,
        usageBarDisplayMode: UsageBarDisplayMode,
        now: Date
    ) -> String {
        let detail = compactMenuRowUsageSummary(
            for: entry.account,
            usageBarDisplayMode: usageBarDisplayMode,
            now: now
        )
        guard let placement = entry.placement else {
            return "\(entry.account.name) • \(detail)"
        }
        return "\(entry.account.name) • \(detail) • \(placement.badgeText)"
    }

    private static func activeAccountLocationLine(for card: ActiveAccountCard, now: Date) -> String {
        if !card.locations.isEmpty {
            return card.locations.joined(separator: " + ")
        }
        if card.showsUpdatedTime {
            return "Updated \(compactElapsedTime(since: card.account.lastRemoteRefreshAt, now: now)) ago"
        }
        return "This Mac"
    }

    private static func usageLine(
        title: String,
        window: CodexRateLimitWindow?,
        usageBarDisplayMode: UsageBarDisplayMode,
        now: Date
    ) -> String {
        let percentText = usageBarPercentText(for: window, mode: usageBarDisplayMode, now: now)
        guard let window, let resetStatus = resetStatusText(for: window, now: now) else {
            return "\(title): \(percentText)"
        }
        return "\(title): \(percentText), \(resetStatus)"
    }

    private static func pacingPrototypeSummary(for variant: PacingPrototypeVariant) -> String {
        "\(variant.title): Session and Weekly current-card prototype"
    }

    private static func managementSectionItems(for state: MenuBarMenuState) -> [String] {
        [state.canAddAccount ? "Add Account…" : "Add Account… (disabled)"]
    }

    private static func colorHexString(for color: NSColor) -> String {
        let normalized = (color.usingColorSpace(.deviceRGB) ?? color.usingColorSpace(.sRGB)) ?? color
        let red = Int(round(normalized.redComponent * 255))
        let green = Int(round(normalized.greenComponent * 255))
        let blue = Int(round(normalized.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func launchAtLoginSummary(for state: LoginItemState) -> String {
        switch state {
        case .enabled:
            return "On"
        case .disabled:
            return "Off"
        case .requiresApproval:
            return "Needs Approval"
        case .unavailable:
            return "Unavailable"
        }
    }

    private static func accountIdentity(for account: CodexAccount) -> MenuBarValidationSnapshot.AccountIdentity {
        MenuBarValidationSnapshot.AccountIdentity(
            name: account.name,
            email: account.email,
            planType: account.effectivePlanType,
            identityDigest: identityDigest(for: account)
        )
    }

    private static func remoteHostState(for remoteHost: RemoteHostMenuState) -> MenuBarValidationSnapshot.RemoteHostState {
        .init(
            name: remoteHost.name,
            connectionState: remoteHost.connectionState.rawValue,
            desiredAccount: remoteHost.desiredAccount.map(accountIdentity(for:)),
            activeAccount: remoteHost.activeAccount.map(accountIdentity(for:)),
            detectedAccount: remoteHost.detectedAccount.map(accountIdentity(for:)),
            verificationStatus: remoteHost.verificationStatus.rawValue,
            lastVerificationError: remoteHost.lastVerificationError
        )
    }

    private static func identityDigest(for account: CodexAccount) -> String? {
        let components = [
            account.identity.stableAccountID,
            account.identity.authPrincipalIdentity?.subject,
            account.identity.authPrincipalIdentity?.chatGPTUserID,
            account.identity.workspaceIdentity?.workspaceAccountID
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        guard !components.isEmpty else { return nil }

        let digest = SHA256.hash(data: Data(components.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func menuItems(from menu: NSMenu?) -> [MenuBarValidationSnapshot.MenuItem] {
        guard let menu else { return [] }
        return menu.items.map(menuItem(from:))
    }

    private static func menuItem(from item: NSMenuItem) -> MenuBarValidationSnapshot.MenuItem {
        let actionSelector = normalizedActionSelector(for: item)
        return MenuBarValidationSnapshot.MenuItem(
            title: menuItemTitle(for: item),
            isEnabled: item.isEnabled,
            state: menuItemStateName(item.state),
            hasAction: actionSelector != nil,
            actionSelector: actionSelector,
            isSeparator: item.isSeparatorItem,
            viewFrameWidth: item.view.map { Double($0.frame.width) },
            children: item.submenu.map { $0.items.map(menuItem(from:)) } ?? []
        )
    }

    private static func normalizedActionSelector(for item: NSMenuItem) -> String? {
        guard let action = item.action else { return nil }
        let selector = NSStringFromSelector(action)
        return selector == "submenuAction:" ? nil : selector
    }

    private static func menuItemTitle(for item: NSMenuItem) -> String {
        if !item.title.isEmpty {
            return item.title
        }

        let attributed = item.attributedTitle?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !attributed.isEmpty {
            return attributed
        }

        if item.view != nil {
            return "(custom view)"
        }

        return ""
    }

    private static func menuItemStateName(_ state: NSControl.StateValue) -> String {
        switch state {
        case .on:
            return "on"
        case .mixed:
            return "mixed"
        default:
            return "off"
        }
    }

    private static func statusItemState(from snapshot: StatusItemRuntimeSnapshot) -> MenuBarValidationSnapshot.StatusItemState {
        return .init(
            isHovered: snapshot.isHovered,
            isPointerInsideButton: snapshot.isPointerInsideButton,
            isTitleVisible: snapshot.isTitleVisible,
            displayedTitle: snapshot.displayedTitle,
            imagePosition: snapshot.imagePosition,
            buttonFrame: snapshot.buttonFrame.map {
                .init(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
            },
            pointerLocation: snapshot.pointerLocation.map {
                .init(x: $0.x, y: $0.y)
            }
        )
    }
}
