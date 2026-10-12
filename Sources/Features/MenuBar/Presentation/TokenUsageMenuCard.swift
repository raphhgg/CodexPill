import Foundation
import Observation

/// What the Token Usage card shows: each connected tool's tokens per day for the period, by model.
struct TokenUsageMenuCard: Equatable {
    enum Phase: Equatable {
        case loaded
        /// Reading sessions. The chart shows the last finished reading, dimmed, or placeholder bars before the first.
        case loading(fraction: Double)
        case unavailable
    }

    struct ToolSummary: Equatable, Identifiable {
        let tool: TokenUsageTool
        let todayTokenCount: Int
        let periodTokenCount: Int
        /// The top models plus `Other`, as shares of this tool's tokens.
        let models: [ModelShare]
        let isUnavailable: Bool

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

    var periodTokenCount: Int { tools.reduce(0) { $0 + $1.totalTokens } }

    var todayTokenCount: Int { days.indices.last.map(tokenCount(onDay:)) ?? 0 }

    var hasData: Bool { periodTokenCount > 0 || isLoading }

    var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    /// Loading with no earlier reading to show.
    var showsPlaceholderChart: Bool { isLoading && periodTokenCount == 0 }

    /// The splits and their switch show only once a reading has finished.
    var showsSplits: Bool { phase == .loaded && periodTokenCount > 0 }

    func tokenCount(onDay index: Int) -> Int {
        tools.reduce(0) { $0 + tokenCount(for: $1.tool, onDay: index) }
    }

    func tokenCount(for tool: TokenUsageTool, onDay index: Int) -> Int {
        guard let series = tools.first(where: { $0.tool == tool }), series.days.indices.contains(index) else { return 0 }
        return series.days[index].totalTokens
    }

    var maximumDayTokenCount: Int {
        max(days.indices.map(tokenCount(onDay:)).max() ?? 0, 1)
    }

    func maximumDayTokenCount(for tool: TokenUsageTool) -> Int {
        max(tools.first { $0.tool == tool }?.days.map(\.totalTokens).max() ?? 0, 1)
    }

    var subtitle: String {
        if case .loading(let fraction) = phase {
            return "\(period.summaryTitle) · Loading \(Int((fraction * 100).rounded()))%"
        }
        return "\(period.summaryTitle) · \(formattedShortTokenCount(periodTokenCount)) · Today \(formattedShortTokenCount(todayTokenCount))"
    }

    var toolSummaries: [ToolSummary] {
        let ready = tools.map { series in
            ToolSummary(
                tool: series.tool,
                todayTokenCount: days.indices.last.map { tokenCount(for: series.tool, onDay: $0) } ?? 0,
                periodTokenCount: series.totalTokens,
                models: Self.modelShares(of: series),
                isUnavailable: false
            )
        }
        let unavailable = unavailableTools.map {
            ToolSummary(tool: $0, todayTokenCount: 0, periodTokenCount: 0, models: [], isUnavailable: true)
        }
        return (ready + unavailable).sorted { $0.tool.order < $1.tool.order }
    }

    func share(of tool: TokenUsageTool) -> Double? {
        guard periodTokenCount > 0 else { return nil }
        return Double(tools.first { $0.tool == tool }?.totalTokens ?? 0) / Double(periodTokenCount)
    }

    var topModels: [TopModel] {
        var models: [TopModel] = []
        for series in tools {
            for entry in series.modelTotals {
                models.append(TopModel(tool: series.tool, name: ModelDisplayName.make(entry.model), tokenCount: entry.tokens))
            }
        }
        models.sort { lhs, rhs in
            lhs.tokenCount == rhs.tokenCount ? lhs.name < rhs.name : lhs.tokenCount > rhs.tokenCount
        }
        return Array(models.prefix(Self.topModelCount))
    }

    /// The same tools, each with the most the splits can show, so the card keeps one height while loading and after.
    var layoutTemplate: TokenUsageMenuCard {
        let toolSet = tools.map(\.tool) + unavailableTools
        let day = days.last ?? Date(timeIntervalSinceReferenceDate: 0)
        let models = Dictionary(uniqueKeysWithValues: (1...Self.topModelCount).map { ("model \($0)", $0) })
        return TokenUsageMenuCard(
            phase: .loaded,
            period: period,
            days: [day],
            dayLabels: [""],
            tools: (toolSet.isEmpty ? [.codex] : toolSet).map {
                ToolTokenUsageSeries(tool: $0, days: [ToolDailyTokenUsage(day: day, tokensByModel: models)])
            },
            unavailableTools: []
        )
    }

    func tooltip(forDay index: Int) -> String {
        guard dayLabels.indices.contains(index) else { return "" }
        let parts = tools.map { "\($0.tool.displayName) \(formattedShortTokenCount(tokenCount(for: $0.tool, onDay: index)))" }
        return "\(dayLabels[index]): \(formattedShortTokenCount(tokenCount(onDay: index))) tokens\n" + parts.joined(separator: " · ")
    }

    var accessibilitySummary: String {
        var parts = ["Token Usage", period.summaryTitle]
        switch phase {
        case .unavailable:
            parts.append("Token usage unavailable")
        case .loading:
            parts.append(subtitle)
        case .loaded:
            parts.append(subtitle)
            for summary in toolSummaries {
                if summary.isUnavailable {
                    parts.append("\(summary.tool.displayName) unavailable")
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
        let seriesOf = { (data: TokenUsageMenuLoadedData) in
            data.tools.isEmpty
                ? [AllToolsTokenUsageMenuProvider.codexSeries(from: data.buckets, in: interval, calendar: calendar)]
                : data.tools
        }

        switch loadState {
        case .loaded(let data):
            phase = .loaded
            tools = seriesOf(data)
            unavailableTools = data.unavailableTools
        case .loading(let progress, let preview):
            phase = .loading(fraction: progress?.fraction ?? 0)
            tools = preview.map(seriesOf) ?? [AllToolsTokenUsageMenuProvider.codexSeries(from: [], in: interval, calendar: calendar)]
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
            unavailableTools: unavailableTools
        )
    }
}

/// The card's live model: the coordinator replaces `card` as data arrives, so an open menu updates in place,
/// and the toggles write straight to the preferences.
@MainActor
@Observable
final class TokenUsageCardModel {
    var card: TokenUsageMenuCard
    var theme: AppTheme
    let preferences: TokenUsagePreferencesStore

    init(card: TokenUsageMenuCard, theme: AppTheme = .defaultTheme, preferences: TokenUsagePreferencesStore) {
        self.card = card
        self.theme = theme
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
