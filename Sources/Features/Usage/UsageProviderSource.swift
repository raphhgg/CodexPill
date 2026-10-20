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
    /// rusage is not connected to the provider, so the menu offers to connect it.
    case notConnected
    case unavailable(UsageUnavailableReason)
    /// Connected, but the provider has not reported any usage windows yet.
    case awaitingUsage
    case snapshot(UsageSnapshot)
}

/// Why a connected provider shows no current usage. Each case has its own menu copy.
enum UsageUnavailableReason: Equatable, Sendable {
    /// The provider's app is not on this Mac.
    case notInstalled
    case signedOut
    /// The sign-in is past its expiry, or the provider rejected it (HTTP 401).
    case signInExpired
    /// rusage's own sign-in is gone or was rejected. Only a new sign-in helps.
    case signInRequired
    /// The sign-in exists, but macOS needs the user to allow rusage to read it.
    case keychainAccessNeeded
    /// The sign-in exists but could not be read or parsed.
    case signInUnreadable
    /// The provider's app is writing its sign-in right now. The next read usually works.
    case signInBusy
    /// The provider knows the sign-in but refuses to share usage with it (HTTP 403).
    case accessDenied
    /// The provider asked rusage to slow down (HTTP 429).
    case rateLimited
    /// No answer at all: offline, DNS, TLS, or a timeout.
    case unreachable
    /// The provider answered with a server error or another unexpected status.
    case serviceError
    /// The provider answered, but not in the shape rusage reads.
    case unexpectedResponse

    /// The last good numbers stay on screen only while they still belong to the same signed-in account. After a new
    /// sign-in is required, the next one may be another account.
    var keepsLastSnapshot: Bool {
        self != .signedOut && self != .notInstalled && self != .signInRequired
    }
}
