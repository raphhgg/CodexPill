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

        let currentAccountItems: [String]
        if let activeAccount = state.activeAccount {
            currentAccountItems = [
                accountSummary(for: activeAccount, now: now)
            ]
        } else {
            currentAccountItems = ["No active saved account"]
        }
        sections.append(.init(title: "Current Account", items: currentAccountItems))

        if !state.visibleInactiveAccounts.isEmpty {
            sections.append(.init(
                title: "Other Accounts",
                items: state.visibleInactiveAccounts.map { accountSummary(for: $0, now: now) }
            ))
        }

        if !state.overflowInactiveAccounts.isEmpty {
            sections.append(.init(
                title: "More Accounts",
                items: state.overflowInactiveAccounts.map { accountSummary(for: $0, now: now) }
            ))
        }

        sections.append(.init(
            title: "Accounts",
            items: [
                state.canSaveCurrentAccount ? "Save Current Account" : "Save Current Account (disabled)",
                state.canSignInAnotherAccount ? "Sign In Another Account…" : "Sign In Another Account… (disabled)",
                "Rename Account",
                "Remove Account",
                "Visible Other Accounts: \(state.visibleInactiveAccountCount == 0 ? "All" : "\(state.visibleInactiveAccountCount)")"
            ]
        ))

        sections.append(.init(
            title: "Preferences",
            items: [
                "Refresh Time: \(state.refreshIntervalMinutes) minutes",
                "Status Bar Style: \(state.statusBarIndicatorStyle.menuTitle)",
                state.statusBarMonochrome ? "Monochrome: On" : "Monochrome: Off",
                state.canShowAbout ? "About" : "About (disabled)"
            ]
        ))

        return MenuBarValidationSnapshot(
            sections: sections,
            statusMessage: state.shouldShowStatusMessage ? state.statusMessage : nil
        )
    }

    static func makeHostedValidationView(state: MenuBarMenuState, now: Date = .now) -> some View {
        let snapshot = makeSnapshot(state: state, now: now)

        return VStack(alignment: .leading, spacing: 16) {
            ForEach(snapshot.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(section.items, id: \.self) { item in
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
        let plan = account.planType?.capitalized ?? "Unknown"
        let email = account.email ?? "No email"
        let session = usageLine(title: "Session", window: account.rateLimits?.primary, now: now)
        let weekly = usageLine(title: "Weekly", window: account.rateLimits?.secondary, now: now)
        return "\(account.name) • \(plan) • \(email) • \(session) • \(weekly)"
    }

    private static func usageLine(title: String, window: CodexRateLimitWindow?, now: Date) -> String {
        let percentText = window.map { "\($0.displayedUsedPercent(at: now))% used" } ?? "--"
        guard let window, let resetsAt = window.resetsAt, resetsAt > now else {
            return "\(title): \(percentText)"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "\(title): \(percentText), resets \(formatter.localizedString(for: resetsAt, relativeTo: now))"
    }
}
