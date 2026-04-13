import Foundation

protocol AccountCatalogLoading: AccountCatalogPersisting {
    func bootstrapStorage() throws
    func loadAccounts() throws -> [CodexAccount]
}

extension AccountRepository: AccountCatalogLoading {}

struct LoadAccountsResult {
    let accounts: [CodexAccount]
    let activeAccountID: UUID?
}

struct LoadAccountsUseCase {
    private let repository: AccountCatalogLoading
    private let identityResolver: SavedAccountIdentityResolver

    init(
        repository: AccountCatalogLoading,
        identityResolver: SavedAccountIdentityResolver
    ) {
        self.repository = repository
        self.identityResolver = identityResolver
    }

    func run() throws -> LoadAccountsResult {
        try repository.bootstrapStorage()
        let loadedAccounts = try repository.loadAccounts()
        let reconciledAccounts = identityResolver.reconcileStoredAccounts(loadedAccounts)
        if reconciledAccounts != loadedAccounts {
            try repository.saveAccounts(reconciledAccounts)
        }

        return LoadAccountsResult(
            accounts: reconciledAccounts,
            activeAccountID: identityResolver.resolveCurrentAccountID(accounts: reconciledAccounts)
        )
    }
}
