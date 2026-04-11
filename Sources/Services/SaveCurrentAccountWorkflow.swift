import Foundation

protocol CodexAccountStatusReading {
    func readCurrentAccountStatus() async throws -> CodexAccountStatus
}

extension CodexAppServerClient: CodexAccountStatusReading {}

protocol CodexAuthSnapshotSaving {
    func saveCurrentAuthSnapshot(
        named name: String,
        existing: CodexAccount?
    ) throws -> CodexAccount
}

extension CodexAuthSnapshotService: CodexAuthSnapshotSaving {}

struct SaveCurrentAccountWorkflowResult {
    let savedAccount: CodexAccount
    let activeAccountID: UUID?
}

struct SaveCurrentAccountWorkflow {
    private let appServerClient: CodexAccountStatusReading
    private let authService: CodexAuthSnapshotSaving
    private let repository: AccountCatalogPersisting
    private let accountMatcher: CodexAccountMatcher

    init(
        appServerClient: CodexAccountStatusReading,
        authService: CodexAuthSnapshotSaving,
        repository: AccountCatalogPersisting,
        accountMatcher: CodexAccountMatcher = CodexAccountMatcher()
    ) {
        self.appServerClient = appServerClient
        self.authService = authService
        self.repository = repository
        self.accountMatcher = accountMatcher
    }

    func run(
        customName: String?,
        existingAccounts: [CodexAccount]
    ) async throws -> SaveCurrentAccountWorkflowResult {
        let remote = try await appServerClient.readCurrentAccountStatus()
        let resolvedName = resolveAccountName(customName, fallbackEmail: remote.email)

        guard !existingAccounts.contains(where: { $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame }) else {
            throw SaveCurrentAccountWorkflowError.duplicateAccountName
        }

        var saved = try authService.saveCurrentAuthSnapshot(
            named: resolvedName,
            existing: nil
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

        let activeAccountID = accountMatcher.match(
            liveAuthFingerprint: saved.identity.snapshotFingerprint,
            liveRemoteIdentity: remote.remoteIdentity,
            accounts: updatedAccounts
        ).matchedAccountID

        return SaveCurrentAccountWorkflowResult(
            savedAccount: saved,
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

enum SaveCurrentAccountWorkflowError: LocalizedError {
    case duplicateAccountName

    var errorDescription: String? {
        switch self {
        case .duplicateAccountName:
            "An account with that name already exists."
        }
    }
}
