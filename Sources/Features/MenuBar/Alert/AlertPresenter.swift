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
