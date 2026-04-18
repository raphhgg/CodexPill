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

    struct MenuItem: Codable, Equatable {
        let title: String
        let isEnabled: Bool
        let state: String
        let hasAction: Bool
        let actionSelector: String?
        let isSeparator: Bool
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
                "Menu Bar Content: \(state.effectiveStatusBarDisplayMode.menuTitle)",
                "Menu Bar Indicator: \(state.statusBarIndicatorStyle.menuTitle)",
                "Accent Color: \(colorHexString(for: state.progressAccentColor))",
                state.statusBarMonochrome ? "Monochrome: On" : "Monochrome: Off",
                state.canShowAbout ? "About" : "About (disabled)"
            ]
        ))

        return MenuBarValidationSnapshot(
            sections: sections,
            statusMessage: state.shouldShowStatusMessage ? state.statusMessage : nil,
            currentAccount: state.activeAccount.map(accountIdentity(for:)),
            hasStatusItemContentData: state.hasStatusItemContentData,
            effectiveStatusBarDisplayMode: state.effectiveStatusBarDisplayMode.rawValue,
            statusItem: statusItemState.map(statusItemState(from:)),
            actionTrace: actionTrace,
            menuItems: menuItems(from: menu)
        )
    }

    private static func accountSections(for state: MenuBarMenuState, now: Date) -> [MenuBarValidationSnapshot.Section] {
        var sections: [MenuBarValidationSnapshot.Section] = []

        if let activeAccount = state.activeAccount {
            sections.append(.init(
                title: "Current Account",
                items: [accountSummary(for: activeAccount, now: now)]
            ))
        } else {
            sections.append(.init(title: "Current Account", items: ["No active saved account"]))
        }

        if !state.visibleInactiveAccounts.isEmpty {
            sections.append(.init(
                title: "Other Accounts",
                items: state.visibleInactiveAccounts.map { inactiveAccountSummary(for: $0, now: now) }
            ))
        }

        if !state.overflowInactiveAccounts.isEmpty {
            sections.append(.init(
                title: "More Accounts…",
                items: state.overflowInactiveAccounts.map { inactiveAccountSummary(for: $0, now: now) }
            ))
        }

        return sections
    }

    static func makeHostedValidationView(state: MenuBarMenuState, now: Date = .now) -> some View {
        let snapshot = makeSnapshot(state: state, now: now)

        return VStack(alignment: .leading, spacing: 16) {
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
        .padding(18)
        .frame(width: 360, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func accountSummary(for account: CodexAccount, now: Date) -> String {
        let plan = menuPlanDisplayName(account.planType)
        let email = account.email ?? "No email"
        let session = usageLine(title: "Session", window: account.rateLimits?.primary, now: now)
        let weekly = usageLine(title: "Weekly", window: account.rateLimits?.secondary, now: now)
        return "\(account.name) • \(plan) • \(email) • \(session) • \(weekly)"
    }

    private static func inactiveAccountSummary(for account: CodexAccount, now: Date) -> String {
        let plan = menuPlanDisplayName(account.planType)
        let session = account.rateLimits?.primary.map { "\($0.displayedUsedPercent(at: now))%" } ?? "--"
        let weekly = account.rateLimits?.secondary.map { "\($0.displayedUsedPercent(at: now))%" } ?? "--"
        return "\(account.name) • \(plan) • Session \(session) • Weekly \(weekly)"
    }

    private static func usageLine(title: String, window: CodexRateLimitWindow?, now: Date) -> String {
        let percentText = window.map { "\($0.displayedUsedPercent(at: now))% used" } ?? "--"
        guard let window, let resetsAt = window.resetsAt, resetsAt > now else {
            return "\(title): \(percentText)"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "\(title): \(percentText), Resets \(formatter.localizedString(for: resetsAt, relativeTo: now))"
    }

    private static func managementSectionItems(for state: MenuBarMenuState) -> [String] {
        [
            state.canSaveCurrentAccount ? "Save Current Account" : "Save Current Account (disabled)",
            state.canSignInAnotherAccount ? "Sign In Another Account…" : "Sign In Another Account… (disabled)",
            "Rename Account",
            "Remove Account"
        ]
    }

    private static func colorHexString(for color: NSColor) -> String {
        let normalized = (color.usingColorSpace(.deviceRGB) ?? color.usingColorSpace(.sRGB)) ?? color
        let red = Int(round(normalized.redComponent * 255))
        let green = Int(round(normalized.greenComponent * 255))
        let blue = Int(round(normalized.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func accountIdentity(for account: CodexAccount) -> MenuBarValidationSnapshot.AccountIdentity {
        MenuBarValidationSnapshot.AccountIdentity(
            name: account.name,
            email: account.email,
            planType: account.planType,
            identityDigest: identityDigest(for: account)
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
        MenuBarValidationSnapshot.MenuItem(
            title: menuItemTitle(for: item),
            isEnabled: item.isEnabled,
            state: menuItemStateName(item.state),
            hasAction: item.action != nil,
            actionSelector: item.action.map(NSStringFromSelector),
            isSeparator: item.isSeparatorItem,
            children: item.submenu.map { $0.items.map(menuItem(from:)) } ?? []
        )
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
