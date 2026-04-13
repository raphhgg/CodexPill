import Foundation

struct LiveCodexAccountIdentity: Equatable {
    let stableAccountID: String?
    let authPrincipalIdentity: CodexAuthPrincipalIdentity?
    let workspaceIdentity: CodexWorkspaceIdentity?
    let snapshotFingerprint: String?

    init(
        stableAccountID: String? = nil,
        authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil,
        workspaceIdentity: CodexWorkspaceIdentity? = nil,
        snapshotFingerprint: String? = nil
    ) {
        self.stableAccountID = stableAccountID
        self.authPrincipalIdentity = authPrincipalIdentity
        self.workspaceIdentity = workspaceIdentity
        self.snapshotFingerprint = snapshotFingerprint
    }

    init(account: CodexAccount) {
        self.init(
            stableAccountID: account.identity.stableAccountID,
            authPrincipalIdentity: account.identity.authPrincipalIdentity,
            workspaceIdentity: account.identity.workspaceIdentity,
            snapshotFingerprint: account.identity.snapshotFingerprint
        )
    }

    static let empty = Self()
}

protocol LiveCodexAccountIdentityReading {
    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity
}

protocol StoredAccountIdentityReconciling {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount]
}

extension CodexAuthSnapshotService: LiveCodexAccountIdentityReading {
    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(
            stableAccountID: currentStableAccountID(),
            authPrincipalIdentity: currentAuthPrincipalIdentity(),
            workspaceIdentity: currentWorkspaceIdentity(),
            snapshotFingerprint: currentAuthFingerprint()
        )
    }
}

extension CodexAuthSnapshotService: StoredAccountIdentityReconciling {}

struct SavedAccountIdentityResolver {
    private let liveIdentityReader: LiveCodexAccountIdentityReading
    private let storedAccountReconciler: StoredAccountIdentityReconciling
    private let accountMatcher: CodexAccountMatcher

    init(
        liveIdentityReader: LiveCodexAccountIdentityReading,
        storedAccountReconciler: StoredAccountIdentityReconciling,
        accountMatcher: CodexAccountMatcher = CodexAccountMatcher()
    ) {
        self.liveIdentityReader = liveIdentityReader
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
            liveIdentity: liveIdentityReader.readCurrentLiveAccountIdentity(),
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
            liveRemoteIdentity: liveRemoteIdentity,
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
