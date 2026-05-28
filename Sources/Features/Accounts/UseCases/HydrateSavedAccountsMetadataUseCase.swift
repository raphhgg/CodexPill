import Foundation

protocol CodexAuthSessionStore: CodexAuthActivator {
    func readCurrentAuthData() throws -> Data
    func restoreCurrentAuthData(_ data: Data) throws
    func readAuthSnapshot(for account: CodexAccount) throws -> Data
}

extension CodexAuthSnapshotService: CodexAuthSessionStore {
}

struct HydrateSavedAccountsMetadataResult {
    let accounts: [CodexAccount]
    let activeAccountID: UUID?
    let hydratedAccountIDs: [UUID]
}

struct HydrateSavedAccountsMetadataUseCase: Sendable {
    private let authService: CodexAuthSessionStore
    private let savedAccountStatusClient: SavedCodexAccountStatusClient
    private let identityResolver: SavedAccountIdentityResolver
    private let repository: AccountCatalogStore

    init(
        authService: CodexAuthSessionStore,
        accountStatusClient: CodexAccountStatusClient,
        savedAccountStatusClient: SavedCodexAccountStatusClient,
        identityResolver: SavedAccountIdentityResolver,
        repository: AccountCatalogStore
    ) {
        self.authService = authService
        self.savedAccountStatusClient = savedAccountStatusClient
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

        var updatedAccounts = accounts
        var hydratedAccountIDs: [UUID] = []

        for accountID in candidateAccountIDs {
            guard let index = updatedAccounts.firstIndex(where: { $0.id == accountID }) else { continue }

            let remote: CodexAccountStatus
            do {
                let snapshot = try authService.readAuthSnapshot(for: updatedAccounts[index])
                remote = try await savedAccountStatusClient.readSavedAccountStatus(authData: snapshot)
            } catch {
                continue
            }
            let hasFreshRateLimits = appServerRateLimitsHaveUsableWindow(remote.rateLimits)
                && !appServerRateLimitsLookSuspiciouslyZeroed(remote.rateLimits)

            updatedAccounts[index].applyRemoteMetadata(
                email: remote.email ?? updatedAccounts[index].email,
                planType: remote.planType ?? updatedAccounts[index].planType,
                rateLimits: hasFreshRateLimits ? remote.rateLimits : updatedAccounts[index].rateLimits,
                preferRateLimitPlan: hasFreshRateLimits
            )

            if hasFreshRateLimits {
                updatedAccounts[index].updatedAt = .now
                hydratedAccountIDs.append(accountID)
            }
        }

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
