import Foundation

protocol CodexSignInAnotherAuthHandling: CodexAuthSnapshotSaving {
    func prepareForNewSignIn() throws
    func readCurrentAuthData() throws -> Data
}

extension CodexAuthSnapshotService: CodexSignInAnotherAuthHandling {}

struct SignInAnotherPreparationResult {
    let pendingAccountName: String
}

struct CompletePendingSignedInAccountResult {
    let savedAccount: CodexAccount
    let activeAccountID: UUID?
}

struct SignInAnotherWorkflow {
    private let authService: CodexSignInAnotherAuthHandling
    private let appController: CodexAppRelaunching
    private let appServerClient: CodexAccountStatusReading
    private let repository: AccountCatalogPersisting
    private let identityResolver: SavedAccountIdentityResolver

    init(
        authService: CodexSignInAnotherAuthHandling,
        appController: CodexAppRelaunching,
        appServerClient: CodexAccountStatusReading,
        repository: AccountCatalogPersisting,
        identityResolver: SavedAccountIdentityResolver
    ) {
        self.authService = authService
        self.appController = appController
        self.appServerClient = appServerClient
        self.repository = repository
        self.identityResolver = identityResolver
    }

    func prepare(named pendingAccountName: String?) throws -> SignInAnotherPreparationResult {
        let resolvedName = resolveAccountName(pendingAccountName, fallbackEmail: nil)
        try appController.assertCodexAvailable()
        try authService.prepareForNewSignIn()
        return SignInAnotherPreparationResult(pendingAccountName: resolvedName)
    }

    func relaunchCodex() async throws {
        try await appController.relaunchCodex()
    }

    func completePendingSignIn(
        pendingAccountName: String,
        existingAccounts: [CodexAccount]
    ) async throws -> CompletePendingSignedInAccountResult? {
        guard (try? authService.readCurrentAuthData()) != nil else {
            return nil
        }

        let remote = try? await appServerClient.readCurrentAccountStatus()
        let matchOutcome = identityResolver.resolve(accounts: existingAccounts)
        let matchedAccountID = matchOutcome.isSafeForOverwrite ? matchOutcome.matchedAccountID : nil
        let existing = matchedAccountID.flatMap { id in
            existingAccounts.first(where: { $0.id == id })
        }
        let resolvedName = existing?.name ?? resolveAccountName(pendingAccountName, fallbackEmail: nil)

        if matchedAccountID == nil,
           existingAccounts.contains(where: { $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame }) {
            throw SaveCurrentAccountWorkflowError.duplicateAccountName
        }

        let saved = try authService.saveCurrentAuthSnapshot(named: resolvedName, existing: existing)
        var enriched = saved

        if let remote {
            enriched.applyRemoteMetadata(
                email: remote.email,
                planType: remote.planType,
                rateLimits: remote.rateLimits
            )
        }

        var updatedAccounts = existingAccounts
        if let matchedAccountID,
           let existingIndex = updatedAccounts.firstIndex(where: { $0.id == matchedAccountID }) {
            updatedAccounts[existingIndex] = enriched
        } else {
            updatedAccounts.append(enriched)
        }
        updatedAccounts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try repository.saveAccounts(updatedAccounts)

        return CompletePendingSignedInAccountResult(
            savedAccount: enriched,
            activeAccountID: enriched.id
        )
    }

    private func resolveAccountName(_ customName: String?, fallbackEmail: String?) -> String {
        let trimmedCustomName = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedCustomName.isEmpty {
            return trimmedCustomName
        }

        let trimmedEmail = fallbackEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedEmail.isEmpty {
            return trimmedEmail
        }

        return "Codex Account"
    }
}
