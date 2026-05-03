import Foundation

@MainActor
protocol AccountValidationRecorder {
    func recordAddAccountMenuAction(activeAccount: CodexAccount?, savedAccounts: [CodexAccount])
    func recordAddAccountNameDialogPresented(runningCLISessions: Int)
    func recordAddAccountNameDialogCancelled(activeAccount: CodexAccount?, savedAccounts: [CodexAccount])
    func recordSwitchAccountMenuAction(
        targetAccount: CodexAccount,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    )
    func recordSwitchConfirmationPresented(targetAccount: CodexAccount)
    func recordSwitchConfirmationAccepted(targetAccount: CodexAccount)
    func recordSwitchWorkflowStarted(targetAccount: CodexAccount)
    func recordActiveAccountChanged(
        fromName: String?,
        toName: String,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    )
    func recordScheduledRefreshRequested(
        accountName: String,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    )
    func recordScheduledRefreshResult(
        accountName: String,
        error: String?,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount],
        uiEvidence: AccountSealScheduledRefreshUIEvidence
    )
}
