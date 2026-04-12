import Foundation

protocol AccountSnapshotDeleting: AccountCatalogPersisting {
    func deleteSnapshot(for account: CodexAccount) throws
}

extension AccountRepository: AccountSnapshotDeleting {}

struct DeleteSavedAccountResult {
    let accounts: [CodexAccount]
    let activeAccountID: UUID?
}

struct DeleteSavedAccountUseCase {
    private let repository: AccountSnapshotDeleting
    private let activeAccountResolver: ActiveAccountResolver

    init(
        repository: AccountSnapshotDeleting,
        activeAccountResolver: ActiveAccountResolver
    ) {
        self.repository = repository
        self.activeAccountResolver = activeAccountResolver
    }

    func run(account: CodexAccount, accounts: [CodexAccount]) throws -> DeleteSavedAccountResult {
        try repository.deleteSnapshot(for: account)
        let updatedAccounts = accounts.filter { $0.id != account.id }
        try repository.saveAccounts(updatedAccounts)

        return DeleteSavedAccountResult(
            accounts: updatedAccounts,
            activeAccountID: activeAccountResolver.resolveActiveAccountID(accounts: updatedAccounts)
        )
    }
}
