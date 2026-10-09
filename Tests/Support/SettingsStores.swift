import Foundation

@testable import CodexPill

@MainActor
struct SettingsStores {
    let menuDisplaySettings: MenuDisplaySettingsStore
    let statusItemSettings: StatusItemSettingsStore
    let remoteHostSettings: RemoteHostSettingsStore
    let notificationPreferences: NotificationPreferencesStore
    let notificationState: NotificationStateStore
    let tokenUsagePreferences: TokenUsagePreferencesStore

    init(userDefaults: UserDefaults) {
        menuDisplaySettings = MenuDisplaySettingsStore(userDefaults: userDefaults)
        statusItemSettings = StatusItemSettingsStore(userDefaults: userDefaults)
        remoteHostSettings = RemoteHostSettingsStore(userDefaults: userDefaults)
        notificationPreferences = NotificationPreferencesStore(userDefaults: userDefaults)
        notificationState = NotificationStateStore(userDefaults: userDefaults)
        tokenUsagePreferences = TokenUsagePreferencesStore(userDefaults: userDefaults)
    }
}
