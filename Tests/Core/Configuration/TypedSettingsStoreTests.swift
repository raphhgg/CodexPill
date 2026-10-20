import Foundation
import Testing

@testable import rusage

@MainActor
struct MenuDisplaySettingsStoreTests {
    @Test
    func chartStylesFromBeforeThePerToolChartOpenAsBars() {
        let defaults = makeDefaults()
        for old in ["dailyBars", "heatStrip", "sparkline"] {
            defaults.set(old, forKey: "tokenUsageChartStyle")
            #expect(TokenUsagePreferencesStore(userDefaults: defaults).chartStyle == .bars)
        }
    }

    @Test
    func preferencesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = MenuDisplaySettingsStore(userDefaults: defaults)
        first.refreshIntervalMinutes = 10
        first.toolOrder = [.cursor, .claude, .codex]
        first.masksEmails = true

        let second = MenuDisplaySettingsStore(userDefaults: defaults)

        #expect(second.refreshIntervalMinutes == 10)
        #expect(second.toolOrder == [.cursor, .claude, .codex])
        #expect(second.masksEmails)
    }

    @Test
    func invalidStoredValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(99, forKey: "refreshIntervalMinutes")

        let store = MenuDisplaySettingsStore(userDefaults: defaults)

        #expect(store.refreshIntervalMinutes == 5)
        #expect(store.toolOrder == [.claude, .codex, .cursor])
        #expect(!store.masksEmails)
    }

    @Test
    func aPartialOrUnknownStoredOrderKeepsEveryToolOnce() {
        let defaults = makeDefaults()
        defaults.set(["cursor", "gemini", "cursor"], forKey: "toolOrder")

        let store = MenuDisplaySettingsStore(userDefaults: defaults)

        #expect(store.toolOrder == [.cursor, .claude, .codex])
    }
}

@MainActor
struct StatusItemSettingsStoreTests {
    @Test
    func defaultsUseCurrentStatusBarPreferences() {
        let store = StatusItemSettingsStore(userDefaults: makeDefaults())

        #expect(store.statusBarIndicatorStyle == .glasses)
        #expect(store.statusBarDisplayMode == .textOnHover)
        #expect(store.pacingMarkersEnabled)
        #expect(store.revealStatusItemTitleShortcut == .defaultRevealStatusItemTitle)
        #expect(store.sessionAccentColor == nil)
    }

    @Test(arguments: [
        ("dualArcBadge", StatusBarIndicatorStyle.moon),
        ("stackedBars", .punchCard),
        ("twinPills", .glasses),
        ("notchedSquare", .punchCard),
        ("splitCapsule", .glasses),
        ("hourglass", .glasses),
        ("moon", .moon),
        ("punchCard", .punchCard),
        ("somethingUnknown", .glasses)
    ])
    func storedStyleValuesMapToCurrentStyles(rawValue: String, expectedStyle: StatusBarIndicatorStyle) {
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
        first.sessionAccentColor = accent
        first.pacingMarkersEnabled = false

        let second = StatusItemSettingsStore(userDefaults: defaults)
        #expect(second.sessionAccentColor == accent)
        #expect(second.hasCustomUsageColors)
        #expect(!second.pacingMarkersEnabled)

        second.resetUsageColors()

        let reset = StatusItemSettingsStore(userDefaults: defaults)
        #expect(reset.sessionAccentColor == nil)
        #expect(!reset.hasCustomUsageColors)
    }

    @Test
    func existingAccentColorBecomesSessionAndWeeklyColor() throws {
        let defaults = makeDefaults()
        let accent = StatusItemAccentColor(red: 0.14, green: 0.55, blue: 0.31, alpha: 1)
        defaults.set(try JSONEncoder().encode(accent), forKey: "progressAccentColor")

        let store = StatusItemSettingsStore(userDefaults: defaults)

        #expect(store.sessionAccentColor == accent)
        #expect(store.effectiveWeeklyAccentColor == accent)
        #expect(store.usesOneUsageColor)
        #expect(store.usagePercentMode == .used)
        #expect(store.usageMeterLayout == .classic)
    }

