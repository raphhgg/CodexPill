import Foundation
import Observation

@MainActor
@Observable
final class CodexPillSettingsStore {
    let menuDisplaySettings: MenuDisplaySettingsStore
    let statusItemSettings: StatusItemSettingsStore
    let remoteHostSettings: RemoteHostSettingsStore
    let notificationPreferences: NotificationPreferencesStore
    let notificationState: NotificationStateStore
    let tokenUsagePreferences: TokenUsagePreferencesStore

    init(userDefaults: UserDefaults = .standard) {
        menuDisplaySettings = MenuDisplaySettingsStore(userDefaults: userDefaults)
        statusItemSettings = StatusItemSettingsStore(userDefaults: userDefaults)
        remoteHostSettings = RemoteHostSettingsStore(userDefaults: userDefaults)
        notificationPreferences = NotificationPreferencesStore(userDefaults: userDefaults)
        notificationState = NotificationStateStore(userDefaults: userDefaults)
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

    var remoteHostStates: [PersistedRemoteHostState] {
        get { remoteHostSettings.remoteHostStates }
        set { remoteHostSettings.remoteHostStates = newValue }
    }

    var configuredRemoteHost: RemoteHost? {
        get { remoteHostSettings.configuredRemoteHost }
        set { remoteHostSettings.configuredRemoteHost = newValue }
    }

    var remoteHostInstalledAccountIDs: [UUID] {
        get { remoteHostSettings.remoteHostInstalledAccountIDs }
        set { remoteHostSettings.remoteHostInstalledAccountIDs = newValue }
    }

    var remoteHostActiveAccount: CodexAccount? {
        get { remoteHostSettings.remoteHostActiveAccount }
        set { remoteHostSettings.remoteHostActiveAccount = newValue }
    }

    var remoteHostDesiredAccountID: UUID? {
        get { remoteHostSettings.remoteHostDesiredAccountID }
        set { remoteHostSettings.remoteHostDesiredAccountID = newValue }
    }

    var notificationsWhenBlockedEnabled: Bool {
        get { notificationPreferences.notificationsWhenBlockedEnabled }
        set { notificationPreferences.notificationsWhenBlockedEnabled = newValue }
    }

    var notificationsWhenOutEnabled: Bool {
        get { notificationPreferences.notificationsWhenOutEnabled }
        set { notificationPreferences.notificationsWhenOutEnabled = newValue }
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

    var accountNotificationStates: [PersistedAccountNotificationState] {
        get { notificationState.accountNotificationStates }
        set { notificationState.accountNotificationStates = newValue }
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

    func upsertRemoteHost(_ host: RemoteHost) {
        remoteHostSettings.upsertRemoteHost(host)
    }

    func removeRemoteHost(destination: String) {
        remoteHostSettings.removeRemoteHost(destination: destination)
    }

    func remoteHostState(for destination: String) -> PersistedRemoteHostState? {
        remoteHostSettings.remoteHostState(for: destination)
    }

    func updateRemoteHostState(for host: RemoteHost, mutate: (inout PersistedRemoteHostState) -> Void) {
        remoteHostSettings.updateRemoteHostState(for: host, mutate: mutate)
    }

    func accountNotificationState(for accountID: UUID) -> PersistedAccountNotificationState? {
        notificationState.accountNotificationState(for: accountID)
    }

    func updateAccountNotificationState(
        for accountID: UUID,
        mutate: (inout PersistedAccountNotificationState) -> Void
    ) {
        notificationState.updateAccountNotificationState(for: accountID, mutate: mutate)
    }
}
