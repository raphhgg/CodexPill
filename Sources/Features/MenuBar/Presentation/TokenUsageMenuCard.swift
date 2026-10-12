import Foundation
import Observation

/// What the Token Usage card shows: each connected tool's tokens per day for the period, by model.
struct TokenUsageMenuCard: Equatable {
    enum Phase: Equatable {
        case loaded
        /// Codex is still reading sessions. Other tools are already final.
        case reading(fraction: Double?)
        case unavailable
    }

    struct ToolSummary: Equatable, Identifiable {
        let tool: TokenUsageTool
        let todayTokenCount: Int
        let periodTokenCount: Int
        /// The top models plus `Other`, as shares of this tool's tokens.
        let models: [ModelShare]
        let isUnavailable: Bool
        let isReading: Bool

        var id: TokenUsageTool { tool }
    }

    struct ModelShare: Equatable {
        let name: String
        let share: Double
    }

    struct TopModel: Equatable {
        let tool: TokenUsageTool
        let name: String
        let tokenCount: Int
    }

    static let modelsPerTool = 2
    static let topModelCount = 5

    let phase: Phase
    let period: CodexTokenUsagePeriod
    let days: [Date]
    let dayLabels: [String]
    /// Connected tools in a fixed order, each with one entry per day.
    let tools: [ToolTokenUsageSeries]
    let unavailableTools: [TokenUsageTool]
    /// While Codex reads, its days on or before this one are not final.
    let codexPendingDay: Date?

    var periodTokenCount: Int { tools.reduce(0) { $0 + $1.totalTokens } }

    var todayTokenCount: Int { days.indices.last.map(tokenCount(onDay:)) ?? 0 }

    var hasData: Bool { periodTokenCount > 0 || isReading }

    var isReading: Bool {
        if case .reading = phase { return true }
        return false
    }

    var readingFraction: Double? {
        if case .reading(let fraction) = phase { return fraction }
        return nil
    }

    func tokenCount(onDay index: Int) -> Int {
        tools.reduce(0) { $0 + tokenCount(for: $1.tool, onDay: index) }
    }

    func tokenCount(for tool: TokenUsageTool, onDay index: Int) -> Int {
        guard let series = tools.first(where: { $0.tool == tool }), series.days.indices.contains(index) else { return 0 }
        return series.days[index].totalTokens
    }

    /// Codex days the scan hasn't finished yet.
    func isPending(_ tool: TokenUsageTool, onDay index: Int) -> Bool {
        guard tool == .codex, let codexPendingDay, days.indices.contains(index) else { return false }
        return days[index] <= codexPendingDay
    }

    var maximumDayTokenCount: Int {
        max(days.indices.map(tokenCount(onDay:)).max() ?? 0, 1)
    }

    func maximumDayTokenCount(for tool: TokenUsageTool) -> Int {
        max(tools.first { $0.tool == tool }?.days.map(\.totalTokens).max() ?? 0, 1)
    }

    var subtitle: String {
        if let readingFraction {
            return "\(period.summaryTitle) · Reading Codex sessions · \(Int((readingFraction * 100).rounded()))%"
        }
        return "\(period.summaryTitle) · \(formattedShortTokenCount(periodTokenCount)) · Today \(formattedShortTokenCount(todayTokenCount))"
    }

    var toolSummaries: [ToolSummary] {
        let ready = tools.map { series in
            let reading = isReading && series.tool == .codex
            return ToolSummary(
                tool: series.tool,
                todayTokenCount: days.indices.last.map { tokenCount(for: series.tool, onDay: $0) } ?? 0,
                periodTokenCount: series.totalTokens,
                models: reading ? [] : Self.modelShares(of: series),
                isUnavailable: false,
                isReading: reading
            )
        }
        let unavailable = unavailableTools.map {
            ToolSummary(tool: $0, todayTokenCount: 0, periodTokenCount: 0, models: [], isUnavailable: true, isReading: false)
        }
        return (ready + unavailable).sorted { $0.tool.order < $1.tool.order }
    }

    /// Each tool's share of the period. Nil while Codex is still reading, because the total isn't final.
    func share(of tool: TokenUsageTool) -> Double? {
        guard !isReading, periodTokenCount > 0 else { return nil }
        return Double(tools.first { $0.tool == tool }?.totalTokens ?? 0) / Double(periodTokenCount)
    }

    /// The largest models across tools. Codex models wait until its scan finishes.
    var topModels: [TopModel] {
        var models: [TopModel] = []
        for series in tools where !(isReading && series.tool == .codex) {
            for entry in series.modelTotals {
                models.append(TopModel(tool: series.tool, name: ModelDisplayName.make(entry.model), tokenCount: entry.tokens))
            }
        }
        models.sort { lhs, rhs in
            lhs.tokenCount == rhs.tokenCount ? lhs.name < rhs.name : lhs.tokenCount > rhs.tokenCount
        }
        let limit = isReading ? Self.topModelCount - 1 : Self.topModelCount
        return Array(models.prefix(limit))
    }

