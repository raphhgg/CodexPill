import Foundation

struct RefreshActiveAccountResult {
    let accounts: [CodexAccount]
    let refreshedAccountID: UUID
}

struct RefreshActiveAccountUseCase {
    private let appServerClient: CodexAccountStatusReading
    private let identityResolver: SavedAccountIdentityResolver
    private let repository: AccountCatalogPersisting

    init(
        appServerClient: CodexAccountStatusReading,
        identityResolver: SavedAccountIdentityResolver,
        repository: AccountCatalogPersisting
    ) {
        self.appServerClient = appServerClient
        self.identityResolver = identityResolver
        self.repository = repository
    }

    func run(accounts: [CodexAccount]) async throws -> RefreshActiveAccountResult {
        let remote = try await appServerClient.readCurrentAccountStatus()
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

        var updatedAccounts = accounts
        updatedAccounts[matchedIndex].applyRemoteMetadata(
            email: remote.email,
            planType: remote.planType,
            rateLimits: remote.rateLimits ?? updatedAccounts[matchedIndex].rateLimits
        )
        updatedAccounts[matchedIndex].updatedAt = .now
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
