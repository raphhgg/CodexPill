import AppKit

extension AppIconColor {
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
