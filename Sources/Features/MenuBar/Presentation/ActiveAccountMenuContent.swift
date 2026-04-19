import SwiftUI

struct ActiveAccountMenuContent: View {
    let account: CodexAccount
    let progressAccentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(account.name)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(menuPlanDisplayName(account.planType))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Updated \(RelativeDateTimeFormatter().localizedString(for: account.lastRemoteRefreshAt, relativeTo: .now))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(accountMetadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.top, -2)

            ActiveLimitRow(
                title: "Session",
                window: account.rateLimits?.primary,
                tintColor: progressAccentColor
            )
            ActiveLimitRow(
                title: "Weekly",
                window: account.rateLimits?.secondary,
                tintColor: progressAccentColor
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountMetadataLine: String {
        guard let email = account.email, !email.isEmpty else {
            return "No email"
        }
        return email
    }
}

struct InactiveAccountMenuContent: View {
    let account: CodexAccount
    let placement: MenuBarAccountPlacement?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(account.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(compactMenuRowUsageSummary(for: account))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let placement {
                    Text(placement.badgeText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RemoteHostMenuContent: View {
    let remoteHost: RemoteHostMenuState
    let progressAccentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(primaryTitle)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(primaryBadge)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(remoteHost.name) • \(remoteHost.connectionState.menuTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(secondaryBadge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.top, -2)

            if let activeAccount = remoteHost.activeAccount {
                ActiveLimitRow(
                    title: "Session",
                    window: activeAccount.rateLimits?.primary,
                    tintColor: progressAccentColor
                )
                ActiveLimitRow(
                    title: "Weekly",
                    window: activeAccount.rateLimits?.secondary,
                    tintColor: progressAccentColor
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryTitle: String {
        remoteHost.activeAccount?.name ?? remoteHost.name
    }

    private var primaryBadge: String {
        if let activeAccount = remoteHost.activeAccount {
            return menuPlanDisplayName(activeAccount.planType)
        }
        return remoteHost.connectionState.menuTitle
    }

    private var secondaryBadge: String {
        guard let email = remoteHost.activeAccount?.email, !email.isEmpty else {
            return remoteHost.destination
        }
        return email
    }
}

struct ActiveLimitRow: View {
    let title: String
    let window: CodexRateLimitWindow?
    let tintColor: Color

    var body: some View {
        let displayedUsedPercent = window?.displayedUsedPercent() ?? 0
        let usageText = window.map { "\($0.displayedUsedPercent())% used" } ?? "--"

        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            ProgressView(value: Double(displayedUsedPercent), total: 100)
                .tint(tintColor)
            HStack {
                Text(usageText)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Spacer()
                if let window, let resetStatus = resetStatusText(for: window) {
                    Text(resetStatus)
                        .foregroundStyle(.secondary)
                } else if window == nil {
                    Text("Unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}
