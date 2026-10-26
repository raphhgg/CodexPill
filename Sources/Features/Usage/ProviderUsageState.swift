import Foundation

/// What the menu shows for one tool other than Codex. It never reaches Codex account availability or ranking.
struct ProviderUsageState: Equatable {
    let provider: UsageProvider
    let status: ProviderUsageStatus
    /// Whether the menu can offer rusage's own sign-in for this tool, and which way.
    var ownSignIn: ProviderOwnSignIn = .unsupported
    /// False while the user hid the tool's card. It stays connected.
    var isShown = true
}

enum ProviderUsageStatus: Equatable {
    case notConnected
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
