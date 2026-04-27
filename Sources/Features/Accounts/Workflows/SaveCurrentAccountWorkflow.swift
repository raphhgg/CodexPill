import Foundation

protocol CodexAccountStatusClient {
    func readCurrentAccountStatus() async throws -> CodexAccountStatus
}

extension CodexAppServerClient: CodexAccountStatusClient {}

protocol CodexAuthSnapshotStore {
    func saveCurrentAuthSnapshot(
        named name: String,
        existing: CodexAccount?
    ) throws -> CodexAccount
}

extension CodexAuthSnapshotService: CodexAuthSnapshotStore {}

struct SaveCurrentAccountWorkflowResult {
    let savedAccount: CodexAccount
    let activeAccountID: UUID?
}

struct SaveCurrentAccountWorkflow {
    private let accountStatusClient: CodexAccountStatusClient
    private let authService: CodexAuthSnapshotStore
    private let repository: AccountCatalogStore
    private let identityResolver: SavedAccountIdentityResolver

    init(
        accountStatusClient: CodexAccountStatusClient,
        authService: CodexAuthSnapshotStore,
        repository: AccountCatalogStore,
        identityResolver: SavedAccountIdentityResolver
    ) {
        self.accountStatusClient = accountStatusClient
        self.authService = authService
        self.repository = repository
        self.identityResolver = identityResolver
    }

    func run(
        customName: String?,
        existingAccounts: [CodexAccount]
    ) async throws -> SaveCurrentAccountWorkflowResult {
        let remote = try await accountStatusClient.readCurrentAccountStatus()
        let matchOutcome = identityResolver.resolve(
            accounts: existingAccounts,
            liveRemoteIdentity: remote.remoteIdentity
        )
        let matchedExistingAccountID = matchOutcome.isSafeForOverwrite ? matchOutcome.matchedAccountID : nil
        let existing = matchedExistingAccountID.flatMap { id in
            existingAccounts.first(where: { $0.id == id })
        }
        let resolvedName = resolveAccountName(customName, fallbackEmail: remote.email)

        guard !existingAccounts.contains(where: {
            $0.id != existing?.id &&
                $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame
        }) else {
            throw SaveCurrentAccountWorkflowError.duplicateAccountName
        }

        var saved = try authService.saveCurrentAuthSnapshot(
            named: resolvedName,
            existing: existing
        )
        saved.applyRemoteMetadata(
            email: remote.email,
            planType: remote.planType,
            rateLimits: remote.rateLimits
        )

        var updatedAccounts = existingAccounts
        if let index = updatedAccounts.firstIndex(where: { $0.id == saved.id }) {
            updatedAccounts[index] = saved
        } else {
            updatedAccounts.append(saved)
        }

        updatedAccounts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try repository.saveAccounts(updatedAccounts)

        return SaveCurrentAccountWorkflowResult(
            savedAccount: saved,
            activeAccountID: saved.id
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

enum SaveCurrentAccountWorkflowError: LocalizedError {
    case duplicateAccountName

    var errorDescription: String? {
        switch self {
        case .duplicateAccountName:
            "An account with that name already exists."
        }
    }
}
