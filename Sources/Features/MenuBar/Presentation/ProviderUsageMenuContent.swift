import SwiftUI

/// Read-only usage for a provider other than Codex. It has no switching actions.
struct ProviderUsageMenuContent: View {
    let provider: UsageProvider
    let status: ProviderUsageStatus
    let sessionAccentColor: Color
    let weeklyAccentColor: Color
    let percentMode: UsagePercentMode
    let meterLayout: UsageMeterLayout
    let showsPacingMarkers: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch status {
            case .notConnected:
                EmptyView()
            case .awaitingUsage:
                message(
                    title: "Waiting for \(provider.menuTitle)",
                    detail: provider.awaitingUsageDetail
                )
            case .unavailable:
                message(
                    title: "Can't read \(provider.menuTitle) usage",
                    detail: "Retrying soon."
                )
            case let .current(snapshot):
                meters(for: snapshot, freshness: "As of \(usageAsOfText(snapshot.fetchedAt, now: now))")
            case let .stale(snapshot):
                meters(for: snapshot, freshness: "As of \(usageAsOfText(snapshot.fetchedAt, now: now))")
                    .opacity(0.55)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func meters(for snapshot: UsageSnapshot, freshness: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(freshness)
                .font(.caption)
                .foregroundStyle(.secondary)
            UsageMeters(
                meters: [
                    UsageMeter(title: "Session", window: snapshot.window(.session), tintColor: sessionAccentColor),
                    UsageMeter(title: "Weekly", window: snapshot.window(.weekly), tintColor: weeklyAccentColor)
                ],
                layout: meterLayout,
                percentMode: percentMode,
                showsPacingMarkers: showsPacingMarkers,
                now: now
            )
            .padding(.top, meterLayout == .compact ? 3 : 0)
        }
    }
}

extension UsageProvider {
    var menuTitle: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .cursor: "Cursor"
        }
    }

    fileprivate var awaitingUsageDetail: String {
        switch self {
        case .claude: "Send a message in Claude Code to see usage."
        case .codex, .cursor: "Usage appears after the next update."
        }
    }
}

/// The time alone for today, otherwise the date and time.
func usageAsOfText(_ date: Date, now: Date) -> String {
    let isToday = Calendar.current.isDate(date, inSameDayAs: now)
    return date.formatted(date: isToday ? .omitted : .abbreviated, time: .shortened)
}
