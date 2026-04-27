import Foundation

protocol CodexAuthSessionStore: CodexAuthActivator {
    func readCurrentAuthData() throws -> Data
    func restoreCurrentAuthData(_ data: Data) throws
}

extension CodexAuthSnapshotService: CodexAuthSessionStore {
}

struct HydrateSavedAccountsMetadataResult {
    let accounts: [CodexAccount]
    let activeAccountID: UUID?
    let hydratedAccountIDs: [UUID]
}

struct HydrateSavedAccountsMetadataUseCase {
    private let authService: CodexAuthSessionStore
    private let accountStatusClient: CodexAccountStatusClient
    private let identityResolver: SavedAccountIdentityResolver
    private let repository: AccountCatalogStore

    init(
        authService: CodexAuthSessionStore,
        accountStatusClient: CodexAccountStatusClient,
        identityResolver: SavedAccountIdentityResolver,
        repository: AccountCatalogStore
    ) {
        self.authService = authService
        self.accountStatusClient = accountStatusClient
        self.identityResolver = identityResolver
        self.repository = repository
    }

    func run(
        accounts: [CodexAccount],
        activeAccountID: UUID?,
        refreshExistingMetadata: Bool = false
    ) async throws -> HydrateSavedAccountsMetadataResult {
        let candidateAccountIDs = accounts
            .filter { account in
                account.id != activeAccountID &&
                    (refreshExistingMetadata || account.rateLimits == nil)
            }
            .map(\.id)

        guard !candidateAccountIDs.isEmpty else {
            return HydrateSavedAccountsMetadataResult(
                accounts: accounts,
                activeAccountID: activeAccountID,
                hydratedAccountIDs: []
            )
        }

        let originalAuthData = try authService.readCurrentAuthData()
        var updatedAccounts = accounts
        var hydratedAccountIDs: [UUID] = []
        var shouldRestoreOriginalAuth = true

        defer {
            if shouldRestoreOriginalAuth {
                try? authService.restoreCurrentAuthData(originalAuthData)
            }
        }

        for accountID in candidateAccountIDs {
            guard let index = updatedAccounts.firstIndex(where: { $0.id == accountID }) else { continue }

            try authService.activate(updatedAccounts[index])
            let remote = try await accountStatusClient.readCurrentAccountStatus()
            let hasFreshRateLimits = remote.rateLimits != nil

            updatedAccounts[index].applyRemoteMetadata(
                email: remote.email ?? updatedAccounts[index].email,
                planType: remote.planType ?? updatedAccounts[index].planType,
                rateLimits: remote.rateLimits ?? updatedAccounts[index].rateLimits,
                preferRateLimitPlan: hasFreshRateLimits
            )

            if hasFreshRateLimits {
                updatedAccounts[index].updatedAt = .now
                hydratedAccountIDs.append(accountID)
            }
        }

        try authService.restoreCurrentAuthData(originalAuthData)
        shouldRestoreOriginalAuth = false

        if updatedAccounts != accounts {
            try repository.saveAccounts(updatedAccounts)
        }

        return HydrateSavedAccountsMetadataResult(
            accounts: updatedAccounts,
            activeAccountID: identityResolver.resolveCurrentAccountID(accounts: updatedAccounts),
            hydratedAccountIDs: hydratedAccountIDs
        )
    }
}
