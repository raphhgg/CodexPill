import SwiftUI

struct MenuBarValidationSnapshot: Codable, Equatable {
    struct Section: Codable, Equatable {
        let title: String
        let items: [String]
    }

    let sections: [Section]
    let statusMessage: String?
}

@MainActor
enum MenuBarValidationSupport {
    static func makeSnapshot(state: MenuBarMenuState, now: Date = .now) -> MenuBarValidationSnapshot {
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
                "Status Item Content: \(state.statusBarDisplayMode.menuTitle)",
                "Status Item Appearance: \(state.statusBarIndicatorStyle.menuTitle)",
                state.statusBarMonochrome ? "Monochrome: On" : "Monochrome: Off",
                state.canShowAbout ? "About" : "About (disabled)"
            ]
        ))

        return MenuBarValidationSnapshot(
            sections: sections,
            statusMessage: state.shouldShowStatusMessage ? state.statusMessage : nil
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
                title: "More Accounts",
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
        let session = account.rateLimits?.primary?.displayedUsedPercent(at: now) ?? 100
        let weekly = account.rateLimits?.secondary?.displayedUsedPercent(at: now) ?? 100
        return "\(account.name) • \(plan) • Session \(session)% • Weekly \(weekly)%"
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
}
