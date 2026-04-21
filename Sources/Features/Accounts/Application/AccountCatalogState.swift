import Foundation

struct AccountCatalogState {
    private(set) var accounts: [CodexAccount] = []
    private(set) var activeAccountID: UUID?

    var activeAccount: CodexAccount? {
        accounts.first(where: { $0.id == activeAccountID })
    }

    var inactiveAccounts: [CodexAccount] {
        accounts.filter { $0.id != activeAccountID }
    }

    mutating func applyLoad(_ result: LoadAccountsResult) {
        accounts = result.accounts
        activeAccountID = result.activeAccountID
    }

    mutating func applySavedAccount(_ account: CodexAccount, activeAccountID: UUID?) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        accounts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.activeAccountID = activeAccountID
    }

    mutating func applyDeleted(_ result: DeleteSavedAccountResult) {
        accounts = result.accounts
        activeAccountID = result.activeAccountID
    }

    mutating func applyRenamed(_ result: RenameSavedAccountResult) {
        accounts = result.accounts
    }

    mutating func applyHydrated(_ result: HydrateSavedAccountsMetadataResult) {
        accounts = result.accounts
        activeAccountID = result.activeAccountID
    }

    mutating func applyRefreshed(_ result: RefreshActiveAccountResult) {
        accounts = result.accounts
        activeAccountID = result.refreshedAccountID
    }

    mutating func applyPersistedMetadata(_ accounts: [CodexAccount]) {
        self.accounts = accounts
    }

    mutating func setActiveAccountID(_ activeAccountID: UUID?) {
        self.activeAccountID = activeAccountID
    }

    mutating func resolveActiveAccountID(using identityResolver: SavedAccountIdentityResolver) {
        activeAccountID = identityResolver.resolveCurrentAccountID(accounts: accounts)
    }
}
