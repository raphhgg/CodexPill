import Foundation

protocol CodexAuthActivator {
    func activate(_ account: CodexAccount) throws
}

extension CodexAuthSnapshotService: CodexAuthActivator {}

protocol AccountCatalogStore {
    func saveAccounts(_ accounts: [CodexAccount]) throws
}

extension AccountRepository: AccountCatalogStore {}

struct SwitchAccountWorkflow {
    private let authService: CodexAuthActivator
    private let repository: AccountCatalogStore
    private let codexAppProcessClient: CodexAppProcessClient
    private let identityResolver: SavedAccountIdentityResolver

    init(
        authService: CodexAuthActivator,
        repository: AccountCatalogStore,
        codexAppProcessClient: CodexAppProcessClient,
        identityResolver: SavedAccountIdentityResolver
    ) {
        self.authService = authService
        self.repository = repository
        self.codexAppProcessClient = codexAppProcessClient
        self.identityResolver = identityResolver
    }

    func run(
        account: CodexAccount,
        accounts: [CodexAccount]
    ) async throws -> UUID? {
        try codexAppProcessClient.assertCodexAvailable()
        try authService.activate(account)
        try repository.saveAccounts(accounts)

        let activeAccountID = identityResolver.resolveCurrentAccountID(accounts: accounts)

        try await codexAppProcessClient.relaunchCodex()
        return activeAccountID
    }
}
