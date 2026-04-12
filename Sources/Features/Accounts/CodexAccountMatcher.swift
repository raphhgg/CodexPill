import Foundation

enum CodexAccountMatchOutcome: Equatable {
    case exactStableAccountID(UUID)
    case exactSnapshot(UUID)
    case uniqueRemoteIdentity(UUID)
    case ambiguousStableAccountID([UUID])
    case ambiguousSnapshotFingerprint([UUID])
    case ambiguousRemoteIdentity([UUID])
    case noMatch

    var matchedAccountID: UUID? {
        switch self {
        case .exactStableAccountID(let id), .exactSnapshot(let id), .uniqueRemoteIdentity(let id):
            return id
        case .ambiguousStableAccountID, .ambiguousSnapshotFingerprint, .ambiguousRemoteIdentity, .noMatch:
            return nil
        }
    }
}

struct CodexAccountMatcher {
    func match(
        liveStableAccountID: String?,
        liveAuthFingerprint: String?,
        liveRemoteIdentity: CodexRemoteAccountIdentity?,
        accounts: [CodexAccount]
    ) -> CodexAccountMatchOutcome {
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
            return .noMatch
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
            return .noMatch
        }
    }

    private func uuidSort(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
