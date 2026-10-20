import Foundation

/// The look of rusage: the usage bars on each tool card and the Token Usage chart.
enum AppTheme: String, CaseIterable {
    case cobalt
    case lagoon
    case emerald
    case violet
    case honey
    case rose
    case monochrome
    /// Each tool in its own color.
    case toolColors

    static let defaultTheme: AppTheme = .cobalt

    var menuTitle: String {
        switch self {
        case .cobalt: "Cobalt"
        case .lagoon: "Deep Teal"
        case .emerald: "Emerald"
        case .violet: "Violet"
        case .honey: "Honey"
        case .rose: "Rose"
        case .monochrome: "Monochrome"
        case .toolColors: "Tool Colors"
        }
    }
}
