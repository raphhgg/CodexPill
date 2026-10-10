import Foundation

/// Who the live `auth.json` belongs to, read from its tokens and, when known, from Codex.
struct LiveCodexAccountIdentity: Equatable {
    let stableAccountID: String?
    let authPrincipalIdentity: CodexAuthPrincipalIdentity?
    let workspaceIdentity: CodexWorkspaceIdentity?
    let snapshotFingerprint: String?
    let remoteIdentity: CodexRemoteAccountIdentity?

    init(
        stableAccountID: String? = nil,
        authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil,
        workspaceIdentity: CodexWorkspaceIdentity? = nil,
        snapshotFingerprint: String? = nil,
        remoteIdentity: CodexRemoteAccountIdentity? = nil
    ) {
        self.stableAccountID = stableAccountID
        self.authPrincipalIdentity = authPrincipalIdentity
        self.workspaceIdentity = workspaceIdentity
        self.snapshotFingerprint = snapshotFingerprint
        self.remoteIdentity = remoteIdentity
    }

    static let empty = Self()
}
