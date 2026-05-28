import Foundation

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

    init(account: CodexAccount) {
        self.init(
            stableAccountID: account.identity.stableAccountID,
            authPrincipalIdentity: account.identity.authPrincipalIdentity,
            workspaceIdentity: account.identity.workspaceIdentity,
            snapshotFingerprint: account.identity.snapshotFingerprint,
            remoteIdentity: account.resolvedRemoteIdentity
        )
    }

    static let empty = Self()
}

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

    func resolve(
        accounts: [CodexAccount],
        liveRemoteIdentity: CodexRemoteAccountIdentity? = nil
    ) -> CodexAccountMatchOutcome {
        resolve(
            liveIdentity: liveIdentitySource.readCurrentLiveAccountIdentity(),
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

    func resolveSavedAccountID(
        for account: CodexAccount,
        among accounts: [CodexAccount],
        liveRemoteIdentity: CodexRemoteAccountIdentity? = nil
    ) -> UUID? {
        resolve(
            liveIdentity: LiveCodexAccountIdentity(account: account),
            accounts: accounts,
            liveRemoteIdentity: liveRemoteIdentity
        ).matchedAccountID
    }
}
