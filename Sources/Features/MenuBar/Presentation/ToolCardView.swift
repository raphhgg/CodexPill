import AppKit
import SwiftUI

struct ToolCardView: View {
    let section: ToolSection
    let sessionAccentColor: Color
    let weeklyAccentColor: Color
    let percentMode: UsagePercentMode
    let meterLayout: UsageMeterLayout
    let showsPacingMarkers: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if section.card.title != nil || section.card.detail != nil {
                message
            }
            reading
                .opacity(section.card.isDimmed ? 0.55 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var reading: some View {
        if !section.card.windows.isEmpty {
            UsageMeters(
                meters: UsageMeter.meters(
                    for: section.card.windows,
                    sessionTint: sessionAccentColor,
                    weeklyTint: weeklyAccentColor
                ),
                layout: meterLayout,
                percentMode: percentMode,
                showsPacingMarkers: showsPacingMarkers,
                now: now
            )
        }
        if let spend = section.card.spend {
            Text(onDemandSpendText(spend))
                .font(.caption)
                .monospacedDigit()
        }
        if let credits = section.card.resetCredits {
            ResetCreditsLine(credits: credits)
                .padding(.top, 4)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(section.provider.markAssetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text(section.provider.copy.sectionTitle)
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 6)
            if let planTag = section.planTag {
                Text(planTag)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    .fixedSize()
            }
        }
        .foregroundStyle(.secondary)
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title = section.card.title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            if let detail = section.card.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ResetCreditsLine: View {
    let credits: UsageResetCredits

    var body: some View {
        HStack(spacing: 6) {
            Text(resetCreditsCountText(credits))
            Spacer(minLength: 6)
            if let expiry = resetCreditsExpiryText(credits) {
                Text(expiry)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

func resetCreditsCountText(_ credits: UsageResetCredits) -> String {
    credits.availableCount == 1 ? "1 reset available" : "\(credits.availableCount) resets available"
}

/// "Expires 17 Oct" for one credit, "Next expires 5 Nov" for several, nil when Codex sent no expiry.
func resetCreditsExpiryText(_ credits: UsageResetCredits) -> String? {
    guard let expiry = credits.nextExpiry else { return nil }
    return credits.availableCount > 1 ? "Next expires \(shortDate(expiry))" : "Expires \(shortDate(expiry))"
}

func shortDate(_ date: Date) -> String {
    date.formatted(.dateTime.day().month(.abbreviated))
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

extension UsageProvider {
    var markAssetName: String {
        switch self {
        case .codex: "ProviderCodex"
        case .claude: "ProviderClaude"
        case .cursor: "ProviderCursor"
        }
    }
}

/// Hosts a SwiftUI card in a menu item. Items with a view get no highlight from AppKit, so this draws one while the
/// pointer is on the card and its side menu is open.
final class MenuCardItemView: NSView {
    init(_ content: some View, width: CGFloat) {
        let hostingView = NSHostingView(rootView: content.frame(width: width))
        let size = NSSize(width: width, height: max(1, hostingView.fittingSize.height))
        super.init(frame: NSRect(origin: .zero, size: size))
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard enclosingMenuItem?.isHighlighted == true else { return }
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 5, yRadius: 5).fill()
    }
}
