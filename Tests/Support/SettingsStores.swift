import Foundation

@testable import RUsage

@MainActor
struct SettingsStores {
    let menuDisplaySettings: MenuDisplaySettingsStore
    let statusItemSettings: StatusItemSettingsStore
    let tokenUsagePreferences: TokenUsagePreferencesStore
    let claudeUsageSettings: ClaudeUsageSettingsStore
    let themePreferences: ThemePreferencesStore

    init(userDefaults: UserDefaults) {
        menuDisplaySettings = MenuDisplaySettingsStore(userDefaults: userDefaults)
        statusItemSettings = StatusItemSettingsStore(userDefaults: userDefaults)
        tokenUsagePreferences = TokenUsagePreferencesStore(userDefaults: userDefaults)
        claudeUsageSettings = ClaudeUsageSettingsStore(userDefaults: userDefaults)
        themePreferences = ThemePreferencesStore(userDefaults: userDefaults)
    }
}
