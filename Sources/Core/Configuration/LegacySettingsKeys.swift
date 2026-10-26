import Foundation

// The flat keys rusage stored one setting per key before settings were grouped. `Preferences` reads them only
// while a group's own key is missing. Delete this file once every install has saved each group.

extension GeneralSettings {
    static func legacy(in userDefaults: UserDefaults) -> Self {
        var settings = defaults
        settings.refreshIntervalMinutes = refreshInterval(userDefaults.integer(forKey: "refreshIntervalMinutes"))
        settings.toolOrder = completeToolOrder(
            (userDefaults.stringArray(forKey: "toolOrder") ?? []).compactMap(UsageProvider.init(rawValue:))
        )
        settings.masksEmails = userDefaults.bool(forKey: "masksEmails")
        settings.theme = userDefaults.string(forKey: "appTheme").flatMap(AppTheme.init(rawValue:)) ?? defaults.theme
        return settings
    }
}

extension MenuBarSettings {
    static func legacy(in userDefaults: UserDefaults) -> Self {
        var settings = defaults
        settings.statusBarIndicatorStyle = StatusBarIndicatorStyle(storedValue: userDefaults.string(forKey: "statusBarIndicatorStyle"))
        settings.statusBarDisplayMode = userDefaults.string(forKey: "statusBarDisplayMode")
            .flatMap(StatusBarDisplayMode.init(rawValue:)) ?? defaults.statusBarDisplayMode
        settings.sessionAccentColor = decoded(StatusItemAccentColor.self, userDefaults, "progressAccentColor")
        settings.weeklyAccentColor = decoded(StatusItemAccentColor.self, userDefaults, "weeklyAccentColor")
        settings.usesOneUsageColor = userDefaults.object(forKey: "usesOneUsageColor") as? Bool ?? defaults.usesOneUsageColor
        settings.usagePercentMode = userDefaults.string(forKey: "usagePercentMode")
            .flatMap(UsagePercentMode.init(rawValue:)) ?? defaults.usagePercentMode
        settings.usageMeterLayout = userDefaults.string(forKey: "usageMeterLayout")
            .flatMap(UsageMeterLayout.init(rawValue:)) ?? defaults.usageMeterLayout
        settings.pacingMarkersEnabled = userDefaults.object(forKey: "pacingMarkersEnabled") as? Bool ?? defaults.pacingMarkersEnabled
        if userDefaults.object(forKey: "revealStatusItemTitleShortcutEnabled") as? Bool == false {
            settings.revealStatusItemTitleShortcut = nil
        } else {
            settings.revealStatusItemTitleShortcut = decoded(KeyboardShortcut.self, userDefaults, "revealStatusItemTitleShortcut")
                .flatMap { $0.isValid ? $0 : nil } ?? defaults.revealStatusItemTitleShortcut
        }
        return settings
    }

    private static func decoded<Value: Decodable>(_ type: Value.Type, _ userDefaults: UserDefaults, _ key: String) -> Value? {
        userDefaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

extension TokenUsageSettings {
    static func legacy(in userDefaults: UserDefaults) -> Self {
        var settings = defaults
        settings.isEnabled = userDefaults.bool(forKey: "tokenUsageEnabled")
        settings.chartStyle = TokenUsageChartStyle(storedValue: userDefaults.string(forKey: "tokenUsageChartStyle"))
        settings.breakdown = TokenUsageBreakdown(storedValue: userDefaults.string(forKey: "tokenUsageBreakdown"))
        settings.peakScope = userDefaults.string(forKey: "tokenUsagePeakScope")
            .flatMap(TokenUsagePeakScope.init(rawValue:)) ?? defaults.peakScope
        return settings
    }
}

extension CodexSettings {
    static func legacy(in userDefaults: UserDefaults) -> Self {
        var settings = defaults
        settings.isConnected = !userDefaults.bool(forKey: "hidesCodex")
        return settings
    }
}

extension ClaudeSettings {
    static func legacy(in userDefaults: UserDefaults) -> Self {
        var settings = defaults
        settings.isConnected = userDefaults.bool(forKey: "claudeUsageEnabled")
        settings.usesOwnSignIn = userDefaults.bool(forKey: "claudeUsesOwnSignIn")
        settings.showsModelLimits = userDefaults.object(forKey: "claudeShowsModelLimits") as? Bool ?? defaults.showsModelLimits
        return settings
    }
}

extension CursorSettings {
    static func legacy(in userDefaults: UserDefaults) -> Self {
        var settings = defaults
        settings.isConnected = userDefaults.bool(forKey: "cursorUsageEnabled")
        return settings
    }
}
