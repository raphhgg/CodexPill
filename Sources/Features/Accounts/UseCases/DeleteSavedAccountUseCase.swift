import Foundation

protocol AccountSnapshotRemover: AccountCatalogStore {
    func deleteSnapshot(for account: CodexAccount) throws
}

extension AccountRepository: AccountSnapshotRemover {}

protocol CodexAuthSignerOut: Sendable {
    func signOut() async throws
}

struct CodexLocalAuthSignOut: CodexAuthSignerOut {
    private let authService: CodexAuthSnapshotService
    private let codexAppProcessClient: CodexAppProcessClient

    init(authService: CodexAuthSnapshotService, codexAppProcessClient: CodexAppProcessClient) {
        self.authService = authService
        self.codexAppProcessClient = codexAppProcessClient
    }

    func signOut() async throws {
        try codexAppProcessClient.assertCodexAvailable()
        try authService.signOut()
        try await codexAppProcessClient.relaunchCodex()
    }
}

struct NoopCodexAuthSignerOut: CodexAuthSignerOut {
    func signOut() async throws {}
}

struct DeleteSavedAccountResult {
    let accounts: [CodexAccount]
    let activeAccountID: UUID?
}

struct DeleteSavedAccountUseCase: Sendable {
    private let repository: AccountSnapshotRemover
    private let identityResolver: SavedAccountIdentityResolver
    private let authSignerOut: CodexAuthSignerOut

    init(
        repository: AccountSnapshotRemover,
        identityResolver: SavedAccountIdentityResolver,
        authSignerOut: CodexAuthSignerOut = NoopCodexAuthSignerOut()
    ) {
        self.repository = repository
        self.identityResolver = identityResolver
        self.authSignerOut = authSignerOut
    }

    func run(account: CodexAccount, accounts: [CodexAccount], signOutLocalAccount: Bool = false) async throws -> DeleteSavedAccountResult {
        if signOutLocalAccount {
            try await authSignerOut.signOut()
        }
        try repository.deleteSnapshot(for: account)
        let updatedAccounts = accounts.filter { $0.id != account.id }
        try repository.saveAccounts(updatedAccounts)

        return DeleteSavedAccountResult(
            accounts: updatedAccounts,
            activeAccountID: identityResolver.resolveCurrentAccountID(accounts: updatedAccounts)
        )
    }
}
