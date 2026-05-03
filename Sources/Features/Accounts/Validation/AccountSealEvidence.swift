import Foundation

struct AccountSealAccountStateSnapshot: Encodable {
    let activeAccountId: String?
    let savedAccountIds: [String]
    let savedAccountNames: [String]
    let savedAccountCount: Int
    let savedAccounts: [AccountSealSavedAccountSnapshot]

    init(activeAccount: CodexAccount?, savedAccounts: [CodexAccount]) {
        self.activeAccountId = activeAccount?.id.uuidString
        self.savedAccountIds = savedAccounts.map { $0.id.uuidString }
        self.savedAccountNames = savedAccounts.map(\.name)
        self.savedAccountCount = savedAccounts.count
        self.savedAccounts = savedAccounts.map(AccountSealSavedAccountSnapshot.init(account:))
    }
}

struct AccountSealSavedAccountSnapshot: Encodable {
    let id: String
    let name: String
    let email: String?

    init(account: CodexAccount) {
        self.id = account.id.uuidString
        self.name = account.name
        self.email = account.email
    }
}

struct AccountSealScheduledRefreshUIEvidence: Encodable {
    let statusMessage: String?
    let menuItemCount: Int
    let lastMenuAction: String?
    let lastConfirmationRequest: String?
    let hasBlockingAlert: Bool

    init(
        statusMessage: String?,
        menuItemCount: Int,
        lastMenuAction: String?,
        lastConfirmationRequest: String?
    ) {
        self.statusMessage = statusMessage
        self.menuItemCount = menuItemCount
        self.lastMenuAction = lastMenuAction
        self.lastConfirmationRequest = lastConfirmationRequest
        self.hasBlockingAlert = lastConfirmationRequest != nil
    }
}

struct AccountSealNameDialogSnapshot: Encodable {
    let dialogId: String
    let title: String
    let wasPresented: Bool
    let finalState: String
}
