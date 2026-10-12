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
    case glasses
    case moon
    case punchCard

    init(storedValue: String?) {
        switch storedValue {
        case "hourglass":
            self = .glasses
        case "dualArcBadge":
            self = .moon
        case "stackedBars", "notchedSquare":
            self = .punchCard
        default:
            self = storedValue.flatMap(Self.init(rawValue:)) ?? .glasses
        }
    }

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .glasses:
            "Glasses"
        case .moon:
            "Moon"
        case .punchCard:
            "Punch card"
        }
    }
}

enum UsagePercentMode: String, CaseIterable, Identifiable {
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

    var label: String { rawValue }

    func percent(forUsedPercent usedPercent: Int) -> Int {
        let used = min(max(usedPercent, 0), 100)
        switch self {
        case .used:
            return used
        case .left:
            return 100 - used
        }
    }
}

enum UsageMeterLayout: String, CaseIterable, Identifiable {
    case classic
    case compact

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .classic:
            "Classic Layout"
        case .compact:
            "Compact Layout"
        }
    }
}
