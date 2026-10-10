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
                let text = provider.awaitingUsageMessage
                message(title: text.title, detail: text.detail)
            case let .unavailable(reason, lastSnapshot):
                let text = provider.unavailableMessage(for: reason)
                message(title: text.title, detail: text.detail)
                if let lastSnapshot {
                    meters(for: lastSnapshot, freshness: "As of \(usageAsOfText(lastSnapshot.fetchedAt, now: now))")
                        .opacity(0.55)
                }
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

    private func message(title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func meters(for snapshot: UsageSnapshot, freshness: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text([snapshot.planName.map(planLabel), freshness].compactMap(\.self).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            UsageMeters(
                meters: meters(for: snapshot),
                layout: meterLayout,
                percentMode: percentMode,
                showsPacingMarkers: showsPacingMarkers,
                now: now
            )
            .padding(.top, meterLayout == .compact ? 3 : 0)
        }
    }

    private func meters(for snapshot: UsageSnapshot) -> [UsageMeter] {
        switch provider {
        case .codex, .claude:
            UsageMeter.codexMeters(for: snapshot, sessionTint: sessionAccentColor, weeklyTint: weeklyAccentColor)
        case .cursor:
            []
        }
    }

    private func planLabel(_ planName: String) -> String {
        planName.replacingOccurrences(of: "_", with: " ").capitalized + " plan"
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

    func unavailableMessage(for reason: UsageUnavailableReason) -> (title: String, detail: String?) {
        let retrying = "Retrying in a few minutes."
        return switch reason {
        case .signedOut: ("Not signed in to \(menuTitle)", "Sign in to \(menuTitle) to see usage.")
        case .signInExpired: ("\(menuTitle) sign-in expired", "Open \(menuTitle) to renew it.")
        case .keychainAccessNeeded: ("Allow Keychain access", nil)
        case .signInUnreadable: ("Can't read the \(menuTitle) sign-in", "Sign in to \(menuTitle) again.")
        case .accessDenied: ("\(serviceName) won't share usage", "Sign in to \(menuTitle) again.")
        case .rateLimited: ("\(serviceName) asked to wait", retrying)
        case .unreachable: ("Can't reach \(serviceName)", retrying)
        case .serviceError: ("\(serviceName) is having trouble", retrying)
        case .unexpectedResponse: ("Unexpected reply from \(serviceName)", retrying)
        }
    }

    /// Who answers the usage request.
    private var serviceName: String {
        switch self {
        case .claude: "Anthropic"
        case .codex, .cursor: menuTitle
        }
    }

    fileprivate var awaitingUsageMessage: (title: String, detail: String?) {
        switch self {
        case .claude: ("Waiting for Claude usage", nil)
        case .codex, .cursor: ("Waiting for \(menuTitle)", "Usage appears after the next update.")
        }
    }
}

/// The time alone for today, otherwise the date and time.
func usageAsOfText(_ date: Date, now: Date) -> String {
    let isToday = Calendar.current.isDate(date, inSameDayAs: now)
    return date.formatted(date: isToday ? .omitted : .abbreviated, time: .shortened)
}
