import Foundation

protocol CodexAuthSessionStore: CodexAuthActivator {
    func readCurrentAuthData() throws -> Data
    func restoreCurrentAuthData(_ data: Data) throws
    func readAuthSnapshot(for account: CodexAccount) throws -> Data
    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity
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
                    (refreshExistingMetadata || account.usage == nil)
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

            guard let snapshot = try? authService.readAuthSnapshot(for: updatedAccounts[index]) else { continue }
            let read = await savedAccountStatusClient.readSavedAccountStatus(authData: snapshot)

            if let rotatedAuthData = read.rotatedAuthData,
               let rewrittenAccount = writeBackRotatedAuthData(
                   rotatedAuthData,
                   for: updatedAccounts[index],
                   accounts: updatedAccounts
               ) {
                updatedAccounts[index] = rewrittenAccount
            }

            guard case .success(let remote) = read.status else { continue }
            let hasFreshRateLimits = appServerUsageHasUsableWindow(remote.usage)
                && !appServerUsageLooksSuspiciouslyZeroed(remote.usage)

            updatedAccounts[index].applyRemoteMetadata(
                email: remote.email ?? updatedAccounts[index].email,
                planType: remote.planType ?? updatedAccounts[index].planType,
                usage: hasFreshRateLimits ? remote.usage : updatedAccounts[index].usage,
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

    private func writeBackRotatedAuthData(
        _ rotatedAuthData: Data,
        for account: CodexAccount,
        accounts: [CodexAccount]
    ) -> CodexAccount? {
        let identity = authService.liveIdentity(forAuthData: rotatedAuthData)
        let outcome = CodexAccountMatcher().match(
            liveStableAccountID: identity.stableAccountID,
            liveAuthPrincipalIdentity: identity.authPrincipalIdentity,
            liveWorkspaceIdentity: identity.workspaceIdentity,
            liveAuthFingerprint: identity.snapshotFingerprint,
            liveRemoteIdentity: identity.remoteIdentity,
            accounts: accounts
        )
        guard outcome.isSafeForOverwrite,
              outcome.matchedAccountID == account.id,
              var rewrittenAccount = try? authService.saveAuthSnapshot(rotatedAuthData, named: account.name, existing: account)
        else {
            return nil
        }
        rewrittenAccount.updatedAt = account.updatedAt
        return rewrittenAccount
    }
}
