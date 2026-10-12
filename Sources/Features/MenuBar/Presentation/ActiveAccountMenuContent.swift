import SwiftUI

struct ActiveAccountMenuContent: View {
    let account: CodexAccount
    let locations: [String]
    let showsUpdatedTime: Bool
    let sessionAccentColor: Color
    let weeklyAccentColor: Color
    let percentMode: UsagePercentMode
    let meterLayout: UsageMeterLayout
    let showsPacingMarkers: Bool
    let tokenUsageCard: TokenUsageMenuCard?
    let now: Date

    init(
        account: CodexAccount,
        locations: [String],
        showsUpdatedTime: Bool,
        sessionAccentColor: Color,
        weeklyAccentColor: Color,
        percentMode: UsagePercentMode,
        meterLayout: UsageMeterLayout,
        showsPacingMarkers: Bool,
        tokenUsageCard: TokenUsageMenuCard? = nil,
        now: Date = .now
    ) {
        self.account = account
        self.locations = locations
        self.showsUpdatedTime = showsUpdatedTime
        self.sessionAccentColor = sessionAccentColor
        self.weeklyAccentColor = weeklyAccentColor
        self.percentMode = percentMode
        self.meterLayout = meterLayout
        self.showsPacingMarkers = showsPacingMarkers
        self.tokenUsageCard = tokenUsageCard
        self.now = now
    }

    var body: some View {
        content(now: now)
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(account.name)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                ActiveAccountPlanPill(text: menuPlanDisplayName(account.effectivePlanType))
            }

            Text(activeAccountMetadataPrefix(now: now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, -2)

            UsageMeters(
                meters: UsageMeter.codexMeters(
                    for: account.usage,
                    sessionTint: sessionAccentColor,
                    weeklyTint: weeklyAccentColor
                ),
                layout: meterLayout,
                percentMode: percentMode,
                showsPacingMarkers: showsPacingMarkers,
                now: now
            )
            .padding(.top, meterLayout == .compact ? 3 : 0)

            if let tokenUsageCard {
                ActiveAccountCardDivider()
                    .padding(.horizontal, -14)
                    .padding(.bottom, -6)
                TokenUsageMenuContent(card: tokenUsageCard)
                    .padding(.horizontal, -14)
                    .padding(.bottom, -2)
            }

        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activeAccountMetadataPrefix(now: Date) -> String {
        if locations.isEmpty {
            guard showsUpdatedTime else { return "This Mac" }
            return "Updated \(compactElapsedTime(since: account.lastRemoteRefreshAt, now: now)) ago"
        }

        return locations.joined(separator: " + ")
    }
}

private struct ActiveAccountPlanPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )
    }
}

struct ActiveAccountCardDivider: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            Divider()
                .opacity(0.55)
            Spacer(minLength: 9)
        }
        .padding(.horizontal, 14)
    }
}
