import Foundation

struct TokenUsageDayBucket: Equatable, Identifiable {
    let id: Int
    let shortLabel: String
    let tokenCount: Int
}

struct TokenUsageMenuCard: Equatable, Identifiable {
    let style: TokenUsageChartStyle
    let loadingAnimationStyle: TokenUsageLoadingAnimationStyle
    let period: CodexTokenUsagePeriod
    let buckets: [TokenUsageDayBucket]
    let allTimePeakBucket: TokenUsageDayBucket?
    let allTimePeakProgress: TokenUsageScanProgress?
    let peakScope: TokenUsagePeakScope
    let loadState: TokenUsageMenuLoadState

    var id: TokenUsageChartStyle { style }

    var periodTitle: String {
        period.summaryTitle
    }

    var todayTokenCount: Int {
        buckets.last?.tokenCount ?? 0
    }

    var periodTotalTokenCount: Int {
        buckets.reduce(0) { $0 + $1.tokenCount }
    }

    var peakDayBucket: TokenUsageDayBucket? {
        buckets.max { $0.tokenCount < $1.tokenCount }
    }

    var peakDaySummary: String? {
        let bucket = displayedPeakBucket
        if let bucket, bucket.tokenCount > 0 {
            return "\(bucket.shortLabel): \(formattedTokenCount(bucket.tokenCount)) tokens"
        }
        guard peakScope == .allTime, let allTimePeakProgress else { return nil }
        return allTimePeakProgress.message
    }

    var peakDayTitle: String {
        peakScope.cardTitle
    }

    private var displayedPeakBucket: TokenUsageDayBucket? {
        switch peakScope {
        case .currentPeriod:
            return peakDayBucket
        case .allTime:
            return allTimePeakBucket
        }
    }

    var hasData: Bool {
        periodTotalTokenCount > 0
    }

    var accessibilitySummary: String {
        var parts = [
            "Token Usage",
            periodTitle
        ]

        switch loadState {
        case .loading(let progress):
            parts.append(progress?.message.appending("...") ?? "Scanning local sessions...")
        case .unavailable:
            parts.append("Token usage unavailable")
        case .loaded:
            if hasData {
                parts.append("Today: \(formattedTokenCount(todayTokenCount)) tokens")
                parts.append("\(periodTitle): \(formattedTokenCount(periodTotalTokenCount)) tokens")
                if let peakDaySummary {
                    parts.append("\(peakDayTitle): \(peakDaySummary)")
                }
            } else {
                parts.append("No token usage found yet")
            }
        }

        return parts.joined(separator: " • ")
    }

    static func make(
        style: TokenUsageChartStyle,
        loadingAnimationStyle: TokenUsageLoadingAnimationStyle = .waves,
        peakScope: TokenUsagePeakScope = .currentPeriod,
        period: CodexTokenUsagePeriod,
        loadState: TokenUsageMenuLoadState,
        calendar: Calendar = .current
    ) -> TokenUsageMenuCard {
        let buckets: [TokenUsageDayBucket]
        let allTimePeakBucket: TokenUsageDayBucket?
        let allTimePeakProgress: TokenUsageScanProgress?
        switch loadState {
        case .loaded(let data):
            let dailyUsage = data.buckets
            let visibleDailyUsage = dailyUsage.suffix(period.dayCount)
            buckets = visibleDailyUsage.enumerated().map { index, usage in
                TokenUsageDayBucket(
                    id: index,
                    shortLabel: Self.shortLabel(for: usage.day, calendar: calendar),
                    tokenCount: usage.usage.totalTokens
                )
            }
            if let allTimePeak = data.allTimePeak {
                allTimePeakBucket = TokenUsageDayBucket(
                    id: -1,
                    shortLabel: Self.shortLabel(for: allTimePeak.day, calendar: calendar),
                    tokenCount: allTimePeak.usage.totalTokens
                )
            } else {
                allTimePeakBucket = nil
            }
            allTimePeakProgress = data.allTimePeakProgress
        case .loading(_), .unavailable:
            buckets = []
            allTimePeakBucket = nil
            allTimePeakProgress = nil
        }

        return TokenUsageMenuCard(
            style: style,
            loadingAnimationStyle: loadingAnimationStyle,
            period: period,
            buckets: buckets,
            allTimePeakBucket: allTimePeakBucket,
            allTimePeakProgress: allTimePeakProgress,
            peakScope: peakScope,
            loadState: loadState
        )
    }

    private static func shortLabel(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}

struct TokenUsageLoadingFrame: Equatable {
    let message: String
    let highlightedIndex: Int
    let phase: Double

    static func make(
        at date: Date,
        itemCount: Int,
        reduceMotion: Bool = false,
        baseMessage: String = "Scanning local sessions"
    ) -> TokenUsageLoadingFrame {
        let safeItemCount = max(itemCount, 1)
        guard !reduceMotion else {
            return TokenUsageLoadingFrame(
                message: baseMessage + "...",
                highlightedIndex: 0,
                phase: 0
            )
        }

        let tick = max(Int((date.timeIntervalSince1970 * 2).rounded(.down)), 0)
        let dotCount = (tick % 3) + 1
        return TokenUsageLoadingFrame(
            message: baseMessage + String(repeating: ".", count: dotCount),
            highlightedIndex: tick % safeItemCount,
            phase: date.timeIntervalSince1970
        )
    }
}

func formattedTokenCount(_ tokenCount: Int) -> String {
    if tokenCount >= 1_000_000_000 {
        return formattedCompactTokenCount(tokenCount, divisor: 1_000_000_000, suffix: "B")
    }

    if tokenCount >= 1_000_000 {
        return formattedCompactTokenCount(tokenCount, divisor: 1_000_000, suffix: "M")
    }

    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    return formatter.string(from: NSNumber(value: tokenCount)) ?? "\(tokenCount)"
}

private func formattedCompactTokenCount(_ tokenCount: Int, divisor: Double, suffix: String) -> String {
    let value = Double(tokenCount) / divisor
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    return "\(formatter.string(from: NSNumber(value: value)) ?? "\(value)")\(suffix)"
}
