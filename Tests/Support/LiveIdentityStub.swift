import Foundation

@testable import CodexPill

struct LiveIdentityStub: LiveCodexAccountIdentitySource {
    let identity: LiveCodexAccountIdentity

    init(
        fingerprint: String? = nil,
        stableAccountID: String? = nil,
        authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil,
        workspaceIdentity: CodexWorkspaceIdentity? = nil,
        remoteIdentity: CodexRemoteAccountIdentity? = nil
    ) {
        identity = LiveCodexAccountIdentity(
            stableAccountID: stableAccountID,
            authPrincipalIdentity: authPrincipalIdentity,
            workspaceIdentity: workspaceIdentity,
            snapshotFingerprint: fingerprint,
            remoteIdentity: remoteIdentity
        )
    }

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        identity
    }
}
