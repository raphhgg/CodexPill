import Foundation

protocol CodexSignInAuthStore: Sendable {
    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount
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
    let accountName: String
    let prompt: IsolatedCodexLoginPrompt

    fileprivate let liveAuthFingerprintBefore: String?
    fileprivate let loginSession: IsolatedCodexLoginSession

    init(
        accountName: String,
        liveAuthFingerprintBefore: String?,
        loginSession: IsolatedCodexLoginSession
    ) {
        self.accountName = accountName
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

    func startIsolatedAddAccount(
        named pendingAccountName: String?,
        existingAccounts: [CodexAccount]
    ) async throws -> IsolatedAddAccountSignInSession {
        let resolvedName = try validateNewAccountName(pendingAccountName, existingAccounts: existingAccounts)
        let liveAuthFingerprintBefore = authService.currentAuthFingerprint()
        let loginSession = try await isolatedLoginClient.startLogin()
        return IsolatedAddAccountSignInSession(
            accountName: resolvedName,
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
           let matchedAccount = existingAccounts.first(where: { $0.id == matchedAccountID }) {
            throw AddAccountWorkflowError.accountAlreadySaved(matchedAccount.name)
        }

        let saved: CodexAccount
        do {
            saved = try authService.saveAuthSnapshot(authData, named: session.accountName, existing: nil)
        } catch {
            throw AddAccountWorkflowError.catalogSaveFailed
        }
        var updatedAccounts = existingAccounts
        updatedAccounts.append(saved)
        updatedAccounts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    private func validateNewAccountName(
        _ customName: String?,
        existingAccounts: [CodexAccount]
    ) throws -> String {
        let resolvedName = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !resolvedName.isEmpty else {
            throw AccountDisplayNameError.emptyAccountName
        }
        guard !existingAccounts.contains(where: { $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame }) else {
            throw AccountDisplayNameError.duplicateAccountName
        }
        return resolvedName
    }
}

enum AccountDisplayNameError: Equatable, LocalizedError {
    case emptyAccountName
    case duplicateAccountName

    var errorDescription: String? {
        switch self {
        case .emptyAccountName:
            "Account name is required."
        case .duplicateAccountName:
            "An account with that name already exists."
        }
    }
}

enum AddAccountWorkflowError: Equatable, LocalizedError {
    case liveAuthChanged
    case accountAlreadySaved(String)
    case catalogSaveFailed

    var errorDescription: String? {
        switch self {
        case .liveAuthChanged:
            "CodexPill could not verify that your current account stayed unchanged. No account was added."
        case .accountAlreadySaved(let name):
            "This Codex account is already saved as \(name)."
        case .catalogSaveFailed:
            "The sign-in completed, but CodexPill could not save the account. Your current Codex account was not changed."
        }
    }
}
