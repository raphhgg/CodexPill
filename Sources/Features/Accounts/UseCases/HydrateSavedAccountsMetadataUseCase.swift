import Foundation

protocol CodexAuthDataRestoring: CodexAuthActivating {
    func readCurrentAuthData() throws -> Data
    func restoreCurrentAuthData(_ data: Data) throws
}

extension CodexAuthSnapshotService: CodexAuthDataRestoring {
}

struct HydrateSavedAccountsMetadataResult {
    let accounts: [CodexAccount]
    let activeAccountID: UUID?
    let hydratedAccountIDs: [UUID]
}

struct HydrateSavedAccountsMetadataUseCase {
    private let authService: CodexAuthDataRestoring
    private let appServerClient: CodexAccountStatusReading
    private let identityResolver: SavedAccountIdentityResolver
    private let repository: AccountCatalogPersisting

    init(
        authService: CodexAuthDataRestoring,
        appServerClient: CodexAccountStatusReading,
        identityResolver: SavedAccountIdentityResolver,
        repository: AccountCatalogPersisting
    ) {
        self.authService = authService
        self.appServerClient = appServerClient
        self.identityResolver = identityResolver
        self.repository = repository
    }

    func run(accounts: [CodexAccount], activeAccountID: UUID?) async throws -> HydrateSavedAccountsMetadataResult {
        let missingMetadataIDs = accounts
            .filter { $0.id != activeAccountID && $0.rateLimits == nil }
            .map(\.id)

        guard !missingMetadataIDs.isEmpty else {
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

        for accountID in missingMetadataIDs {
            guard let index = updatedAccounts.firstIndex(where: { $0.id == accountID }) else { continue }

            try authService.activate(updatedAccounts[index])
            let remote = try await appServerClient.readCurrentAccountStatus()

            updatedAccounts[index].applyRemoteMetadata(
                email: remote.email ?? updatedAccounts[index].email,
                planType: remote.planType ?? updatedAccounts[index].planType,
                rateLimits: remote.rateLimits ?? updatedAccounts[index].rateLimits
            )
            updatedAccounts[index].updatedAt = .now

            if remote.rateLimits != nil {
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
