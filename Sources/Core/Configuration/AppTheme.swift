import Foundation

/// The look of Refill: the app icon, the usage bars on each tool card, and the Token Usage chart.
enum AppTheme: String, CaseIterable {
    case cobalt
    case lagoon
    case emerald
    case violet
    case honey
    case rose
    case monochrome
    /// Each tool in its own color. The app icon keeps the last color picked.
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

    /// The icon this theme sets. Nil when the theme keeps the current icon.
    var iconColor: AppIconColor? {
        switch self {
        case .cobalt: .cobalt
        case .lagoon: .lagoon
        case .emerald: .emerald
        case .violet: .violet
        case .honey: .honey
        case .rose: .rose
        case .monochrome: .graphite
        case .toolColors: nil
        }
    }
}
