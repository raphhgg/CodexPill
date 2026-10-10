import Foundation

/// The sign-in Claude usage reads with. Each connection uses exactly one, so CodexPill never shows the limits of an
/// account the user did not pick.
enum ClaudeSignInSource: String, Sendable {
    /// Claude Code's own sign-in, read only.
    case claudeCode
    /// CodexPill's own "Sign in with Claude", kept in CodexPill's Keychain item.
    case codexPill
}

/// Whether Claude usage is connected, and with which sign-in. Not connected until the user connects it. Account
/// switching does not depend on it.
/// The usage source reads it off the main actor; `UserDefaults` is documented as thread-safe.
final class ClaudeUsageSettingsStore: @unchecked Sendable {
    private static let isEnabledKey = "claudeUsageEnabled"
    private static let signInSourceKey = "claudeUsageSignInSource"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Nil when Claude is not connected. A connection saved before CodexPill had its own sign-in reads as Claude Code's.
    var connection: ClaudeSignInSource? {
        get {
            guard userDefaults.bool(forKey: Self.isEnabledKey) else { return nil }
            return userDefaults.string(forKey: Self.signInSourceKey).flatMap(ClaudeSignInSource.init(rawValue:)) ?? .claudeCode
        }
        set {
            userDefaults.set(newValue != nil, forKey: Self.isEnabledKey)
            userDefaults.set(newValue?.rawValue, forKey: Self.signInSourceKey)
        }
    }
}
