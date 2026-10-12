import Foundation
import Observation

@MainActor
@Observable
final class AppIconPreferencesStore {
    var appIconColor: AppIconColor {
        didSet {
            userDefaults.set(appIconColor.rawValue, forKey: Self.appIconColorKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let appIconColorKey = "appIconColor"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        appIconColor = userDefaults.string(forKey: Self.appIconColorKey)
            .flatMap(AppIconColor.init(rawValue:)) ?? .defaultColor
    }
}
