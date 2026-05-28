import Foundation

struct CodexAccountStatus: Equatable {
    var email: String?
    var planType: String?
    var rateLimits: CodexRateLimitSnapshot?
    var stableAccountID: String? = nil
    var authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil
    var workspaceIdentity: CodexWorkspaceIdentity? = nil
    var snapshotFingerprint: String? = nil

    var remoteIdentity: CodexRemoteAccountIdentity? {
        CodexRemoteAccountIdentity(emailAddress: email)
    }
}

protocol CodexAccountStatusClient: Sendable {
    func readCurrentAccountStatus() async throws -> CodexAccountStatus
}

protocol SavedCodexAccountStatusClient: Sendable {
    func readSavedAccountStatus(authData: Data) async throws -> CodexAccountStatus
}
