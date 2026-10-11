import AppKit

enum AppIconColor: String, CaseIterable {
    case cobalt
    case lagoon
    case emerald
    case violet
    case honey
    case rose

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
        }
    }

    func overrideImage(in bundle: Bundle = .main) -> NSImage? {
        guard self != .defaultColor,
              let url = bundle.url(forResource: "AppIcon-\(rawValue)", withExtension: "png")
        else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

@MainActor
protocol AppIconApplying {
    func apply(_ color: AppIconColor)
}

struct SystemAppIconApplier: AppIconApplying {
    func apply(_ color: AppIconColor) {
        // Setting nil restores the bundle icon.
        NSApp.applicationIconImage = color.overrideImage()
    }
}
