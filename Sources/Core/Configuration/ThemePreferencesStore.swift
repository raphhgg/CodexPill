import Foundation
import Observation

@MainActor
@Observable
final class ThemePreferencesStore {
    var theme: AppTheme {
        didSet {
            userDefaults.set(theme.rawValue, forKey: Self.themeKey)
            if let iconColor = theme.iconColor {
                appIconColor = iconColor
            }
        }
    }

    /// The icon in use. Tool Colors has no icon of its own, so it keeps the last one.
    private(set) var appIconColor: AppIconColor {
        didSet {
            userDefaults.set(appIconColor.rawValue, forKey: Self.appIconColorKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let themeKey = "appTheme"
    private static let appIconColorKey = "appIconColor"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let iconColor = userDefaults.string(forKey: Self.appIconColorKey)
            .flatMap(AppIconColor.init(rawValue:)) ?? .defaultColor
        appIconColor = iconColor
        // Before themes there was only the icon color, so the first theme matches it.
        theme = userDefaults.string(forKey: Self.themeKey).flatMap(AppTheme.init(rawValue:))
            ?? AppTheme.allCases.first { $0.iconColor == iconColor }
            ?? .defaultTheme
    }
}
