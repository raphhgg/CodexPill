import Foundation

protocol LiveCodexAccountIdentitySource: Sendable {
    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity
}

protocol StoredAccountIdentityReconciler: Sendable {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount]
}

extension CodexAuthSnapshotService: LiveCodexAccountIdentitySource {
    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(
            stableAccountID: currentStableAccountID(),
            authPrincipalIdentity: currentAuthPrincipalIdentity(),
            workspaceIdentity: currentWorkspaceIdentity(),
            snapshotFingerprint: currentAuthFingerprint(),
            remoteIdentity: currentRemoteIdentity()
        )
    }
}

extension CodexAuthSnapshotService: StoredAccountIdentityReconciler {}

struct SavedAccountIdentityResolver: Sendable {
    private let liveIdentitySource: LiveCodexAccountIdentitySource
    private let storedAccountReconciler: StoredAccountIdentityReconciler
    private let accountMatcher: CodexAccountMatcher

    init(
        liveIdentitySource: LiveCodexAccountIdentitySource,
        storedAccountReconciler: StoredAccountIdentityReconciler,
        accountMatcher: CodexAccountMatcher = CodexAccountMatcher()
    ) {
        self.liveIdentitySource = liveIdentitySource
        self.storedAccountReconciler = storedAccountReconciler
        self.accountMatcher = accountMatcher
    }

    func reconcileStoredAccounts(_ accounts: [CodexAccount]) -> [CodexAccount] {
        storedAccountReconciler.reconcileStoredAccountIdentities(accounts)
    }

    func readCurrentLiveIdentity() -> LiveCodexAccountIdentity {
        liveIdentitySource.readCurrentLiveAccountIdentity()
    }

    func resolve(
        accounts: [CodexAccount],
        liveRemoteIdentity: CodexRemoteAccountIdentity? = nil
    ) -> CodexAccountMatchOutcome {
        resolve(
            liveIdentity: readCurrentLiveIdentity(),
            accounts: accounts,
            liveRemoteIdentity: liveRemoteIdentity
        )
    }

    func resolve(
        liveIdentity: LiveCodexAccountIdentity,
        accounts: [CodexAccount],
        liveRemoteIdentity: CodexRemoteAccountIdentity? = nil
    ) -> CodexAccountMatchOutcome {
        accountMatcher.match(
            liveStableAccountID: liveIdentity.stableAccountID,
            liveAuthPrincipalIdentity: liveIdentity.authPrincipalIdentity,
            liveWorkspaceIdentity: liveIdentity.workspaceIdentity,
            liveAuthFingerprint: liveIdentity.snapshotFingerprint,
            liveRemoteIdentity: liveRemoteIdentity ?? liveIdentity.remoteIdentity,
            accounts: accounts
        )
    }

    func resolveCurrentAccountID(
        accounts: [CodexAccount],
        liveRemoteIdentity: CodexRemoteAccountIdentity? = nil
    ) -> UUID? {
        resolve(
            accounts: accounts,
            liveRemoteIdentity: liveRemoteIdentity
        ).matchedAccountID
    }
}
