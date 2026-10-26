import Foundation
import Testing

@testable import RUsage

@MainActor
struct SettingsModelTests {
    @Test
    func changesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = SettingsModel(userDefaults: defaults)
        first.general.refreshIntervalMinutes = 10
        first.general.toolOrder = [.cursor, .claude, .codex]
        first.general.theme = .toolColors
        first.menuBar.revealStatusItemTitleShortcut = nil
        first.tokenUsage.chartStyle = .lines
        first.codex.isConnected = false
        first.claude.update { $0.showsModelLimits = false }
        first.cursor.update { $0.isConnected = true }

        let second = SettingsModel(userDefaults: defaults)

        #expect(second.general == first.general)
        #expect(second.menuBar.revealStatusItemTitleShortcut == nil)
        #expect(second.tokenUsage.chartStyle == .lines)
        #expect(!second.codex.isConnected)
        #expect(!second.claude.value.showsModelLimits)
        #expect(second.cursor.value.isConnected)
    }

    @Test
    func anUnchangedGroupIsNotSaved() {
        let defaults = makeDefaults()
        let settings = SettingsModel(userDefaults: defaults)

        settings.general = settings.general
        settings.claude.update { _ in }

        #expect(defaults.data(forKey: GeneralSettings.key) == nil)
        #expect(defaults.data(forKey: ClaudeSettings.key) == nil)
    }

    @Test
    func theWeeklyColorFollowsTheSessionColorUntilItIsSetApart() {
        let session = StatusItemAccentColor(red: 0.14, green: 0.55, blue: 0.31, alpha: 1)
        let weekly = StatusItemAccentColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1)
        var menuBar = MenuBarSettings.defaults
        menuBar.sessionAccentColor = session
        menuBar.weeklyAccentColor = weekly

        #expect(menuBar.effectiveWeeklyAccentColor == session)
        #expect(menuBar.hasCustomUsageColors)

        menuBar.usesOneUsageColor = false
        #expect(menuBar.effectiveWeeklyAccentColor == weekly)

        menuBar.resetUsageColors()
        #expect(menuBar == .defaults)
        #expect(!menuBar.hasCustomUsageColors)
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "SettingsModelTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
