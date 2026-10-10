import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuDisplaySettingsStoreTests {
    @Test
    func preferencesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = MenuDisplaySettingsStore(userDefaults: defaults)
        first.refreshIntervalMinutes = 10
        first.visibleInactiveAccountCount = 0

        let second = MenuDisplaySettingsStore(userDefaults: defaults)

        #expect(second.refreshIntervalMinutes == 10)
        #expect(second.visibleInactiveAccountCount == 0)
    }

    @Test
    func invalidStoredValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(99, forKey: "refreshIntervalMinutes")
        defaults.set(99, forKey: "visibleInactiveAccountCount")

        let store = MenuDisplaySettingsStore(userDefaults: defaults)

        #expect(store.refreshIntervalMinutes == 5)
        #expect(store.visibleInactiveAccountCount == 5)
    }
}

@MainActor
struct StatusItemSettingsStoreTests {
    @Test(arguments: [
        ("notchedSquare", StatusBarIndicatorStyle.stackedBars),
        ("splitCapsule", StatusBarIndicatorStyle.twinPills)
    ])
    func legacyStyleAliasesMigrate(rawValue: String, expectedStyle: StatusBarIndicatorStyle) {
        let defaults = makeDefaults()
        defaults.set(rawValue, forKey: "statusBarIndicatorStyle")

        let store = StatusItemSettingsStore(userDefaults: defaults)

        #expect(store.statusBarIndicatorStyle == expectedStyle)
    }

    @Test
    func customAccentPersistsAndResetRemovesCustomColor() {
        let defaults = makeDefaults()
        let accent = StatusItemAccentColor(red: 0.14, green: 0.55, blue: 0.31, alpha: 1)

        let first = StatusItemSettingsStore(userDefaults: defaults)
        first.progressAccentColor = accent
        first.pacingMarkersEnabled = false

        let second = StatusItemSettingsStore(userDefaults: defaults)
        #expect(second.progressAccentColor == accent)
        #expect(second.hasCustomProgressAccentColor)
        #expect(!second.pacingMarkersEnabled)

        second.resetProgressAccentColor()

        let reset = StatusItemSettingsStore(userDefaults: defaults)
        #expect(reset.progressAccentColor == nil)
        #expect(!reset.hasCustomProgressAccentColor)
    }

    @Test
    func revealShortcutPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let shortcut = KeyboardShortcut(keyCode: 11, modifiers: [.control, .shift])

        let first = StatusItemSettingsStore(userDefaults: defaults)
        first.revealStatusItemTitleShortcut = shortcut

        let second = StatusItemSettingsStore(userDefaults: defaults)

        #expect(second.revealStatusItemTitleShortcut == shortcut)
    }

    @Test
    func revealShortcutCanBeCleared() {
        let defaults = makeDefaults()
        let first = StatusItemSettingsStore(userDefaults: defaults)
        first.revealStatusItemTitleShortcut = nil

        let second = StatusItemSettingsStore(userDefaults: defaults)

        #expect(second.revealStatusItemTitleShortcut == nil)
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "TypedSettingsStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
