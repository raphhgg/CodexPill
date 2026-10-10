import Foundation

protocol CodexAuthSessionStore: CodexAuthActivator {
    func readCurrentAuthData() throws -> Data
    func restoreCurrentAuthData(_ data: Data) throws
    func readAuthSnapshot(for account: CodexAccount) throws -> Data
    func replaceAuthSnapshot(_ authData: Data, ifUnchangedFrom expected: Data, for account: CodexAccount) throws -> CodexAccount?
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity
}

extension CodexAuthSnapshotService: CodexAuthSessionStore {
}

struct SavedAccountMetadataUpdate: Equatable {
    let accountID: UUID
    let email: String?
    let planType: String?
    let rateLimits: CodexRateLimitSnapshot?
    let updatedAt: Date
    let identity: CodexAccountIdentity

    init(_ account: CodexAccount) {
        accountID = account.id
        email = account.email
        planType = account.planType
        rateLimits = account.rateLimits
        updatedAt = account.updatedAt
        identity = account.identity
    }
}

extension CodexAccount {
    mutating func apply(_ update: SavedAccountMetadataUpdate) {
        email = update.email
        planType = update.planType
        rateLimits = update.rateLimits
        updatedAt = update.updatedAt
        identity = update.identity
    }
}

extension AccountCatalogStore {
    func save(_ update: SavedAccountMetadataUpdate, into accounts: [CodexAccount]) throws -> [CodexAccount]? {
        guard let index = accounts.firstIndex(where: { $0.id == update.accountID }) else { return nil }
        var updatedAccounts = accounts
        updatedAccounts[index].apply(update)
        try saveAccounts(updatedAccounts)
        return updatedAccounts
    }
}

struct HydrateSavedAccountsMetadataUseCase: Sendable {
    private let authService: CodexAuthSessionStore
    private let savedAccountStatusClient: SavedCodexAccountStatusClient
    private let repository: AccountCatalogStore

    init(
        authService: CodexAuthSessionStore,
        savedAccountStatusClient: SavedCodexAccountStatusClient,
        repository: AccountCatalogStore
    ) {
        self.authService = authService
        self.savedAccountStatusClient = savedAccountStatusClient
        self.repository = repository
    }

    func accountIDsToRefresh(
        in accounts: [CodexAccount],
        activeAccountID: UUID?,
        refreshExistingMetadata: Bool
    ) -> [UUID] {
        accounts
            .filter { account in
                account.id != activeAccountID &&
                    (refreshExistingMetadata || account.rateLimits == nil)
            }
            .map(\.id)
    }

    func refresh(_ account: CodexAccount, among accounts: [CodexAccount]) async -> SavedAccountMetadataUpdate? {
        guard let snapshot = try? authService.readAuthSnapshot(for: account) else { return nil }
        let read = await savedAccountStatusClient.readSavedAccountStatus(authData: snapshot)

        var refreshed = account
        if let rotatedAuthData = read.rotatedAuthData,
           let rewrittenAccount = writeBackRotatedAuthData(
               rotatedAuthData,
               replacing: snapshot,
               for: account,
               accounts: accounts
           ) {
            refreshed = rewrittenAccount
        }

        if case .success(let remote) = read.status {
            let hasFreshRateLimits = appServerRateLimitsHaveUsableWindow(remote.rateLimits)
                && !appServerRateLimitsLookSuspiciouslyZeroed(remote.rateLimits)

            refreshed.applyRemoteMetadata(
                email: remote.email ?? refreshed.email,
                planType: remote.planType ?? refreshed.planType,
                rateLimits: hasFreshRateLimits ? remote.rateLimits : refreshed.rateLimits,
                preferRateLimitPlan: hasFreshRateLimits
            )
            if hasFreshRateLimits {
                refreshed.updatedAt = .now
            }
        }

        return refreshed == account ? nil : SavedAccountMetadataUpdate(refreshed)
    }

    func save(_ update: SavedAccountMetadataUpdate, into accounts: [CodexAccount]) throws -> [CodexAccount]? {
        try repository.save(update, into: accounts)
    }

    private func writeBackRotatedAuthData(
        _ rotatedAuthData: Data,
        replacing readSnapshot: Data,
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
              var rewrittenAccount = try? authService.replaceAuthSnapshot(
                  rotatedAuthData,
                  ifUnchangedFrom: readSnapshot,
                  for: account
              )
        else {
            return nil
        }
        rewrittenAccount.updatedAt = account.updatedAt
        return rewrittenAccount
    }
}
