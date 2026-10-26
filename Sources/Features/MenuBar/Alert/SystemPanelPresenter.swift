import Foundation

@MainActor
final class SystemPanelPresenter {
    private let suppressesInteractivePrompts: Bool
    private let panelWindowFactory: PanelWindowFactory

    init(
        suppressesInteractivePrompts: Bool,
        appIconSource: AppIconSource? = nil
    ) {
        self.suppressesInteractivePrompts = suppressesInteractivePrompts
        self.panelWindowFactory = PanelWindowFactory(appIconSource: appIconSource ?? BundleAppIconSource())
    }
}

extension SystemPanelPresenter: PanelPresenter {
    func presentAddAccountSignIn(
        _ request: MenuBarAddAccountSignInPanelRequest,
        waitForCompletion: @escaping () async -> Result<CodexSignedInAccount, Error>,
        onCancel: @escaping () -> Void
    ) async -> MenuBarAddAccountSignInPanelResult {
        guard !suppressesInteractivePrompts else {
            onCancel()
            return .cancelled
        }

        let controller = CodexSignInPanelController(
            request: request,
            panelWindowFactory: panelWindowFactory,
            waitForCompletion: waitForCompletion,
            onCancel: onCancel
        )
        return await controller.runModal()
    }
}
