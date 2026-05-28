import Foundation

enum TokenUsageChartStyle: String, CaseIterable, Codable, Equatable {
    case dailyBars
    case heatStrip
    case sparkline

    var menuTitle: String {
        switch self {
        case .dailyBars:
            return "Daily Bars"
        case .heatStrip:
            return "Heat Strip"
        case .sparkline:
            return "Sparkline"
        }
    }
}
