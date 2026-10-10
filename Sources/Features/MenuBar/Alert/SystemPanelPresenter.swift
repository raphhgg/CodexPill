import Foundation

@MainActor
final class SystemPanelPresenter {
    private let environment: [String: String]
    private let panelWindowFactory: PanelWindowFactory

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        appIconSource: AppIconSource? = nil
    ) {
        self.environment = environment
        self.panelWindowFactory = PanelWindowFactory(appIconSource: appIconSource ?? BundleAppIconSource())
    }
}

extension SystemPanelPresenter: PanelPresenter {
    func presentAddAccountSignIn(
        _ request: MenuBarAddAccountSignInPanelRequest,
        waitForCompletion: @escaping () async -> Result<CodexAccount, Error>,
        onCancel: @escaping () -> Void
    ) async -> MenuBarAddAccountSignInPanelResult {
        guard !AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(environment: environment) else {
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
