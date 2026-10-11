import Foundation

/// Whether the user agreed to let Refill read Cursor's sign-in. Off until they connect Cursor.
/// The usage source reads it off the main actor; `UserDefaults` is documented as thread-safe.
final class CursorUsageSettingsStore: @unchecked Sendable {
    private static let isEnabledKey = "cursorUsageEnabled"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: Self.isEnabledKey) }
        set { userDefaults.set(newValue, forKey: Self.isEnabledKey) }
    }
}
