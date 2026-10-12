import Foundation

@testable import CodexPill

@MainActor
struct SettingsStores {
    let menuDisplaySettings: MenuDisplaySettingsStore
    let statusItemSettings: StatusItemSettingsStore
    let tokenUsagePreferences: TokenUsagePreferencesStore
    let claudeUsageSettings: ClaudeUsageSettingsStore

    init(userDefaults: UserDefaults) {
        menuDisplaySettings = MenuDisplaySettingsStore(userDefaults: userDefaults)
        statusItemSettings = StatusItemSettingsStore(userDefaults: userDefaults)
        tokenUsagePreferences = TokenUsagePreferencesStore(userDefaults: userDefaults)
        claudeUsageSettings = ClaudeUsageSettingsStore(userDefaults: userDefaults)
    }
}
