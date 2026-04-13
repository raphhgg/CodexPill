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
    private let identityResolver: SavedAccountIdentityResolver

    init(
        repository: AccountSnapshotDeleting,
        identityResolver: SavedAccountIdentityResolver
    ) {
        self.repository = repository
        self.identityResolver = identityResolver
    }

    func run(account: CodexAccount, accounts: [CodexAccount]) throws -> DeleteSavedAccountResult {
        try repository.deleteSnapshot(for: account)
        let updatedAccounts = accounts.filter { $0.id != account.id }
        try repository.saveAccounts(updatedAccounts)

        return DeleteSavedAccountResult(
            accounts: updatedAccounts,
            activeAccountID: identityResolver.resolveCurrentAccountID(accounts: updatedAccounts)
        )
    }
}
