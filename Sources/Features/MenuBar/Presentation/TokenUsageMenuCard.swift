import Foundation

struct TokenUsageDayBucket: Equatable, Identifiable {
    let id: Int
    let shortLabel: String
    let tokenCount: Int
    /// Each tool's share of the day, in tool order. Empty when only one tool's buckets are known.
    var segments: [TokenUsageBarSegment] = []
}

struct TokenUsageBarSegment: Equatable {
    let tool: TokenUsageTool
    let tokenCount: Int
}

/// One tool's line under the chart: today, the period, and its largest models.
struct TokenUsageToolSummary: Equatable, Identifiable {
    struct ModelShare: Equatable {
        let model: String
        let tokenCount: Int
        let percent: Int
    }

    static let maximumModelCount = 3

    let tool: TokenUsageTool
    let todayTokenCount: Int
    let periodTokenCount: Int
    let models: [ModelShare]
    let isUnavailable: Bool

    var id: TokenUsageTool { tool }

    var modelsSummary: String? {
        guard !models.isEmpty else { return nil }
        return models.map { "\($0.model) \($0.percent > 0 ? "\($0.percent)" : "<1")%" }.joined(separator: " · ")
    }

    static func make(from series: ToolTokenUsageSeries, today: Date?) -> TokenUsageToolSummary {
        let total = series.totalTokens
        let modelTotals = series.modelTotals
        let models = modelTotals.prefix(maximumModelCount).map { entry in
            let rounded = total > 0 ? Int((Double(entry.tokens) * 100 / Double(total)).rounded()) : 0
            // A share never reads 100% while another model has tokens.
            return ModelShare(
                model: entry.model,
                tokenCount: entry.tokens,
                percent: modelTotals.count > 1 ? min(rounded, 99) : rounded
            )
        }
        return TokenUsageToolSummary(
            tool: series.tool,
            todayTokenCount: today.map { series.tokens(on: $0) } ?? 0,
            periodTokenCount: total,
            models: models,
            isUnavailable: false
        )
    }

    static func unavailable(_ tool: TokenUsageTool) -> TokenUsageToolSummary {
        TokenUsageToolSummary(tool: tool, todayTokenCount: 0, periodTokenCount: 0, models: [], isUnavailable: true)
    }
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
    var toolSummaries: [TokenUsageToolSummary] = []

    var id: TokenUsageChartStyle { style }

    /// Stacked bars and per-tool lines appear once any tool other than Codex is connected.
    var showsTools: Bool {
        toolSummaries.contains { $0.tool != .codex }
    }

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
                if showsTools {
                    for summary in toolSummaries {
                        parts.append(summary.isUnavailable
                            ? "\(summary.tool.displayName): usage unavailable"
                            : "\(summary.tool.displayName): \(formattedTokenCount(summary.periodTokenCount)) tokens")
                    }
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
        var buckets: [TokenUsageDayBucket]
        var allTimePeakBucket: TokenUsageDayBucket? = nil
        let allTimePeakProgress: TokenUsageScanProgress?
        var toolSummaries: [TokenUsageToolSummary] = []
        switch loadState {
        case .loaded(let data) where !data.tools.isEmpty:
            buckets = toolBuckets(from: data.tools, period: period, calendar: calendar)
            let today = data.tools.first?.days.last?.day
            toolSummaries = data.tools.map { TokenUsageToolSummary.make(from: $0, today: today) }
                + data.unavailableTools.map(TokenUsageToolSummary.unavailable)
            let combinedPeak = buckets.max { $0.tokenCount < $1.tokenCount }
            if let allTimePeak = data.allTimePeak {
                allTimePeakBucket = TokenUsageDayBucket(
                    id: -1,
                    shortLabel: Self.shortLabel(for: allTimePeak.day, calendar: calendar),
                    tokenCount: allTimePeak.usage.totalTokens
                )
            }
            // Codex's all-time peak counts only Codex, so a busier combined day in this period wins.
            if let combinedPeak, combinedPeak.tokenCount > (allTimePeakBucket?.tokenCount ?? 0) {
                allTimePeakBucket = combinedPeak
            }
            allTimePeakProgress = data.allTimePeakProgress
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
            loadState: loadState,
            toolSummaries: toolSummaries
        )
    }

    private static func toolBuckets(
        from tools: [ToolTokenUsageSeries],
        period: CodexTokenUsagePeriod,
        calendar: Calendar
    ) -> [TokenUsageDayBucket] {
        guard let days = tools.first?.days.suffix(period.dayCount).map(\.day) else { return [] }
        return days.enumerated().map { index, day in
            let segments = tools.map { TokenUsageBarSegment(tool: $0.tool, tokenCount: $0.tokens(on: day)) }
            return TokenUsageDayBucket(
                id: index,
                shortLabel: shortLabel(for: day, calendar: calendar),
                tokenCount: segments.reduce(0) { $0 + $1.tokenCount },
                segments: segments
            )
        }
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

/// Like `formattedTokenCount`, but thousands read as `K` so per-tool columns stay narrow.
func formattedShortTokenCount(_ tokenCount: Int) -> String {
    guard tokenCount >= 1_000, tokenCount < 1_000_000 else {
        return formattedTokenCount(tokenCount)
    }
    return formattedCompactTokenCount(tokenCount, divisor: 1_000, suffix: "K")
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
