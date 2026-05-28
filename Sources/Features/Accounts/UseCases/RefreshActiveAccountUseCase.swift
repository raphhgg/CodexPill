import Foundation

struct RefreshActiveAccountResult {
    let accounts: [CodexAccount]
    let refreshedAccountID: UUID
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
        let remote = try await accountStatusClient.readCurrentAccountStatus()
        let matchOutcome = identityResolver.resolve(
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
        var updatedAccounts = accounts
        if activeAuthSnapshotRelinker?.currentAuthFingerprint() != updatedAccounts[matchedIndex].identity.snapshotFingerprint,
           let relinkedAccount = try? relinkActiveAuthSnapshot(for: updatedAccounts[matchedIndex]) {
            updatedAccounts[matchedIndex] = relinkedAccount
        }

        updatedAccounts[matchedIndex].applyRemoteMetadata(
            email: remote.email,
            planType: remote.planType,
            rateLimits: remote.rateLimits ?? updatedAccounts[matchedIndex].rateLimits,
            preferRateLimitPlan: hasFreshRateLimits
        )
        if hasFreshRateLimits {
            updatedAccounts[matchedIndex].updatedAt = .now
        }
        try repository.saveAccounts(updatedAccounts)

        return RefreshActiveAccountResult(
            accounts: updatedAccounts,
            refreshedAccountID: matchedAccountID
        )
    }

    func relinkCurrentAuthSnapshotIfNeeded(
        accounts: [CodexAccount],
        targetAccountID: UUID
    ) throws -> RefreshActiveAccountResult? {
        guard let matchedAccountID = identityResolver.resolveCurrentAccountID(accounts: accounts),
              matchedAccountID == targetAccountID,
              let matchedIndex = accounts.firstIndex(where: { $0.id == matchedAccountID })
        else {
            return nil
        }

        let matchedAccount = accounts[matchedIndex]
        guard activeAuthSnapshotRelinker?.currentAuthFingerprint() != matchedAccount.identity.snapshotFingerprint else {
            return nil
        }

        guard let relinkedAccount = try relinkActiveAuthSnapshot(for: matchedAccount) else {
            return nil
        }

        var updatedAccounts = accounts
        updatedAccounts[matchedIndex] = relinkedAccount
        try repository.saveAccounts(updatedAccounts)
        return RefreshActiveAccountResult(
            accounts: updatedAccounts,
            refreshedAccountID: matchedAccountID
        )
    }

    private func relinkActiveAuthSnapshot(for account: CodexAccount) throws -> CodexAccount? {
        guard let activeAuthSnapshotRelinker else { return nil }
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
