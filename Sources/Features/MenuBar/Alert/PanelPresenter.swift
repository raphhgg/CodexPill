import Foundation

@MainActor
protocol PanelPresenter {
    func presentHostSetup(
        _ request: MenuBarHostSetupPanelRequest,
        testConnection: @escaping (RemoteHost) async -> Result<Void, Error>
    ) async -> RemoteHost?
    func presentAddAccountSignIn(
        _ request: MenuBarAddAccountSignInPanelRequest,
        waitForCompletion: @escaping () async -> Result<CodexAccount, Error>,
        onCancel: @escaping () -> Void
    ) async -> MenuBarAddAccountSignInPanelResult
}

struct MenuBarHostSetupPanelRequest {
    let messageText: String
    let informativeText: String
    let fieldTitle: String
    let placeholder: String
    let nameFieldTitle: String
    let namePlaceholder: String
    let confirmTitle: String
    let cancelTitle: String
    let idleStatusText: String
    let successStatusText: String
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
