import Foundation

/// How the Token Usage card draws its 30 days.
enum TokenUsageChartStyle: String, CaseIterable, Codable, Equatable {
    case bars
    case area
    case lines

    /// Styles from before the per-tool chart (`dailyBars`, `heatStrip`, `sparkline`) open as bars.
    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .bars
    }
}

/// What the Token Usage card lists under the chart.
enum TokenUsageBreakdown: String, CaseIterable, Codable, Equatable {
    case byTool
    case topModels

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .byTool
    }
}
