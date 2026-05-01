import Foundation
import Observation

@MainActor
@Observable
final class MenuDisplaySettingsStore {
    var refreshIntervalMinutes: Int {
        didSet {
            userDefaults.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey)
        }
    }

    var visibleInactiveAccountCount: Int {
        didSet {
            userDefaults.set(visibleInactiveAccountCount, forKey: Self.visibleInactiveAccountCountKey)
        }
    }

    let refreshIntervalOptions = [1, 2, 5, 10, 15, 30]
    let visibleInactiveAccountCountOptions = [2, 3, 5, 0]

    private let userDefaults: UserDefaults

    private static let refreshIntervalKey = "refreshIntervalMinutes"
    private static let visibleInactiveAccountCountKey = "visibleInactiveAccountCount"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedRefreshInterval = userDefaults.integer(forKey: Self.refreshIntervalKey)
        refreshIntervalMinutes = refreshIntervalOptions.contains(storedRefreshInterval) ? storedRefreshInterval : 5

        let storedVisibleInactiveAccountCount = userDefaults.object(forKey: Self.visibleInactiveAccountCountKey) as? Int
        let visibleAccountOptions = visibleInactiveAccountCountOptions
        if let storedVisibleInactiveAccountCount,
           visibleAccountOptions.contains(storedVisibleInactiveAccountCount) {
            visibleInactiveAccountCount = storedVisibleInactiveAccountCount
        } else {
            visibleInactiveAccountCount = 5
        }
    }
}
