import Foundation

enum CodexAccountMatchOutcome: Equatable {
    case exactScopedStableAccountID(UUID)
    case exactStableAccountID(UUID)
    case exactSnapshot(UUID)
    case uniqueRemoteIdentity(UUID)
    case ambiguousScopedStableAccountID([UUID])
    case ambiguousStableAccountID([UUID])
    case ambiguousSnapshotFingerprint([UUID])
    case ambiguousRemoteIdentity([UUID])
    case noMatch

    var matchedAccountID: UUID? {
        switch self {
        case .exactScopedStableAccountID(let id), .exactStableAccountID(let id), .exactSnapshot(let id), .uniqueRemoteIdentity(let id):
            return id
        case .ambiguousScopedStableAccountID, .ambiguousStableAccountID, .ambiguousSnapshotFingerprint, .ambiguousRemoteIdentity, .noMatch:
            return nil
        }
    }

    var isSafeForOverwrite: Bool {
        switch self {
        case .exactScopedStableAccountID, .exactStableAccountID, .exactSnapshot:
            return true
        case .uniqueRemoteIdentity, .ambiguousScopedStableAccountID, .ambiguousStableAccountID, .ambiguousSnapshotFingerprint, .ambiguousRemoteIdentity, .noMatch:
            return false
        }
    }
}

struct CodexAccountMatcher: Sendable {
    func match(
        liveStableAccountID: String?,
        liveAuthPrincipalIdentity: CodexAuthPrincipalIdentity?,
        liveWorkspaceIdentity: CodexWorkspaceIdentity?,
        liveAuthFingerprint: String?,
        liveRemoteIdentity: CodexRemoteAccountIdentity?,
        accounts: [CodexAccount]
    ) -> CodexAccountMatchOutcome {
        let scopedStableMatch = matchScopedStableAccountID(
            liveStableAccountID: liveStableAccountID,
            liveAuthPrincipalIdentity: liveAuthPrincipalIdentity,
            liveWorkspaceIdentity: liveWorkspaceIdentity,
            accounts: accounts
        )

        if let scopedStableMatch,
           scopedStableMatch != .noMatch {
            return scopedStableMatch
        }

        if scopedStableMatch == .noMatch {
            return .noMatch
        }

        if let liveStableAccountID {
            let stableMatches = accounts
                .filter { $0.identity.stableAccountID == liveStableAccountID }
                .map(\.id)

            switch stableMatches.count {
            case 1:
                return .exactStableAccountID(stableMatches[0])
            case let count where count > 1:
                return .ambiguousStableAccountID(stableMatches.sorted(by: uuidSort))
            default:
                break
            }
        }

        if let liveAuthFingerprint {
            let snapshotMatches = accounts
                .filter { $0.identity.snapshotFingerprint == liveAuthFingerprint }
                .map(\.id)

            switch snapshotMatches.count {
            case 1:
                return .exactSnapshot(snapshotMatches[0])
            case let count where count > 1:
                return .ambiguousSnapshotFingerprint(snapshotMatches.sorted(by: uuidSort))
            default:
                break
            }
        }

        guard let liveRemoteIdentity else {
            return scopedStableMatch ?? .noMatch
        }

        let remoteMatches = accounts
            .filter { $0.resolvedRemoteIdentity == liveRemoteIdentity }
            .map(\.id)

        switch remoteMatches.count {
        case 1:
            return .uniqueRemoteIdentity(remoteMatches[0])
        case let count where count > 1:
            return .ambiguousRemoteIdentity(remoteMatches.sorted(by: uuidSort))
        default:
            return scopedStableMatch ?? .noMatch
        }
    }

    private func uuidSort(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    private func matchScopedStableAccountID(
        liveStableAccountID: String?,
        liveAuthPrincipalIdentity: CodexAuthPrincipalIdentity?,
        liveWorkspaceIdentity: CodexWorkspaceIdentity?,
        accounts: [CodexAccount]
    ) -> CodexAccountMatchOutcome? {
        guard let liveStableAccountID else { return nil }

        let stableAccounts = accounts.filter { $0.identity.stableAccountID == liveStableAccountID }
        guard !stableAccounts.isEmpty else { return nil }

        let hasScopedStableCandidates = stableAccounts.contains {
            ($0.identity.authPrincipalIdentity?.isMeaningful ?? false) ||
                ($0.identity.workspaceIdentity?.isMeaningful ?? false)
        }

        if let liveAuthPrincipalIdentity,
           liveAuthPrincipalIdentity.isMeaningful {
            let principalMatches = stableAccounts
                .filter { $0.identity.authPrincipalIdentity == liveAuthPrincipalIdentity }
                .map(\.id)

            switch principalMatches.count {
            case 1:
                return .exactScopedStableAccountID(principalMatches[0])
            case let count where count > 1:
                return .ambiguousScopedStableAccountID(principalMatches.sorted(by: uuidSort))
            default:
                if hasScopedStableCandidates {
                    return .noMatch
                }
            }
        }

        if let liveWorkspaceIdentity,
           liveWorkspaceIdentity.isMeaningful {
            let workspaceMatches = stableAccounts
                .filter { $0.identity.workspaceIdentity == liveWorkspaceIdentity }
                .map(\.id)

            switch workspaceMatches.count {
            case 1:
                return .exactScopedStableAccountID(workspaceMatches[0])
            case let count where count > 1:
                return .ambiguousScopedStableAccountID(workspaceMatches.sorted(by: uuidSort))
            default:
                if hasScopedStableCandidates {
                    return .noMatch
                }
            }
        }

        return nil
    }
}
