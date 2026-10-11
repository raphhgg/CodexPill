import Foundation

/// Whether Claude Code usage is connected: the user agreed that Refill may read Claude Code's sign-in and send it
/// to Anthropic to fetch limits. Off until they connect it. Account switching does not depend on it.
/// The usage source reads it off the main actor; `UserDefaults` is documented as thread-safe.
final class ClaudeUsageSettingsStore: @unchecked Sendable {
    private static let isEnabledKey = "claudeUsageEnabled"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: Self.isEnabledKey) }
        set { userDefaults.set(newValue, forKey: Self.isEnabledKey) }
    }
}
