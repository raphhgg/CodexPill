import AppKit

@MainActor
final class SystemAlertPresenter {
    private let suppressesInteractivePrompts: Bool
    private let appIconSource: AppIconSource

    init(
        suppressesInteractivePrompts: Bool,
        appIconSource: AppIconSource? = nil
    ) {
        self.suppressesInteractivePrompts = suppressesInteractivePrompts
        self.appIconSource = appIconSource ?? BundleAppIconSource()
    }

    func presentConfirmation(_ request: MenuBarConfirmationAlertRequest) -> Bool {
        guard !suppressesInteractivePrompts else {
            return false
        }

        let alert = NSAlert()
        configure(alert: alert)
        alert.messageText = request.messageText
        alert.informativeText = request.informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: request.confirmTitle)
        alert.addButton(withTitle: request.cancelTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func presentInfo(_ request: MenuBarInfoAlertRequest) {
        guard !suppressesInteractivePrompts else {
            return
        }

        let alert = NSAlert()
        configure(alert: alert)
        alert.messageText = request.messageText
        alert.informativeText = request.informativeText
        alert.alertStyle = request.style
        alert.addButton(withTitle: request.buttonTitle)
        alert.runModal()
    }

    private func configure(alert: NSAlert) {
        alert.icon = appIconSource.appIconImage()
    }
}

extension SystemAlertPresenter: AlertPresenter {}
