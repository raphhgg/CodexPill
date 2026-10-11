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
    case hourglass
    case moon
    case punchCard

    init(storedValue: String?) {
        switch storedValue {
        case "dualArcBadge":
            self = .moon
        case "stackedBars", "notchedSquare":
            self = .punchCard
        default:
            self = storedValue.flatMap(Self.init(rawValue:)) ?? .hourglass
        }
    }

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .hourglass:
            "Hourglass"
        case .moon:
            "Moon"
        case .punchCard:
            "Punch card"
        }
    }
}
