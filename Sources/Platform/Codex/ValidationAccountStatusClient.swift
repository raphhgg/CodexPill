import Foundation

struct ValidationAccountStatusClient: CodexAccountStatusClient, SavedCodexAccountStatusClient {
    private let repository: AccountRepository
    private let authService: CodexAuthSnapshotService

    init(repository: AccountRepository, authService: CodexAuthSnapshotService) {
        self.repository = repository
        self.authService = authService
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        try await readSavedAccountStatus(authData: authService.readCurrentAuthData())
    }

    func readSavedAccountStatus(authData: Data) async throws -> CodexAccountStatus {
        let fingerprint = CodexAuthSnapshotService.snapshotFingerprint(for: authData)
        let account = try repository.loadAccounts().first { account in
            account.identity.snapshotFingerprint == fingerprint
        }

        return CodexAccountStatus(
            email: account?.email ?? CodexAuthDataParser.email(from: authData),
            planType: account?.planType ?? CodexAuthDataParser.planType(from: authData),
            rateLimits: account?.rateLimits,
            stableAccountID: account?.identity.stableAccountID ?? CodexAuthDataParser.stableAccountID(from: authData),
            authPrincipalIdentity: account?.identity.authPrincipalIdentity ?? CodexAuthDataParser.authPrincipalIdentity(from: authData),
            workspaceIdentity: account?.identity.workspaceIdentity ?? CodexAuthDataParser.workspaceIdentity(from: authData),
            snapshotFingerprint: fingerprint
        )
    }
}
