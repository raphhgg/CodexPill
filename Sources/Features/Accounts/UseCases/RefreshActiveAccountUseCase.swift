import Foundation

struct RefreshActiveAccountResult: Equatable {
    let update: SavedAccountMetadataUpdate
}

protocol ActiveAuthSnapshotRelinking: Sendable {
    func currentAuthFingerprint() -> String?
    func readCurrentAuthData() throws -> Data
    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount
}

extension CodexAuthSnapshotService: ActiveAuthSnapshotRelinking {}

struct RefreshActiveAccountUseCase: Sendable {
    private let accountStatusClient: CodexAccountStatusClient
    private let identityResolver: SavedAccountIdentityResolver
    private let repository: AccountCatalogStore
    private let activeAuthSnapshotRelinker: ActiveAuthSnapshotRelinking?

    init(
        accountStatusClient: CodexAccountStatusClient,
        identityResolver: SavedAccountIdentityResolver,
        repository: AccountCatalogStore,
        activeAuthSnapshotRelinker: ActiveAuthSnapshotRelinking? = nil
    ) {
        self.accountStatusClient = accountStatusClient
        self.identityResolver = identityResolver
        self.repository = repository
        self.activeAuthSnapshotRelinker = activeAuthSnapshotRelinker
    }

    func run(accounts: [CodexAccount]) async throws -> RefreshActiveAccountResult {
        // Resolves against the auth read before the await, since a switch can replace it meanwhile.
        let liveIdentity = identityResolver.readCurrentLiveIdentity()
        let remote = try await accountStatusClient.readCurrentAccountStatus()
        let matchOutcome = identityResolver.resolve(
            liveIdentity: liveIdentity,
            accounts: accounts,
            liveRemoteIdentity: remote.remoteIdentity
        )

        guard let matchedAccountID = matchOutcome.matchedAccountID else {
            throw RefreshActiveAccountUseCaseError.targetResolutionFailed(matchOutcome)
        }

        guard let matchedIndex = accounts.firstIndex(where: { $0.id == matchedAccountID }) else {
            throw RefreshActiveAccountUseCaseError.targetMissing
        }

        let hasFreshRateLimits = remote.rateLimits != nil
        var refreshedAccount = accounts[matchedIndex]
        refreshedAccount.applyRemoteMetadata(
            email: remote.email,
            planType: remote.planType,
            rateLimits: remote.rateLimits ?? refreshedAccount.rateLimits,
            preferRateLimitPlan: hasFreshRateLimits
        )
        if hasFreshRateLimits {
            refreshedAccount.updatedAt = .now
        }
        return RefreshActiveAccountResult(update: SavedAccountMetadataUpdate(refreshedAccount))
    }

    func relinkCurrentAuthSnapshotIfNeeded(
        accounts: [CodexAccount],
        targetAccountID: UUID
    ) throws -> RefreshActiveAccountResult? {
        guard let targetAccount = accounts.first(where: { $0.id == targetAccountID }),
              let relinkedAccount = try relinkActiveAuthSnapshotIfNeeded(for: targetAccount, among: accounts)
        else {
            return nil
        }
        return RefreshActiveAccountResult(update: SavedAccountMetadataUpdate(relinkedAccount))
    }

    // Merges into the accounts as they are now, since a remove or rename can land while `run` awaits.
    // Relinking waits until here so a removed account never gets its auth snapshot written back.
    func save(_ result: RefreshActiveAccountResult, into accounts: [CodexAccount]) throws -> [CodexAccount]? {
        guard var account = accounts.first(where: { $0.id == result.update.accountID }) else { return nil }
        account.apply(result.update)
        if let relinkedAccount = try? relinkActiveAuthSnapshotIfNeeded(for: account, among: accounts) {
            account.identity = relinkedAccount.identity
            account.identity.remoteIdentity = result.update.identity.remoteIdentity
        }
        return try repository.save(SavedAccountMetadataUpdate(account), into: accounts)
    }

    private func relinkActiveAuthSnapshotIfNeeded(
        for account: CodexAccount,
        among accounts: [CodexAccount]
    ) throws -> CodexAccount? {
        guard let activeAuthSnapshotRelinker,
              identityResolver.resolveCurrentAccountID(accounts: accounts) == account.id,
              activeAuthSnapshotRelinker.currentAuthFingerprint() != account.identity.snapshotFingerprint
        else {
            return nil
        }
        let currentAuthData = try activeAuthSnapshotRelinker.readCurrentAuthData()
        var relinkedAccount = try activeAuthSnapshotRelinker.saveAuthSnapshot(
            currentAuthData,
            named: account.name,
            existing: account
        )
        relinkedAccount.updatedAt = account.updatedAt
        return relinkedAccount
    }
}

enum RefreshActiveAccountUseCaseError: LocalizedError, Equatable {
    case targetResolutionFailed(CodexAccountMatchOutcome)
    case targetMissing

    var errorDescription: String? {
        switch self {
        case .targetResolutionFailed(.ambiguousScopedStableAccountID):
            "Could not refresh the active account because more than one saved account matches the current Codex account and workspace."
        case .targetResolutionFailed(.ambiguousStableAccountID):
            "Could not refresh the active account because more than one saved account matches the current Codex account id."
        case .targetResolutionFailed(.ambiguousSnapshotFingerprint):
            "Could not refresh the active account because more than one saved account matches the current auth snapshot."
        case .targetResolutionFailed(.ambiguousRemoteIdentity):
            "Could not refresh the active account because more than one saved account matches the current Codex account identity."
        case .targetResolutionFailed(.noMatch):
            "Could not refresh the active account because the current Codex account does not match any saved account."
        case .targetResolutionFailed(.exactScopedStableAccountID),
             .targetResolutionFailed(.exactStableAccountID),
             .targetResolutionFailed(.exactSnapshot),
             .targetResolutionFailed(.uniqueRemoteIdentity):
            "Could not refresh the active account."
        case .targetMissing:
            "Could not refresh the active account because the matched saved account is missing."
        }
    }
}
