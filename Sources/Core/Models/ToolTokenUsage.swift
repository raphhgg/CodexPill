import Foundation

/// A coding tool whose token usage appears in the Token Usage card.
enum TokenUsageTool: String, CaseIterable, Codable, Sendable {
    case codex
    case claudeCode
    case cursor

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        case .cursor:
            return "Cursor"
        }
    }
}

/// One day of one tool's tokens, split by model.
///
/// Every tool counts input, cached input, cache writes, and output, so days compare across tools.
struct ToolDailyTokenUsage: Codable, Equatable, Sendable {
    var day: Date
    var tokensByModel: [String: Int]

    var totalTokens: Int {
        tokensByModel.values.reduce(0, +)
    }
}

/// One tool's daily usage for the visible period, oldest day first.
struct ToolTokenUsageSeries: Equatable, Sendable {
    var tool: TokenUsageTool
    var days: [ToolDailyTokenUsage]

    var totalTokens: Int {
        days.reduce(0) { $0 + $1.totalTokens }
    }

    func tokens(on day: Date) -> Int {
        days.first { $0.day == day }?.totalTokens ?? 0
    }

    /// Models by tokens over the period, largest first.
    var modelTotals: [(model: String, tokens: Int)] {
        var totals: [String: Int] = [:]
        for day in days {
            totals.merge(day.tokensByModel, uniquingKeysWith: +)
        }
        return totals
            .filter { $0.value > 0 }
            .map { (model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens == $1.tokens ? $0.model < $1.model : $0.tokens > $1.tokens }
    }
}

enum ToolTokenUsageDays {
    /// Sums usage into one entry per local day inside `interval`, filling empty days.
    static func filled(
        _ usage: [ToolDailyTokenUsage],
        in interval: DateInterval,
        calendar: Calendar
    ) -> [ToolDailyTokenUsage] {
        var byDay: [Date: [String: Int]] = [:]
        for entry in usage {
            let day = calendar.startOfDay(for: entry.day)
            byDay[day, default: [:]].merge(entry.tokensByModel, uniquingKeysWith: +)
        }

        var days: [ToolDailyTokenUsage] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            days.append(ToolDailyTokenUsage(day: day, tokensByModel: byDay[day] ?? [:]))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// The local days of the period ending today, as a half-open interval.
    static func interval(dayCount: Int, endingAt now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return DateInterval(start: start, end: end)
    }
}
