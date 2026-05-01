import Foundation
import Observation

@MainActor
@Observable
final class NotificationPreferencesStore {
    var notificationsWhenBlockedEnabled: Bool {
        didSet {
            userDefaults.set(notificationsWhenBlockedEnabled, forKey: Self.notificationsWhenBlockedEnabledKey)
        }
    }

    var notificationsWhenOutEnabled: Bool {
        didSet {
            userDefaults.set(notificationsWhenOutEnabled, forKey: Self.notificationsWhenOutEnabledKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let notificationsWhenBlockedEnabledKey = "notificationsWhenBlockedEnabled"
    private static let notificationsWhenOutEnabledKey = "notificationsWhenOutEnabled"
    private static let legacyNotificationsBeforeYouRunOutEnabledKey = "notificationsBeforeYouRunOutEnabled"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        notificationsWhenBlockedEnabled = userDefaults.bool(forKey: Self.notificationsWhenBlockedEnabledKey)
        notificationsWhenOutEnabled = userDefaults.object(forKey: Self.notificationsWhenOutEnabledKey) as? Bool
            ?? userDefaults.bool(forKey: Self.legacyNotificationsBeforeYouRunOutEnabledKey)
    }
}
