import Foundation

protocol CodexSignInAnotherAuthHandling: CodexAuthSnapshotSaving, CodexAuthFingerprintReading {
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
    private let activeAccountResolver: ActiveAccountResolver

    init(
        authService: CodexSignInAnotherAuthHandling,
        appController: CodexAppRelaunching,
        appServerClient: CodexAccountStatusReading,
        repository: AccountCatalogPersisting,
        activeAccountResolver: ActiveAccountResolver
    ) {
        self.authService = authService
        self.appController = appController
        self.appServerClient = appServerClient
        self.repository = repository
        self.activeAccountResolver = activeAccountResolver
    }

    func prepare(named pendingAccountName: String?) throws -> SignInAnotherPreparationResult {
        let resolvedName = resolveAccountName(pendingAccountName, fallbackEmail: nil)
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

        let resolvedName = resolveAccountName(pendingAccountName, fallbackEmail: nil)
        guard !existingAccounts.contains(where: { $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame }) else {
            throw SaveCurrentAccountWorkflowError.duplicateAccountName
        }

        let saved = try authService.saveCurrentAuthSnapshot(named: resolvedName, existing: nil)
        var enriched = saved
        let remote = try? await appServerClient.readCurrentAccountStatus()

        if let remote {
            enriched.applyRemoteMetadata(
                email: remote.email,
                planType: remote.planType,
                rateLimits: remote.rateLimits
            )
        }

        var updatedAccounts = existingAccounts
        updatedAccounts.append(enriched)
        updatedAccounts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try repository.saveAccounts(updatedAccounts)

        let activeAccountID = activeAccountResolver.resolveActiveAccountID(
            accounts: updatedAccounts,
            liveRemoteIdentity: remote?.remoteIdentity
        )

        return CompletePendingSignedInAccountResult(
            savedAccount: enriched,
            activeAccountID: activeAccountID
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
