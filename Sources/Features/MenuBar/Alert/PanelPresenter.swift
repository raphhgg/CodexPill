import Foundation

@MainActor
protocol PanelPresenter {
    func presentAddAccountSignIn(
        _ request: MenuBarAddAccountSignInPanelRequest,
        waitForCompletion: @escaping () async -> Result<CodexAccount, Error>,
        onCancel: @escaping () -> Void
    ) async -> MenuBarAddAccountSignInPanelResult
}

struct MenuBarAddAccountSignInPanelRequest {
    let messageText: String
    let informativeText: String
    let userCode: String
    let promptURL: URL
    let waitingStatusText: String
    let copiedStatusText: String
    let browserOpenedStatusText: String
    let copyTitle: String
    let openBrowserTitle: String
    let cancelTitle: String
}

enum MenuBarAddAccountSignInPanelResult {
    case completed(CodexAccount)
    case cancelled
    case failed(Error)
}
