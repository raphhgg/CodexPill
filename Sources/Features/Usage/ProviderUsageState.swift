import Foundation

/// What the menu shows for one provider. It never reaches account availability, ranking, or notifications.
struct ProviderUsageState: Equatable {
    let provider: UsageProvider
    let status: ProviderUsageStatus
}

enum ProviderUsageStatus: Equatable {
    case notConnected
    /// The user started a browser sign-in that has not finished yet.
    case signingIn
    /// `lastSnapshot` is the last good reading, kept so the menu can still show it with its time.
    case unavailable(UsageUnavailableReason, lastSnapshot: UsageSnapshot?)
    case awaitingUsage
    case current(UsageSnapshot)
    case stale(UsageSnapshot)

    init(_ reading: UsageProviderReading, lastSnapshot: UsageSnapshot?, at now: Date, staleAfter: TimeInterval) {
        switch reading {
        case .notConnected:
            self = .notConnected
        case let .unavailable(reason):
            self = .unavailable(reason, lastSnapshot: lastSnapshot)
        case .awaitingUsage:
            self = .awaitingUsage
        case let .snapshot(snapshot):
            switch snapshot.freshness(at: now, staleAfter: staleAfter) {
            case .fresh: self = .current(snapshot)
            case .stale: self = .stale(snapshot)
            }
        }
    }
}
