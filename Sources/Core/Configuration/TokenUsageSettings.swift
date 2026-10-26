import Foundation

/// How much of the Token Usage card the menu shows.
enum TokenUsageDisplay: String, CaseIterable, Codable, Sendable {
    case hidden
    /// The chart, with the breakdown while the pointer is over the card.
    case graphWithBreakdownOnHover
    case graphAndBreakdown
}

/// Whether the Token Usage card shows, and how it draws its 30 days.
struct TokenUsageSettings: SettingsGroup {
    static let key = "settings.tokenUsage.v1"
    static let defaults = TokenUsageSettings()

    var display = TokenUsageDisplay.hidden
    var chartStyle = TokenUsageChartStyle.bars
    var breakdown = TokenUsageBreakdown.byTool
    var peakScope = TokenUsagePeakScope.currentPeriod

    /// Whether the card shows at all. Turning it on shows the chart and breakdown.
    var isEnabled: Bool {
        get { display != .hidden }
        set { display = newValue ? (display == .hidden ? .graphAndBreakdown : display) : .hidden }
    }
}

extension TokenUsageSettings {
    /// `isEnabled` is only read: earlier builds stored it before `display` existed.
    enum CodingKeys: String, CodingKey {
        case display
        case isEnabled
        case chartStyle
        case breakdown
        case peakScope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        if let display = try? container.decodeIfPresent(TokenUsageDisplay.self, forKey: .display) {
            self.display = display
        } else {
            display = container.value(.isEnabled, or: false) ? .graphAndBreakdown : defaults.display
        }
        chartStyle = container.value(.chartStyle, or: defaults.chartStyle)
        breakdown = container.value(.breakdown, or: defaults.breakdown)
        peakScope = container.value(.peakScope, or: defaults.peakScope)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(display, forKey: .display)
        try container.encode(chartStyle, forKey: .chartStyle)
        try container.encode(breakdown, forKey: .breakdown)
        try container.encode(peakScope, forKey: .peakScope)
    }
}
