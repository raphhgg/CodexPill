import Foundation

/// Reads usage for one provider other than Codex. Codex usage lives on `CodexAccount`.
protocol UsageProviderSource: Sendable {
    var provider: UsageProvider { get }
    /// How old a snapshot may be before the menu shows it as stale.
    var staleAfter: TimeInterval { get }
    /// The shortest time between two reads.
    var refreshInterval: TimeInterval { get }

    func readUsage(now: Date) async -> UsageProviderReading
}

extension UsageProviderSource {
    var refreshInterval: TimeInterval { ProviderUsageRuntime.refreshInterval }
}

enum UsageProviderReading: Equatable, Sendable {
    /// CodexPill is not connected to the provider, so the menu offers to connect it.
    case notConnected
    case unavailable(UsageUnavailableReason)
    /// Connected, but the provider has not reported any usage windows yet.
    case awaitingUsage
    case snapshot(UsageSnapshot)
}

enum UsageUnavailableReason: Equatable, Sendable {
    case signedOut
    case signInExpired
    /// The sign-in exists, but macOS needs the user to allow CodexPill to read it.
    case keychainAccessNeeded
    case readFailed

    /// The last good numbers stay on screen only while they still belong to the same signed-in account.
    var keepsLastSnapshot: Bool {
        switch self {
        case .signedOut: false
        case .signInExpired, .keychainAccessNeeded, .readFailed: true
        }
    }
}
