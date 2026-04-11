import Foundation

protocol CodexAuthActivating: CodexAuthFingerprintReading {
    func activate(_ account: CodexAccount) throws
}

extension CodexAuthSnapshotService: CodexAuthActivating {}

protocol AccountCatalogPersisting {
    func saveAccounts(_ accounts: [CodexAccount]) throws
}

extension AccountRepository: AccountCatalogPersisting {}

protocol CodexAppRelaunching {
    func relaunchCodex() async throws
}

extension CodexAppController: CodexAppRelaunching {}

struct SwitchAccountWorkflow {
    private let authService: CodexAuthActivating
    private let repository: AccountCatalogPersisting
    private let appController: CodexAppRelaunching
    private let accountMatcher: CodexAccountMatcher

    init(
        authService: CodexAuthActivating,
        repository: AccountCatalogPersisting,
        appController: CodexAppRelaunching,
        accountMatcher: CodexAccountMatcher = CodexAccountMatcher()
    ) {
        self.authService = authService
        self.repository = repository
        self.appController = appController
        self.accountMatcher = accountMatcher
    }

    func run(
        account: CodexAccount,
        accounts: [CodexAccount]
    ) async throws -> UUID? {
        try authService.activate(account)
        try repository.saveAccounts(accounts)

        let activeAccountID = accountMatcher.match(
            liveAuthFingerprint: authService.currentAuthFingerprint(),
            liveRemoteIdentity: nil,
            accounts: accounts
        ).matchedAccountID

        try await appController.relaunchCodex()
        return activeAccountID
    }
}
