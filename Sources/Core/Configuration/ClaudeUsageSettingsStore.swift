import Foundation

/// Whether Claude Code usage is connected: the user agreed that CodexPill may read Claude Code's sign-in and send it
/// to Anthropic to fetch limits. Off until they connect it. Account switching does not depend on it.
/// The usage source reads it off the main actor; `UserDefaults` is documented as thread-safe.
final class ClaudeUsageSettingsStore: @unchecked Sendable {
    private static let isEnabledKey = "claudeUsageEnabled"
    private static let showsModelLimitsKey = "claudeShowsModelLimits"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: Self.isEnabledKey) }
        set { userDefaults.set(newValue, forKey: Self.isEnabledKey) }
    }

    /// Whether the Claude card and saved accounts show per-model weekly limits, such as "Fable this week". On until
    /// the user turns it off.
    var showsModelLimits: Bool {
        get { userDefaults.object(forKey: Self.showsModelLimitsKey) as? Bool ?? true }
        set { userDefaults.set(newValue, forKey: Self.showsModelLimitsKey) }
    }
}
