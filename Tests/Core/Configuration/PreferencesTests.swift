import Foundation
import Testing

@testable import RUsage

struct PreferencesTests {
    @Test
    func aFreshInstallGetsEveryGroupsDefaults() {
        let preferences = Preferences(userDefaults: makeDefaults())

        #expect(preferences.load(GeneralSettings.self) == .defaults)
        #expect(preferences.load(MenuBarSettings.self) == .defaults)
        #expect(preferences.load(TokenUsageSettings.self) == .defaults)
        #expect(preferences.load(CodexSettings.self) == .defaults)
        #expect(preferences.load(ClaudeSettings.self) == .defaults)
        #expect(preferences.load(CursorSettings.self) == .defaults)
        #expect(GeneralSettings.defaults.toolOrder == [.claude, .codex, .cursor])
        #expect(MenuBarSettings.defaults.revealStatusItemTitleShortcut == .defaultRevealStatusItemTitle)
        #expect(CodexSettings.defaults.isConnected)
        #expect(!ClaudeSettings.defaults.isConnected)
    }

    @Test
    func savedGroupsLoadBackUnchanged() {
        let preferences = Preferences(userDefaults: makeDefaults())
        var general = GeneralSettings.defaults
        general.refreshIntervalMinutes = 10
        general.toolOrder = [.cursor, .claude, .codex]
        general.masksEmails = true
        general.theme = .rose
        var menuBar = MenuBarSettings.defaults
        menuBar.statusBarIndicatorStyle = .moon
        menuBar.statusBarDisplayMode = .iconAndText
        menuBar.sessionAccentColor = StatusItemAccentColor(red: 0.14, green: 0.55, blue: 0.31, alpha: 1)
        menuBar.weeklyAccentColor = StatusItemAccentColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1)
        menuBar.usesOneUsageColor = false
        menuBar.usagePercentMode = .left
        menuBar.usageMeterLayout = .compact
        menuBar.pacingMarkersEnabled = false
        menuBar.revealStatusItemTitleShortcut = KeyboardShortcut(keyCode: 11, modifiers: [.command, .shift])
        let tokenUsage = TokenUsageSettings(display: .graphWithBreakdownOnHover, chartStyle: .lines, breakdown: .topModels, peakScope: .allTime)
        var claude = ClaudeSettings.defaults
        claude.isConnected = true
        claude.usesOwnSignIn = true
        claude.showsModelLimits = false

        preferences.save(general)
        preferences.save(menuBar)
        preferences.save(tokenUsage)
        preferences.save(CodexSettings(isConnected: false))
        preferences.save(claude)
        preferences.save(CursorSettings(isConnected: true))

