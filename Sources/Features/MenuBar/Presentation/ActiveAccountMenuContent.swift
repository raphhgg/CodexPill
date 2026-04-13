import SwiftUI

struct ActiveAccountMenuContent: View {
    let account: CodexAccount

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

            ActiveLimitRow(title: "Session", window: account.rateLimits?.primary)
            ActiveLimitRow(title: "Weekly", window: account.rateLimits?.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(width: 340, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var accountMetadataLine: String {
        guard let email = account.email, !email.isEmpty else {
            return "No email"
        }
        return email
    }
}

private struct ActiveLimitRow: View {
    let title: String
    let window: CodexRateLimitWindow?

    var body: some View {
        let displayedUsedPercent = window?.displayedUsedPercent() ?? 0
        let usageText = window.map { "\($0.displayedUsedPercent())% used" } ?? "--"

        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            ProgressView(value: Double(displayedUsedPercent), total: 100)
                .tint(.accentColor)
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
