import Foundation

enum StatusBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly
    case iconAndText
    case textOnHover

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .iconOnly:
            "Icon Only"
        case .iconAndText:
            "Icon + Text"
        case .textOnHover:
            "Text on Hover"
        }
    }
}

enum StatusBarIndicatorStyle: String, CaseIterable, Identifiable {
    case dualArcBadge
    case stackedBars
    case twinPills

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .dualArcBadge:
            "Dual Arc Badge"
        case .stackedBars:
            "Stacked Bars"
        case .twinPills:
            "Twin Pills"
        }
    }
}

enum UsageBarDisplayMode: String, CaseIterable, Identifiable {
    case used
    case left

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .used:
            "Show % Used"
        case .left:
            "Show % Left"
        }
    }
}

enum UsageBarLayout: String, CaseIterable, Identifiable {
    case classic
    case compact

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .classic:
            "Classic"
        case .compact:
            "Compact"
        }
    }
}

enum OtherAccountsDisplayMode: String, CaseIterable, Identifiable {
    case text
    case bars

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .text:
            "Show as Text"
        case .bars:
            "Show as Bars"
        }
    }
}
