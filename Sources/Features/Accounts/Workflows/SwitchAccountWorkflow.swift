import Foundation

protocol CodexAuthActivating {
    func activate(_ account: CodexAccount) throws
}

extension CodexAuthSnapshotService: CodexAuthActivating {}

protocol AccountCatalogPersisting {
    func saveAccounts(_ accounts: [CodexAccount]) throws
}

extension AccountRepository: AccountCatalogPersisting {}

protocol CodexAppRelaunching {
    func assertCodexAvailable() throws
    func relaunchCodex() async throws
}

extension CodexAppController: CodexAppRelaunching {}

struct SwitchAccountWorkflow {
    private let authService: CodexAuthActivating
    private let repository: AccountCatalogPersisting
    private let appController: CodexAppRelaunching
    private let identityResolver: SavedAccountIdentityResolver

    init(
        authService: CodexAuthActivating,
        repository: AccountCatalogPersisting,
        appController: CodexAppRelaunching,
        identityResolver: SavedAccountIdentityResolver
    ) {
        self.authService = authService
        self.repository = repository
        self.appController = appController
        self.identityResolver = identityResolver
    }

    func run(
        account: CodexAccount,
        accounts: [CodexAccount]
    ) async throws -> UUID? {
        try appController.assertCodexAvailable()
        try authService.activate(account)
        try repository.saveAccounts(accounts)

        let activeAccountID = identityResolver.resolveCurrentAccountID(accounts: accounts)

        try await appController.relaunchCodex()
        return activeAccountID
    }
}
