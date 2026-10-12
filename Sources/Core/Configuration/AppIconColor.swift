enum AppIconColor: String, CaseIterable {
    case cobalt
    case lagoon
    case emerald
    case violet
    case honey
    case rose
    /// The Monochrome theme's icon.
    case graphite

    static let defaultColor: AppIconColor = .cobalt

    var menuTitle: String {
        switch self {
        case .cobalt:
            return "Cobalt"
        case .lagoon:
            return "Deep teal"
        case .emerald:
            return "Emerald"
        case .violet:
            return "Violet"
        case .honey:
            return "Honey"
        case .rose:
            return "Rose"
        case .graphite:
            return "Graphite"
        }
    }
}
