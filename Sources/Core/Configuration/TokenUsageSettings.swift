import Foundation

/// Whether the Token Usage card shows, and how it draws its 30 days.
struct TokenUsageSettings: SettingsGroup {
    static let key = "settings.tokenUsage.v1"
    static let defaults = TokenUsageSettings()

    var isEnabled = false
    var chartStyle = TokenUsageChartStyle.bars
    var breakdown = TokenUsageBreakdown.byTool
    var peakScope = TokenUsagePeakScope.currentPeriod
}

extension TokenUsageSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        isEnabled = container.value(.isEnabled, or: defaults.isEnabled)
        chartStyle = container.value(.chartStyle, or: defaults.chartStyle)
        breakdown = container.value(.breakdown, or: defaults.breakdown)
        peakScope = container.value(.peakScope, or: defaults.peakScope)
    }
}
