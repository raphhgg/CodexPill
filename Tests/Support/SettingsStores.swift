import Foundation

@testable import Refill

@MainActor
struct SettingsStores {
    let menuDisplaySettings: MenuDisplaySettingsStore
    let statusItemSettings: StatusItemSettingsStore
    let tokenUsagePreferences: TokenUsagePreferencesStore
    let claudeUsageSettings: ClaudeUsageSettingsStore
    let appIconPreferences: AppIconPreferencesStore

    init(userDefaults: UserDefaults) {
        menuDisplaySettings = MenuDisplaySettingsStore(userDefaults: userDefaults)
        statusItemSettings = StatusItemSettingsStore(userDefaults: userDefaults)
        tokenUsagePreferences = TokenUsagePreferencesStore(userDefaults: userDefaults)
        claudeUsageSettings = ClaudeUsageSettingsStore(userDefaults: userDefaults)
        appIconPreferences = AppIconPreferencesStore(userDefaults: userDefaults)
    }
}
