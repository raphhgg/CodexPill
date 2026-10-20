import Foundation
import Observation

@MainActor
@Observable
final class ThemePreferencesStore {
    var theme: AppTheme {
        didSet {
            userDefaults.set(theme.rawValue, forKey: Self.themeKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let themeKey = "appTheme"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        theme = userDefaults.string(forKey: Self.themeKey).flatMap(AppTheme.init(rawValue:)) ?? .defaultTheme
    }
}
