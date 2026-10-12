import Foundation

/// What the menu shows for one provider. It never reaches account availability, ranking, or notifications.
struct ProviderUsageState: Equatable {
    let provider: UsageProvider
    let status: ProviderUsageStatus
}

enum ProviderUsageStatus: Equatable {
    case notConnected
    case unavailable(UsageUnavailableReason)
    case awaitingUsage
    case current(UsageSnapshot)
    case stale(UsageSnapshot)

    init(_ reading: UsageProviderReading, at now: Date, staleAfter: TimeInterval) {
        switch reading {
        case .notConnected:
            self = .notConnected
        case let .unavailable(reason):
            self = .unavailable(reason)
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
