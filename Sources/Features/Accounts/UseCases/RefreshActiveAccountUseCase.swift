import Foundation

struct RefreshActiveAccountResult {
    let accounts: [CodexAccount]
    let refreshedAccountID: UUID
}

struct RefreshActiveAccountUseCase {
    private let accountStatusClient: CodexAccountStatusClient
    private let identityResolver: SavedAccountIdentityResolver
    private let repository: AccountCatalogStore

    init(
        accountStatusClient: CodexAccountStatusClient,
        identityResolver: SavedAccountIdentityResolver,
        repository: AccountCatalogStore
    ) {
        self.accountStatusClient = accountStatusClient
        self.identityResolver = identityResolver
        self.repository = repository
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
