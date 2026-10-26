import Observation

/// What the Settings window shows that isn't a stored setting. The coordinator keeps it current as it rebuilds the
/// menu, so the window and the menu agree.
@MainActor
@Observable
final class SettingsWindowState {
    /// The tools with a card in the menu.
    var shownTools: [UsageProvider] = []
    var loginItemState = LoginItemState.unavailable
    /// The menu bar shows text only once the first tool has a reading.
    var canShowMenuBarText = false
    var isBusy = false
    /// Claude's settings change off the main actor too, so they aren't observed; this copy is.
    var showsModelLimits = true

    func update(from state: MenuBarMenuState) {
        let shownTools = state.toolSections.map(\.provider)
        if self.shownTools != shownTools { self.shownTools = shownTools }
        if loginItemState != state.loginItemState { loginItemState = state.loginItemState }
        if canShowMenuBarText != state.hasStatusItemContentData { canShowMenuBarText = state.hasStatusItemContentData }
        if isBusy != state.isBusy { isBusy = state.isBusy }
        if showsModelLimits != state.showsModelLimits { showsModelLimits = state.showsModelLimits }
    }
}

/// The Settings window's changes that do more than store a value: they prompt, start or stop work, or reach the
/// system. Settings that only store a value bind straight to `SettingsModel`.
@MainActor
protocol SettingsActions: AnyObject {
    /// Through the tool's connect and disconnect actions, so their prompts still show.
    func setTool(_ provider: UsageProvider, shown: Bool)
    func setLaunchAtLogin(_ isOn: Bool)
    func openLoginItemsSettings()
    func recordRevealShortcut()
    func setTokenUsageEnabled(_ isOn: Bool)
    func setShowsModelLimits(_ isOn: Bool)
    /// Login items change in System Settings, so the window rereads them when it comes forward.
    func settingsWindowDidBecomeKey()
}