        #expect(preferences.load(GeneralSettings.self) == general)
        #expect(preferences.load(MenuBarSettings.self) == menuBar)
        #expect(preferences.load(TokenUsageSettings.self) == tokenUsage)
        #expect(preferences.load(CodexSettings.self) == CodexSettings(isConnected: false))
        #expect(preferences.load(ClaudeSettings.self) == claude)
        #expect(preferences.load(CursorSettings.self) == CursorSettings(isConnected: true))
    }

    @Test
    func aShortcutTurnedOffStaysOff() {
        let preferences = Preferences(userDefaults: makeDefaults())
        var menuBar = MenuBarSettings.defaults
        menuBar.revealStatusItemTitleShortcut = nil

        preferences.save(menuBar)

        #expect(preferences.load(MenuBarSettings.self).revealStatusItemTitleShortcut == nil)
    }

    @Test
    func aFieldThatNoLongerDecodesKeepsTheRestOfItsGroup() throws {
        let defaults = makeDefaults()
        let stored = #"{"refreshIntervalMinutes": 7, "toolOrder": ["cursor", "copilot", "cursor"], "masksEmails": true, "theme": "neon"}"#
        defaults.set(Data(stored.utf8), forKey: GeneralSettings.key)
        let menuBar = #"{"statusBarIndicatorStyle": "moon", "usagePercentMode": "half", "revealStatusItemTitleShortcut": {"keyCode": 11, "modifiers": 0}}"#
        defaults.set(Data(menuBar.utf8), forKey: MenuBarSettings.key)

        let preferences = Preferences(userDefaults: defaults)
        let general = preferences.load(GeneralSettings.self)
        let menuBarSettings = preferences.load(MenuBarSettings.self)

        #expect(general.refreshIntervalMinutes == 5)
        #expect(general.toolOrder == [.cursor, .claude, .codex])
        #expect(general.masksEmails)
        #expect(general.theme == .defaultTheme)
        #expect(menuBarSettings.statusBarIndicatorStyle == .moon)
        #expect(menuBarSettings.usagePercentMode == .used)
        #expect(menuBarSettings.revealStatusItemTitleShortcut == .defaultRevealStatusItemTitle)
        #expect(menuBarSettings.pacingMarkersEnabled)
    }

    @Test
    func aGroupThatIsNotJSONGivesDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: ClaudeSettings.key)
        defaults.set(true, forKey: "claudeUsageEnabled")

        #expect(Preferences(userDefaults: defaults).load(ClaudeSettings.self) == .defaults)
    }

    @Test
    func tokenUsageSavedBeforeItsDisplayChoiceKeepsShowingTheCard() {
        let defaults = makeDefaults()
        defaults.set(Data(#"{"isEnabled":true,"chartStyle":"lines"}"#.utf8), forKey: TokenUsageSettings.key)
        let preferences = Preferences(userDefaults: defaults)

        #expect(preferences.load(TokenUsageSettings.self).display == .graphAndBreakdown)
        #expect(preferences.load(TokenUsageSettings.self).chartStyle == .lines)

        defaults.set(Data(#"{"isEnabled":false}"#.utf8), forKey: TokenUsageSettings.key)
        #expect(preferences.load(TokenUsageSettings.self).display == .hidden)
    }

    @Test
    func aSavedGroupWinsOverLegacyKeys() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "masksEmails")
        let preferences = Preferences(userDefaults: defaults)

        preferences.save(GeneralSettings.defaults)

        #expect(!preferences.load(GeneralSettings.self).masksEmails)
    }

    @Test
    func legacyKeysCarryOverWhileAGroupIsMissing() throws {
        let defaults = makeDefaults()
        let session = StatusItemAccentColor(red: 0.14, green: 0.55, blue: 0.31, alpha: 1)
        defaults.set(10, forKey: "refreshIntervalMinutes")
        defaults.set(["cursor", "cursor", "codex"], forKey: "toolOrder")
        defaults.set(true, forKey: "masksEmails")
        defaults.set("violet", forKey: "appTheme")
        defaults.set(true, forKey: "hidesCodex")
        defaults.set("iconAndText", forKey: "statusBarDisplayMode")
        defaults.set(try JSONEncoder().encode(session), forKey: "progressAccentColor")
        defaults.set(false, forKey: "usesOneUsageColor")
        defaults.set("left", forKey: "usagePercentMode")
        defaults.set("compact", forKey: "usageMeterLayout")
        defaults.set(false, forKey: "pacingMarkersEnabled")
        defaults.set(true, forKey: "tokenUsageEnabled")
        defaults.set("area", forKey: "tokenUsageChartStyle")
        defaults.set("topModels", forKey: "tokenUsageBreakdown")
        defaults.set("allTime", forKey: "tokenUsagePeakScope")
        defaults.set(true, forKey: "claudeUsageEnabled")
        defaults.set(true, forKey: "claudeUsesOwnSignIn")
        defaults.set(false, forKey: "claudeShowsModelLimits")
        defaults.set(true, forKey: "cursorUsageEnabled")

        let preferences = Preferences(userDefaults: defaults)
        let general = preferences.load(GeneralSettings.self)
        let menuBar = preferences.load(MenuBarSettings.self)
        let claude = preferences.load(ClaudeSettings.self)

        #expect(general.refreshIntervalMinutes == 10)
        #expect(general.toolOrder == [.cursor, .codex, .claude])
        #expect(general.masksEmails)
        #expect(general.theme == .violet)
        #expect(menuBar.statusBarDisplayMode == .iconAndText)
        #expect(menuBar.sessionAccentColor == session)
        #expect(menuBar.weeklyAccentColor == nil)
        #expect(!menuBar.usesOneUsageColor)
        #expect(menuBar.usagePercentMode == .left)
        #expect(menuBar.usageMeterLayout == .compact)
        #expect(!menuBar.pacingMarkersEnabled)
        #expect(preferences.load(TokenUsageSettings.self) == TokenUsageSettings(display: .graphAndBreakdown, chartStyle: .area, breakdown: .topModels, peakScope: .allTime))
        #expect(!preferences.load(CodexSettings.self).isConnected)
        #expect(claude == ClaudeSettings(isConnected: true, usesOwnSignIn: true, showsModelLimits: false))
        #expect(preferences.load(CursorSettings.self).isConnected)
    }

    @Test(arguments: [
        ("dualArcBadge", StatusBarIndicatorStyle.moon),
        ("stackedBars", .punchCard),
        ("notchedSquare", .punchCard),
        ("hourglass", .glasses),
        ("punchCard", .punchCard),
        ("somethingUnknown", .glasses)
    ])
    func legacyIconStylesMapToCurrentStyles(rawValue: String, expectedStyle: StatusBarIndicatorStyle) {
        let defaults = makeDefaults()
        defaults.set(rawValue, forKey: "statusBarIndicatorStyle")

        #expect(Preferences(userDefaults: defaults).load(MenuBarSettings.self).statusBarIndicatorStyle == expectedStyle)
    }

    @Test
    func legacyInvalidValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(7, forKey: "refreshIntervalMinutes")
        defaults.set("neon", forKey: "appTheme")
        defaults.set("dailyBars", forKey: "tokenUsageChartStyle")
        defaults.set(try? JSONEncoder().encode(KeyboardShortcut(keyCode: 11, modifiers: [])), forKey: "revealStatusItemTitleShortcut")

        let preferences = Preferences(userDefaults: defaults)

        #expect(preferences.load(GeneralSettings.self) == .defaults)
        #expect(preferences.load(TokenUsageSettings.self).chartStyle == .bars)
        #expect(preferences.load(MenuBarSettings.self).revealStatusItemTitleShortcut == .defaultRevealStatusItemTitle)
    }

    @Test
    func aLegacyShortcutTurnedOffStaysOff() throws {
        let defaults = makeDefaults()
        defaults.set(try JSONEncoder().encode(KeyboardShortcut.defaultRevealStatusItemTitle), forKey: "revealStatusItemTitleShortcut")
        defaults.set(false, forKey: "revealStatusItemTitleShortcutEnabled")

        #expect(Preferences(userDefaults: defaults).load(MenuBarSettings.self).revealStatusItemTitleShortcut == nil)
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "PreferencesTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
