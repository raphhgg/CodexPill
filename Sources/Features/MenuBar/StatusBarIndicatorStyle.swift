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
