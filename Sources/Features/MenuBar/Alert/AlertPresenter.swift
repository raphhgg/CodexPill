import AppKit

@MainActor
protocol AppIconSource {
    func appIconImage() -> NSImage?
}

@MainActor
struct BundleAppIconSource: AppIconSource {
    func appIconImage() -> NSImage? {
        if let resourceIcon = NSImage.codexPillAppIcon() {
            return resourceIcon
        }

        if let applicationIcon = NSApp.applicationIconImage {
            return applicationIcon
        }

        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

extension NSImage {
    static func codexPillAppIcon(bundle: Bundle = .main) -> NSImage? {
        guard let iconURL = bundle.url(forResource: "AppIcon", withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: iconURL)
    }
}

@MainActor
protocol AlertPresenter {
    func presentTextInput(_ request: MenuBarTextInputAlertRequest) -> String?
    func presentConfirmation(_ request: MenuBarConfirmationAlertRequest) -> Bool
    func presentInfo(_ request: MenuBarInfoAlertRequest)
}

struct MenuBarTextInputAlertRequest {
    let messageText: String
    let informativeText: String
    let fieldTitle: String
    let placeholder: String
    let confirmTitle: String
    let cancelTitle: String
    let requiresNonEmptyValue: Bool
}

struct MenuBarConfirmationAlertRequest {
    let messageText: String
    let informativeText: String
    let confirmTitle: String
    let cancelTitle: String
}

struct MenuBarInfoAlertRequest {
    let messageText: String
    let informativeText: String
    let style: NSAlert.Style
    let buttonTitle: String
}
