import Foundation

/// Reads usage for one provider other than Codex. Codex usage lives on `CodexAccount`.
protocol UsageProviderSource: Sendable {
    var provider: UsageProvider { get }
    /// How old a snapshot may be before the menu shows it as stale.
    var staleAfter: TimeInterval { get }

    func readUsage(now: Date) async -> UsageProviderReading
}

enum UsageProviderReading: Equatable, Sendable {
    /// The provider is not set up on this Mac: no relay file, not signed in, or not installed.
    case notConnected
    case unavailable(UsageUnavailableReason)
    /// Connected, but the provider has not reported any usage windows yet.
    case awaitingUsage
    case snapshot(UsageSnapshot)
}

enum UsageUnavailableReason: Equatable, Sendable {
    case signInExpired
    case readFailed
}
