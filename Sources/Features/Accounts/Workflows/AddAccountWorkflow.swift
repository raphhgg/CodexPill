import Foundation

protocol CodexSignInAuthStore: Sendable {
    func saveAuthSnapshot(_ authData: Data, existing: CodexAccount?) throws -> CodexAccount
    func deleteAuthSnapshot(for account: CodexAccount) throws
    func currentAuthFingerprint() -> String?
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity
}

extension CodexAuthSnapshotService: CodexSignInAuthStore {}

struct AddAccountResult {
    let savedAccount: CodexAccount
    let activeAccountID: UUID?
}

final class IsolatedAddAccountSignInSession: @unchecked Sendable {
    let prompt: IsolatedCodexLoginPrompt

    fileprivate let liveAuthFingerprintBefore: String?
    fileprivate let loginSession: IsolatedCodexLoginSession

    init(
        liveAuthFingerprintBefore: String?,
        loginSession: IsolatedCodexLoginSession
    ) {
        self.liveAuthFingerprintBefore = liveAuthFingerprintBefore
        self.loginSession = loginSession
        self.prompt = loginSession.prompt
    }
}

struct AddAccountWorkflow: Sendable {
    private let authService: CodexSignInAuthStore
    private let repository: AccountCatalogStore
    private let identityResolver: SavedAccountIdentityResolver
    private let isolatedLoginClient: IsolatedCodexLoginClient

    init(
        authService: CodexSignInAuthStore,
        repository: AccountCatalogStore,
        identityResolver: SavedAccountIdentityResolver,
        isolatedLoginClient: IsolatedCodexLoginClient = SystemIsolatedCodexLoginClient()
    ) {
        self.authService = authService
        self.repository = repository
        self.identityResolver = identityResolver
        self.isolatedLoginClient = isolatedLoginClient
    }

    func startIsolatedAddAccount() async throws -> IsolatedAddAccountSignInSession {
        let liveAuthFingerprintBefore = authService.currentAuthFingerprint()
        let loginSession = try await isolatedLoginClient.startLogin()
        return IsolatedAddAccountSignInSession(
            liveAuthFingerprintBefore: liveAuthFingerprintBefore,
            loginSession: loginSession
        )
    }

    func completeIsolatedAddAccount(
        _ session: IsolatedAddAccountSignInSession,
        existingAccounts: [CodexAccount],
        activeAccountID: UUID?
    ) async throws -> AddAccountResult {
        defer { session.loginSession.cleanup() }

        let authData = try await session.loginSession.waitForAuthData()
        guard await session.loginSession.verifyLoginStatus() else {
            throw IsolatedCodexLoginError.loginStatusVerificationFailed
        }
        guard authService.currentAuthFingerprint() == session.liveAuthFingerprintBefore else {
            throw AddAccountWorkflowError.liveAuthChanged
        }

        let capturedIdentity = authService.liveIdentity(forAuthData: authData)
        let matchOutcome = identityResolver.resolve(
            liveIdentity: capturedIdentity,
            accounts: existingAccounts
        )
        if matchOutcome.isSafeForOverwrite,
           let matchedAccountID = matchOutcome.matchedAccountID,
           existingAccounts.contains(where: { $0.id == matchedAccountID }) {
            throw AddAccountWorkflowError.accountAlreadySaved(matchedAccountID)
        }

        let saved: CodexAccount
        do {
            saved = try authService.saveAuthSnapshot(authData, existing: nil)
        } catch {
            throw AddAccountWorkflowError.catalogSaveFailed
        }
        var updatedAccounts = existingAccounts
        updatedAccounts.append(saved)
        updatedAccounts.sort(by: CodexAccount.listOrder)
        do {
            try repository.saveAccounts(updatedAccounts)
        } catch {
            try? authService.deleteAuthSnapshot(for: saved)
            throw AddAccountWorkflowError.catalogSaveFailed
        }

        return AddAccountResult(
            savedAccount: saved,
            activeAccountID: activeAccountID
        )
    }

    func cancelIsolatedAddAccount(_ session: IsolatedAddAccountSignInSession) {
        session.loginSession.cancel()
        session.loginSession.cleanup()
    }

}

enum AddAccountWorkflowError: Equatable, LocalizedError {
    case liveAuthChanged
    /// The signed-in account matches the saved account with this ID.
    case accountAlreadySaved(UUID)
    case catalogSaveFailed

    var errorDescription: String? {
        switch self {
        case .liveAuthChanged:
            "rusage could not verify that your current account stayed unchanged. No account was added."
        case .accountAlreadySaved:
            "This Codex account is already saved."
        case .catalogSaveFailed:
            "The sign-in completed, but rusage could not save the account. Your current Codex account was not changed."
        }
    }
}
