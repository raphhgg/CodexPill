import AppKit

@MainActor
protocol AppIconSource {
    func appIconImage() -> NSImage?
}

@MainActor
struct BundleAppIconSource: AppIconSource {
    func appIconImage() -> NSImage? {
        NSApp.applicationIconImage ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

@MainActor
protocol AlertPresenter {
    func presentConfirmation(_ request: MenuBarConfirmationAlertRequest) -> Bool
    func presentInfo(_ request: MenuBarInfoAlertRequest)
}

struct MenuBarConfirmationAlertRequest {
    let messageText: String
    let informativeText: String
    let confirmTitle: String
    let cancelTitle: String
    /// Marks the confirm button as destructive, for actions that remove or sign out.
    var isDestructive = false
}

struct MenuBarInfoAlertRequest {
    let messageText: String
    let informativeText: String
    let style: NSAlert.Style
    let buttonTitle: String
}
