import Foundation

@MainActor
protocol MenuBarAccounts: AnyObject {
    var accounts: [CodexAccount] { get }
    var activeAccount: CodexAccount? { get }
    var activeAccountID: UUID? { get }
    var sortedInactiveAccounts: [CodexAccount] { get }
    var pendingErrorMessage: String? { get }
    var statusMessage: String { get }
    var isBusy: Bool { get }
    var isApplyingResetCredit: Bool { get }

    func switchToAccount(_ account: CodexAccount) async -> Bool
    func useResetCredit() async -> ResetCreditResult
    func removeSavedAccount(_ account: CodexAccount, signOutLocalAccount: Bool) async
    func refreshAccountData(for account: CodexAccount) async -> AccountsController.BackgroundRefreshOutcome
    func refreshActiveAccount()
    func refreshInactiveSavedAccountsMetadata() async
    func persistAccountMetadata(_ account: CodexAccount)
    func consumePendingErrorMessage() -> String?
    func startIsolatedAddAccountFlow() async throws -> IsolatedAddAccountSignInSession
    func completeIsolatedAddAccount(_ session: IsolatedAddAccountSignInSession) async throws -> CodexAccount
    func cancelIsolatedAddAccount(_ session: IsolatedAddAccountSignInSession)
}

extension AccountsController: MenuBarAccounts {}
