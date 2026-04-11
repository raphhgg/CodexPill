import Foundation

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
