import Foundation

enum RemoteHostSwitchVerificationResult: Equatable {
    case verified(CodexAccountStatus)
    case notVerified(CodexAccountMatchOutcome)
}

struct RemoteHostAccountVerifier {
    private let accountMatcher: CodexAccountMatcher

    init(accountMatcher: CodexAccountMatcher = CodexAccountMatcher()) {
        self.accountMatcher = accountMatcher
    }

    func verify(
        status: CodexAccountStatus,
        expectedAccount: CodexAccount,
        among accounts: [CodexAccount]
    ) -> RemoteHostSwitchVerificationResult {
        let candidates = candidateAccounts(including: expectedAccount, among: accounts)
        let matchOutcome = accountMatcher.match(
            liveStableAccountID: status.stableAccountID,
            liveAuthPrincipalIdentity: status.authPrincipalIdentity,
            liveWorkspaceIdentity: status.workspaceIdentity,
            liveAuthFingerprint: status.snapshotFingerprint,
            liveRemoteIdentity: status.remoteIdentity,
            accounts: candidates
        )

        guard matchOutcome.matchedAccountID == expectedAccount.id else {
            return .notVerified(matchOutcome)
        }

        switch matchOutcome {
        case .exactScopedStableAccountID, .exactStableAccountID, .exactSnapshot, .uniqueRemoteIdentity:
            return .verified(status)
        case .ambiguousScopedStableAccountID,
             .ambiguousStableAccountID,
             .ambiguousSnapshotFingerprint,
             .ambiguousRemoteIdentity,
             .noMatch:
            return .notVerified(matchOutcome)
        }
    }

    func failureMessage(
        for expectedAccount: CodexAccount,
        on host: RemoteHost,
        among accounts: [CodexAccount],
        matchOutcome: CodexAccountMatchOutcome
    ) -> String {
        let candidates = candidateAccounts(including: expectedAccount, among: accounts)

        switch matchOutcome {
        case .exactScopedStableAccountID(let id),
             .exactStableAccountID(let id),
             .exactSnapshot(let id),
             .uniqueRemoteIdentity(let id):
            if let matchedAccount = candidates.first(where: { $0.id == id }) {
                return "\(host.displayName) is using \(matchedAccount.name), not \(expectedAccount.name)."
            }
            return "\(host.displayName) did not switch to \(expectedAccount.name)."
        case .ambiguousScopedStableAccountID,
             .ambiguousStableAccountID,
             .ambiguousSnapshotFingerprint,
             .ambiguousRemoteIdentity:
            return "CodexPill could not verify that \(host.displayName) switched to \(expectedAccount.name) because the remote identity matched multiple saved accounts."
        case .noMatch:
            return "CodexPill could not verify that \(host.displayName) switched to \(expectedAccount.name)."
        }
    }

    private func candidateAccounts(including expectedAccount: CodexAccount, among accounts: [CodexAccount]) -> [CodexAccount] {
        if accounts.contains(where: { $0.id == expectedAccount.id }) {
            return accounts
        }
        return accounts + [expectedAccount]
    }
}