    func tooltip(forDay index: Int) -> String {
        guard dayLabels.indices.contains(index) else { return "" }
        let parts = tools.map { series in
            isPending(series.tool, onDay: index)
                ? "\(series.tool.displayName) …"
                : "\(series.tool.displayName) \(formattedShortTokenCount(tokenCount(for: series.tool, onDay: index)))"
        }
        return "\(dayLabels[index]): \(formattedShortTokenCount(tokenCount(onDay: index))) tokens\n" + parts.joined(separator: " · ")
    }

    var accessibilitySummary: String {
        var parts = ["Token Usage", period.summaryTitle]
        switch phase {
        case .unavailable:
            parts.append("Token usage unavailable")
        case .reading, .loaded:
            parts.append(subtitle)
            for summary in toolSummaries {
                if summary.isUnavailable {
                    parts.append("\(summary.tool.displayName) unavailable")
                } else if summary.isReading {
                    parts.append("\(summary.tool.displayName) reading sessions")
                } else {
                    let models = summary.models.map { "\($0.name) \(Self.percent($0.share))" }.joined(separator: ", ")
                    parts.append("\(summary.tool.displayName) \(formattedShortTokenCount(summary.periodTokenCount)) tokens, \(models)")
                }
            }
        }
        return parts.joined(separator: " • ")
    }

    static func percent(_ share: Double) -> String {
        let value = Int((share * 100).rounded())
        if value == 0, share > 0 { return "<1%" }
        return "\(value)%"
    }

    static func modelShares(of series: ToolTokenUsageSeries) -> [ModelShare] {
        let total = Double(series.totalTokens)
        guard total > 0 else { return [] }
        let models = series.modelTotals
        var shares = models.prefix(modelsPerTool).map {
            ModelShare(name: ModelDisplayName.make($0.model), share: Double($0.tokens) / total)
        }
        let rest = models.dropFirst(modelsPerTool).reduce(0) { $0 + $1.tokens }
        if rest > 0 {
            shares.append(ModelShare(name: "Other", share: Double(rest) / total))
        }
        return shares
    }

    static func make(
        period: CodexTokenUsagePeriod,
        loadState: TokenUsageMenuLoadState,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> TokenUsageMenuCard {
        let interval = ToolTokenUsageDays.interval(dayCount: period.dayCount, endingAt: now, calendar: calendar)
        let days = ToolTokenUsageDays.filled([], in: interval, calendar: calendar).map(\.day)
        let phase: Phase
        var tools: [ToolTokenUsageSeries] = []
        var unavailableTools: [TokenUsageTool] = []
        var pendingDay: Date?

        switch loadState {
        case .loaded(let data):
            phase = .loaded
            tools = data.tools.isEmpty
                ? [AllToolsTokenUsageMenuProvider.codexSeries(from: data.buckets, in: interval, calendar: calendar)]
                : data.tools
            unavailableTools = data.unavailableTools
        case .loading(let progress):
            phase = .reading(fraction: progress?.fraction)
            // Before the first update, every Codex day is still pending.
            pendingDay = progress.map { $0.pendingDay } ?? days.last
            tools = [AllToolsTokenUsageMenuProvider.codexSeries(from: progress?.codexDays ?? [], in: interval, calendar: calendar)]
                + (progress?.otherTools ?? [])
            unavailableTools = progress?.unavailableTools ?? []
        case .unavailable:
            phase = .unavailable
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMM d")

        return TokenUsageMenuCard(
            phase: phase,
            period: period,
            days: days,
            dayLabels: days.map(formatter.string(from:)),
            tools: tools
                .map { ToolTokenUsageSeries(tool: $0.tool, days: ToolTokenUsageDays.filled($0.days, in: interval, calendar: calendar)) }
                .sorted { $0.tool.order < $1.tool.order },
            unavailableTools: unavailableTools,
            codexPendingDay: pendingDay
        )
    }
}

/// The card's live model: the coordinator replaces `card` as data arrives, so an open menu updates in place,
/// and the toggles write straight to the preferences.
@MainActor
@Observable
final class TokenUsageCardModel {
    var card: TokenUsageMenuCard
    let preferences: TokenUsagePreferencesStore

    init(card: TokenUsageMenuCard, preferences: TokenUsagePreferencesStore) {
        self.card = card
        self.preferences = preferences
    }
}

extension TokenUsageTool {
    var order: Int {
        switch self {
        case .codex: 0
        case .claudeCode: 1
        case .cursor: 2
        }
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
