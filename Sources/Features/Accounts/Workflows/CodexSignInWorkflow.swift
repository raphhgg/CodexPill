import Foundation

/// One browser sign-in to Codex in a temporary `CODEX_HOME`. Nothing on this Mac changes until the user agrees to use
/// the account, which then replaces `auth.json`.
final class CodexSignInSession: @unchecked Sendable {
    let prompt: IsolatedCodexLoginPrompt

    fileprivate let liveAuthFingerprintBefore: String?
    fileprivate let loginSession: IsolatedCodexLoginSession

    init(liveAuthFingerprintBefore: String?, loginSession: IsolatedCodexLoginSession) {
        self.liveAuthFingerprintBefore = liveAuthFingerprintBefore
        self.loginSession = loginSession
        prompt = loginSession.prompt
    }
}

/// A finished sign-in, held in memory until it replaces `auth.json` or is dropped.
struct CodexSignedInAccount {
    let account: CodexAccount
    fileprivate let authData: Data
}

struct CodexSignInWorkflow: Sendable {
    private let authFile: CodexAuthFile
    private let isolatedLoginClient: IsolatedCodexLoginClient
    private let codexAppProcessClient: CodexAppProcessClient

    init(
        authFile: CodexAuthFile,
        isolatedLoginClient: IsolatedCodexLoginClient = SystemIsolatedCodexLoginClient(),
        codexAppProcessClient: CodexAppProcessClient
    ) {
        self.authFile = authFile
        self.isolatedLoginClient = isolatedLoginClient
        self.codexAppProcessClient = codexAppProcessClient
    }

    func start() async throws -> CodexSignInSession {
        let fingerprint = authFile.currentFingerprint()
        return CodexSignInSession(liveAuthFingerprintBefore: fingerprint, loginSession: try await isolatedLoginClient.startLogin())
    }

    /// Waits for the browser sign-in. Throws when it lands on the account already in use, or when `auth.json` changed
    /// meanwhile, so replacing it can't drop a sign-in the user made elsewhere.
    func complete(_ session: CodexSignInSession) async throws -> CodexSignedInAccount {
        defer { session.loginSession.cleanup() }

        let authData = try await session.loginSession.waitForAuthData()
        guard await session.loginSession.verifyLoginStatus() else {
            throw IsolatedCodexLoginError.loginStatusVerificationFailed
        }
        guard authFile.currentFingerprint() == session.liveAuthFingerprintBefore else {
            throw CodexSignInWorkflowError.liveAuthChanged
        }
        let account = CodexAuthFile.account(forAuthData: authData)
        if let current = authFile.currentAccount(), current.isSameAccount(as: account) {
            throw CodexSignInWorkflowError.accountAlreadyInUse
        }
        return CodexSignedInAccount(account: account, authData: authData)
    }

    func cancel(_ session: CodexSignInSession) {
        session.loginSession.cancel()
        session.loginSession.cleanup()
    }

    /// Replaces `auth.json` with the new sign-in and relaunches Codex so it picks it up.
    func use(_ signedIn: CodexSignedInAccount) async throws -> CodexRelaunch {
        try authFile.write(signedIn.authData)
        return try await codexAppProcessClient.relaunchCodex()
    }
}

enum CodexSignInWorkflowError: Equatable, LocalizedError {
    case liveAuthChanged
    case accountAlreadyInUse

    var errorDescription: String? {
        switch self {
        case .liveAuthChanged:
            "The Codex sign-in on this Mac changed during sign-in. Nothing was replaced."
        case .accountAlreadyInUse:
            "This Codex account is already the one on this Mac."
        }
    }
}
