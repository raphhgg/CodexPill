import Foundation

protocol CodexSignInAuthStore: CodexAuthSnapshotStore {
    func prepareForNewSignIn() throws
    func readCurrentAuthData() throws -> Data
    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount
    func currentAuthFingerprint() -> String?
    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity
}

extension CodexAuthSnapshotService: CodexSignInAuthStore {}

struct SignInAnotherPreparationResult {
    let pendingAccountName: String
}

struct CompletePendingSignedInAccountResult {
    let savedAccount: CodexAccount
    let activeAccountID: UUID?
}

final class IsolatedAddAccountSignInSession {
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

struct SignInAnotherWorkflow {
    private let authService: CodexSignInAuthStore
    private let codexAppProcessClient: CodexAppProcessClient
    private let accountStatusClient: CodexAccountStatusClient
    private let repository: AccountCatalogStore
    private let identityResolver: SavedAccountIdentityResolver
    private let isolatedLoginClient: IsolatedCodexLoginClient

    init(
        authService: CodexSignInAuthStore,
        codexAppProcessClient: CodexAppProcessClient,
        accountStatusClient: CodexAccountStatusClient,
        repository: AccountCatalogStore,
        identityResolver: SavedAccountIdentityResolver,
        isolatedLoginClient: IsolatedCodexLoginClient = SystemIsolatedCodexLoginClient()
    ) {
        self.authService = authService
        self.codexAppProcessClient = codexAppProcessClient
        self.accountStatusClient = accountStatusClient
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
    ) async throws -> CompletePendingSignedInAccountResult {
        defer { session.loginSession.cleanup() }

        let authData = try await session.loginSession.waitForAuthData()
        guard await session.loginSession.verifyLoginStatus() else {
            throw IsolatedCodexLoginError.loginStatusVerificationFailed
        }
        guard authService.currentAuthFingerprint() == session.liveAuthFingerprintBefore else {
            throw IsolatedAddAccountWorkflowError.liveAuthChanged
        }

        let capturedIdentity = authService.liveIdentity(forAuthData: authData)
        let matchOutcome = identityResolver.resolve(
            liveIdentity: capturedIdentity,
            accounts: existingAccounts
        )
        if matchOutcome.isSafeForOverwrite,
           let matchedAccountID = matchOutcome.matchedAccountID,
           let matchedAccount = existingAccounts.first(where: { $0.id == matchedAccountID }) {
            throw IsolatedAddAccountWorkflowError.accountAlreadySaved(matchedAccount.name)
        }

        let saved: CodexAccount
        do {
            saved = try authService.saveAuthSnapshot(authData, named: session.accountName, existing: nil)
        } catch {
            throw IsolatedAddAccountWorkflowError.catalogSaveFailed
        }
        var updatedAccounts = existingAccounts
        updatedAccounts.append(saved)
        updatedAccounts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        do {
            try repository.saveAccounts(updatedAccounts)
        } catch {
            throw IsolatedAddAccountWorkflowError.catalogSaveFailed
        }

        return CompletePendingSignedInAccountResult(
            savedAccount: saved,
            activeAccountID: activeAccountID
        )
    }

    func cancelIsolatedAddAccount(_ session: IsolatedAddAccountSignInSession) {
        session.loginSession.cancel()
        session.loginSession.cleanup()
    }

    func prepare(named pendingAccountName: String?, existingAccounts: [CodexAccount]) throws -> SignInAnotherPreparationResult {
        let resolvedName = try validateNewAccountName(pendingAccountName, existingAccounts: existingAccounts)

        try codexAppProcessClient.assertCodexAvailable()
        try authService.prepareForNewSignIn()
        return SignInAnotherPreparationResult(pendingAccountName: resolvedName)
    }

    func relaunchCodex() async throws {
        try await codexAppProcessClient.relaunchCodex()
    }

    func completePendingSignIn(
        pendingAccountName: String,
        existingAccounts: [CodexAccount]
    ) async throws -> CompletePendingSignedInAccountResult? {
        guard (try? authService.readCurrentAuthData()) != nil else {
            return nil
        }

        let remote = try? await accountStatusClient.readCurrentAccountStatus()
        let matchOutcome = identityResolver.resolve(
            accounts: existingAccounts,
            liveRemoteIdentity: remote?.remoteIdentity
        )
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

    private func validateNewAccountName(
        _ customName: String?,
        existingAccounts: [CodexAccount]
    ) throws -> String {
        let resolvedName = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !resolvedName.isEmpty else {
            throw SaveCurrentAccountWorkflowError.emptyAccountName
        }
        guard !existingAccounts.contains(where: { $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame }) else {
            throw SaveCurrentAccountWorkflowError.duplicateAccountName
        }
        return resolvedName
    }
}

enum IsolatedAddAccountWorkflowError: Equatable, LocalizedError {
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
