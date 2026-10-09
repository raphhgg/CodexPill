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
    func presentHostSetup(
        _ request: MenuBarHostSetupPanelRequest,
        testConnection: @escaping (RemoteHost) async -> Result<Void, Error>,
        onPresented: @escaping () -> Void = {},
        onCancelled: @escaping () -> Void = {},
        onValidationStarted: @escaping (RemoteHost) -> Void = { _ in },
        onValidationFinished: @escaping (RemoteHost, Result<Void, Error>) -> Void = { _, _ in }
    ) async -> RemoteHost? {
        guard !suppressesInteractivePrompts else {
            onCancelled()
            return nil
        }

        let controller = AddHostPanelController(
            request: request,
            panelWindowFactory: panelWindowFactory,
            testConnection: testConnection,
            onPresented: onPresented,
            onCancelled: onCancelled,
            onValidationStarted: onValidationStarted,
            onValidationFinished: onValidationFinished
        )
        let result = await controller.runModal()
        // Give AppKit one pass to remove the setup panel before a follow-up
        // confirmation panel is presented.
        await Task.yield()
        return result
    }

    func presentAddAccountSignIn(
        _ request: MenuBarAddAccountSignInPanelRequest,
        waitForCompletion: @escaping () async -> Result<CodexAccount, Error>,
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