    @Test
    func separateWeeklyColorPersistsAndSameColorOptionOverridesIt() {
        let defaults = makeDefaults()
        let session = StatusItemAccentColor(red: 0.14, green: 0.55, blue: 0.31, alpha: 1)
        let weekly = StatusItemAccentColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1)

        let first = StatusItemSettingsStore(userDefaults: defaults)
        first.sessionAccentColor = session
        first.weeklyAccentColor = weekly
        first.usesOneUsageColor = false
        first.usagePercentMode = .left
        first.usageMeterLayout = .compact

        let second = StatusItemSettingsStore(userDefaults: defaults)
        #expect(second.effectiveWeeklyAccentColor == weekly)
        #expect(second.usagePercentMode == .left)
        #expect(second.usageMeterLayout == .compact)

        second.usesOneUsageColor = true
        #expect(StatusItemSettingsStore(userDefaults: defaults).effectiveWeeklyAccentColor == session)

        second.resetUsageColors()
        let reset = StatusItemSettingsStore(userDefaults: defaults)
        #expect(reset.weeklyAccentColor == nil)
        #expect(reset.usesOneUsageColor)
        #expect(!reset.hasCustomUsageColors)
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

@MainActor
struct TokenUsagePreferencesStoreTests {
    @Test
    func chartStylesFromBeforeThePerToolChartOpenAsBars() {
        let defaults = makeDefaults()
        for old in ["dailyBars", "heatStrip", "sparkline"] {
            defaults.set(old, forKey: "tokenUsageChartStyle")
            #expect(TokenUsagePreferencesStore(userDefaults: defaults).chartStyle == .bars)
        }
    }

    @Test
    func preferencesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = TokenUsagePreferencesStore(userDefaults: defaults)
        first.isEnabled = true
        first.chartStyle = .lines
        first.breakdown = .topModels
        first.peakScope = .allTime

        let second = TokenUsagePreferencesStore(userDefaults: defaults)

        #expect(second.isEnabled)
        #expect(second.chartStyle == .lines)
        #expect(second.breakdown == .topModels)
        #expect(second.peakScope == .allTime)
    }

    @Test
    func hiddenPeriodsMigrateToThirtyDays() {
        let defaults = makeDefaults()
        defaults.set(CodexTokenUsagePeriod.last7Days.rawValue, forKey: "tokenUsagePeriod")

        let store = TokenUsagePreferencesStore(userDefaults: defaults)

        #expect(store.period == .last30Days)
        #expect(defaults.object(forKey: "tokenUsagePeriod") as? Int == CodexTokenUsagePeriod.last30Days.rawValue)
    }
}

@MainActor
struct ThemePreferencesStoreTests {
    @Test
    func defaultsToCobalt() {
        let store = ThemePreferencesStore(userDefaults: makeDefaults())

        #expect(store.theme == .cobalt)
        #expect(store.appIconColor == .cobalt)
    }

    @Test
    func firstThemeMatchesTheIconColorSavedBeforeThemes() {
        let defaults = makeDefaults()
        defaults.set("rose", forKey: "appIconColor")

        #expect(ThemePreferencesStore(userDefaults: defaults).theme == .rose)
    }

    @Test
    func toolColorsKeepsTheLastIconAndBothPersist() {
        let defaults = makeDefaults()
        let first = ThemePreferencesStore(userDefaults: defaults)
        first.theme = .emerald
        first.theme = .toolColors

        let second = ThemePreferencesStore(userDefaults: defaults)
        #expect(second.theme == .toolColors)
        #expect(second.appIconColor == .emerald)
    }

    @Test
    func monochromeUsesTheGraphiteIcon() {
        let store = ThemePreferencesStore(userDefaults: makeDefaults())
        store.theme = .monochrome

        #expect(store.appIconColor == .graphite)
    }

    @Test
    func unknownStoredValuesFallBackToCobalt() {
        let defaults = makeDefaults()
        defaults.set("tangerine", forKey: "appIconColor")
        defaults.set("neon", forKey: "appTheme")

        #expect(ThemePreferencesStore(userDefaults: defaults).theme == .cobalt)
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "TypedSettingsStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
