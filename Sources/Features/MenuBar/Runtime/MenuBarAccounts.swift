import Foundation

/// The Codex account the menu shows and the actions it offers on it.
@MainActor
protocol MenuBarAccounts: AnyObject {
    var activeAccount: CodexAccount? { get }
    var pendingErrorMessage: String? { get }
    var statusMessage: String { get }
    var isBusy: Bool { get }
    var isApplyingResetCredit: Bool { get }

    func useResetCredit() async -> ResetCreditResult
    func refreshAccountData() async -> AccountsController.BackgroundRefreshOutcome
    func refreshActiveAccount()
    func consumePendingErrorMessage() -> String?
    func startSignIn() async throws -> CodexSignInSession
    func completeSignIn(_ session: CodexSignInSession) async throws -> CodexSignedInAccount
    func cancelSignIn(_ session: CodexSignInSession)
    func use(_ signedIn: CodexSignedInAccount) async -> CodexRelaunch?
    func signOut() async -> CodexRelaunch?
}

extension AccountsController: MenuBarAccounts {}
