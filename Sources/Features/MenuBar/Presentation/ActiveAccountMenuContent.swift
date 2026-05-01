import SwiftUI

struct ActiveAccountMenuContent: View {
    let account: CodexAccount
    let locations: [String]
    let showsUpdatedTime: Bool
    let progressAccentColor: Color
    let showsPacingMarkers: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            content(now: timeline.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(account.name)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(menuPlanDisplayName(account.effectivePlanType))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(activeAccountMetadataPrefix(now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: accountMetadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.top, -2)

            ActiveLimitRow(
                title: "Session",
                window: account.rateLimits?.primary,
                tintColor: progressAccentColor,
                showsPacingMarkers: showsPacingMarkers,
                now: now
            )
            ActiveLimitRow(
                title: "Weekly",
                window: account.rateLimits?.secondary,
                tintColor: progressAccentColor,
                showsPacingMarkers: showsPacingMarkers,
                now: now
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

    private func activeAccountMetadataPrefix(now: Date) -> String {
        if locations.isEmpty {
            guard showsUpdatedTime else { return "This Mac" }
            return "Updated \(compactElapsedTime(since: account.lastRemoteRefreshAt, now: now)) ago"
        }

        return locations.joined(separator: " + ")
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

struct ActiveAccountCardDivider: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 7)
            Divider()
                .opacity(0.55)
            Spacer(minLength: 9)
        }
        .padding(.horizontal, 14)
    }
}

struct ActiveLimitRow: View {
    let title: String
    let window: CodexRateLimitWindow?
    let tintColor: Color
    let showsPacingMarkers: Bool
    let now: Date

    var body: some View {
        let displayedUsedPercent = window?.displayedUsedPercent(at: now) ?? 0
        let usageText = window.map { "\($0.displayedUsedPercent(at: now))% used" } ?? "--"
        let expectedPercent = expectedPaceMarkerPercent(
            for: window,
            showsPacingMarkers: showsPacingMarkers,
            now: now
        )

        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            ActiveLimitProgressBar(
                usedPercent: displayedUsedPercent,
                expectedPercent: expectedPercent,
                tintColor: tintColor
            )
            .frame(height: 5)
            HStack {
                Text(usageText)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Spacer()
                if let window, let resetStatus = resetStatusText(for: window, now: now) {
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

private struct ActiveLimitProgressBar: View {
    let usedPercent: Int
    let expectedPercent: Int?
    let tintColor: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progressWidth = width * clampedFraction(usedPercent)
            let markerX = expectedPercent.map { width * clampedFraction($0) }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(tintColor)
                    .frame(width: progressWidth)

                if let markerX {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.72))
                        .frame(width: 2)
                        .offset(x: min(max(markerX - 1, 0), max(width - 2, 0)))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func clampedFraction(_ percent: Int) -> Double {
        min(max(Double(percent), 0), 100) / 100
    }
}
