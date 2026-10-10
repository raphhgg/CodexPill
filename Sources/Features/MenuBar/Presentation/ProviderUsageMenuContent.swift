import SwiftUI

/// Usage for one tool other than Codex: its meters, or the message for why it has none.
struct ProviderUsageMenuContent: View {
    let copy: ProviderCopy
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
                message(title: "Waiting for \(copy.name) usage", detail: nil)
            case let .unavailable(reason, lastSnapshot):
                let text = copy.unavailableMessage(for: reason)
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
                meters: UsageMeter.meters(for: snapshot, sessionTint: sessionAccentColor, weeklyTint: weeklyAccentColor),
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

/// The time alone for today, otherwise the date and time.
func usageAsOfText(_ date: Date, now: Date) -> String {
    let isToday = Calendar.current.isDate(date, inSameDayAs: now)
    return date.formatted(date: isToday ? .omitted : .abbreviated, time: .shortened)
}
