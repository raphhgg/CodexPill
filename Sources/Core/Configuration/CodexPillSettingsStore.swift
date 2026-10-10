import Foundation
import Observation

@MainActor
@Observable
final class CodexPillSettingsStore {
    let menuDisplaySettings: MenuDisplaySettingsStore
    let statusItemSettings: StatusItemSettingsStore
    let tokenUsagePreferences: TokenUsagePreferencesStore

    init(userDefaults: UserDefaults = .standard) {
        menuDisplaySettings = MenuDisplaySettingsStore(userDefaults: userDefaults)
        statusItemSettings = StatusItemSettingsStore(userDefaults: userDefaults)
        tokenUsagePreferences = TokenUsagePreferencesStore(userDefaults: userDefaults)
    }

    var refreshIntervalMinutes: Int {
        get { menuDisplaySettings.refreshIntervalMinutes }
        set { menuDisplaySettings.refreshIntervalMinutes = newValue }
    }

    var visibleInactiveAccountCount: Int {
        get { menuDisplaySettings.visibleInactiveAccountCount }
        set { menuDisplaySettings.visibleInactiveAccountCount = newValue }
    }

    var statusBarIndicatorStyle: StatusBarIndicatorStyle {
        get { statusItemSettings.statusBarIndicatorStyle }
        set { statusItemSettings.statusBarIndicatorStyle = newValue }
    }

    var statusBarMonochrome: Bool {
        get { statusItemSettings.statusBarMonochrome }
        set { statusItemSettings.statusBarMonochrome = newValue }
    }

    var statusBarDisplayMode: StatusBarDisplayMode {
        get { statusItemSettings.statusBarDisplayMode }
        set { statusItemSettings.statusBarDisplayMode = newValue }
    }

    var progressAccentColor: StatusItemAccentColor? {
        get { statusItemSettings.progressAccentColor }
        set { statusItemSettings.progressAccentColor = newValue }
    }

    var pacingMarkersEnabled: Bool {
        get { statusItemSettings.pacingMarkersEnabled }
        set { statusItemSettings.pacingMarkersEnabled = newValue }
    }

    var revealStatusItemTitleShortcut: KeyboardShortcut? {
        get { statusItemSettings.revealStatusItemTitleShortcut }
        set { statusItemSettings.revealStatusItemTitleShortcut = newValue }
    }

    var hasCustomProgressAccentColor: Bool {
        statusItemSettings.hasCustomProgressAccentColor
    }

    var tokenUsageEnabled: Bool {
        get { tokenUsagePreferences.isEnabled }
        set { tokenUsagePreferences.isEnabled = newValue }
    }

    var tokenUsagePeriod: CodexTokenUsagePeriod {
        get { tokenUsagePreferences.period }
        set { tokenUsagePreferences.period = newValue }
    }

    var tokenUsageChartStyle: TokenUsageChartStyle {
        get { tokenUsagePreferences.chartStyle }
        set { tokenUsagePreferences.chartStyle = newValue }
    }

    var tokenUsageLoadingAnimationStyle: TokenUsageLoadingAnimationStyle {
        get { tokenUsagePreferences.loadingAnimationStyle }
        set { tokenUsagePreferences.loadingAnimationStyle = newValue }
    }

    var tokenUsagePeakScope: TokenUsagePeakScope {
        get { tokenUsagePreferences.peakScope }
        set { tokenUsagePreferences.peakScope = newValue }
    }

    var refreshIntervalOptions: [Int] {
        menuDisplaySettings.refreshIntervalOptions
    }

    var visibleInactiveAccountCountOptions: [Int] {
        menuDisplaySettings.visibleInactiveAccountCountOptions
    }

    func resetProgressAccentColor() {
        statusItemSettings.resetProgressAccentColor()
    }
}
