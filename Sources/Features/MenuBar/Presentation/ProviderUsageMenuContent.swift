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
            case .signingIn:
                message(title: "Finish signing in in your browser", detail: nil)
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
            if let spend = snapshot.spend {
                Text(onDemandSpendText(spend))
                    .font(.caption)
                    .monospacedDigit()
            }
        }
    }

    private func meters(for snapshot: UsageSnapshot) -> [UsageMeter] {
        switch provider {
        case .codex, .claude:
            [
                UsageMeter(title: "Session", window: snapshot.window(.session), tintColor: sessionAccentColor),
                UsageMeter(title: "Weekly", window: snapshot.window(.weekly), tintColor: weeklyAccentColor)
            ]
        case .cursor:
            snapshot.window(.billingCycle).map {
                [UsageMeter(title: "Billing cycle", window: $0, tintColor: weeklyAccentColor)]
            } ?? []
        }
    }

    private func planLabel(_ planName: String) -> String {
        planName.replacingOccurrences(of: "_", with: " ").capitalized + " plan"
    }
}

/// Spend is a dollar amount, never a percent: "On-demand: $12.34 of $50.00", or the amount alone when uncapped.
func onDemandSpendText(_ spend: UsageSpend, locale: Locale = .current) -> String {
    let currency = Decimal.FormatStyle.Currency(code: "USD", locale: locale)
    let used = spend.usedUSD.formatted(currency)
    guard let limit = spend.limitUSD else { return "On-demand: \(used)" }
    return "On-demand: \(used) of \(limit.formatted(currency))"
}

extension UsageProvider {
    var menuTitle: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .cursor: "Cursor"
        }
    }

    fileprivate func unavailableMessage(for reason: UsageUnavailableReason) -> (title: String, detail: String?) {
        switch reason {
        case .notInstalled:
            ("\(menuTitle) isn't installed", nil)
        case .signedOut where self == .claude, .signInExpired:
            ("Sign in to \(menuTitle) again", nil)
        case .signedOut:
            ("Not signed in to \(menuTitle)", "Sign in to \(menuTitle) to see usage.")
        case .keychainAccessNeeded:
            ("Allow Keychain access", nil)
        case .readFailed:
            readFailedMessage
        }
    }

    private var readFailedMessage: (title: String, detail: String) {
        switch self {
        case .claude: ("Can't reach Anthropic", "Retrying in a few minutes.")
        case .cursor: ("Can't reach cursor.com", "Retrying in a few minutes.")
        case .codex: ("Can't read \(menuTitle) usage", "Retrying soon.")
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
