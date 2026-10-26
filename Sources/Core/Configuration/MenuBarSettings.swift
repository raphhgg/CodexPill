import Foundation

/// How the menu bar icon and the usage bars on each tool card look.
struct MenuBarSettings: SettingsGroup {
    static let key = "settings.menuBar.v1"
    static let defaults = MenuBarSettings()

    var statusBarIndicatorStyle = StatusBarIndicatorStyle.glasses
    var statusBarDisplayMode = StatusBarDisplayMode.textOnHover
    /// Custom usage bar colors. Nil uses the theme's colors.
    var sessionAccentColor: StatusItemAccentColor?
    var weeklyAccentColor: StatusItemAccentColor?
    var usesOneUsageColor = true
    var usagePercentMode = UsagePercentMode.used
    var usageMeterLayout = UsageMeterLayout.classic
    var pacingMarkersEnabled = true
    /// Nil when the user turned the shortcut off.
    var revealStatusItemTitleShortcut: KeyboardShortcut? = .defaultRevealStatusItemTitle
}

extension MenuBarSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        statusBarIndicatorStyle = container.value(.statusBarIndicatorStyle, or: defaults.statusBarIndicatorStyle)
        statusBarDisplayMode = container.value(.statusBarDisplayMode, or: defaults.statusBarDisplayMode)
        sessionAccentColor = try? container.decodeIfPresent(StatusItemAccentColor.self, forKey: .sessionAccentColor)
        weeklyAccentColor = try? container.decodeIfPresent(StatusItemAccentColor.self, forKey: .weeklyAccentColor)
        usesOneUsageColor = container.value(.usesOneUsageColor, or: defaults.usesOneUsageColor)
        usagePercentMode = container.value(.usagePercentMode, or: defaults.usagePercentMode)
        usageMeterLayout = container.value(.usageMeterLayout, or: defaults.usageMeterLayout)
        pacingMarkersEnabled = container.value(.pacingMarkersEnabled, or: defaults.pacingMarkersEnabled)
        // A stored null is a shortcut turned off. A missing or invalid one is the default.
        if container.contains(.revealStatusItemTitleShortcut),
           (try? container.decodeNil(forKey: .revealStatusItemTitleShortcut)) == true {
            revealStatusItemTitleShortcut = nil
        } else {
            revealStatusItemTitleShortcut = (try? container.decodeIfPresent(KeyboardShortcut.self, forKey: .revealStatusItemTitleShortcut))
                .flatMap { $0.isValid ? $0 : nil } ?? defaults.revealStatusItemTitleShortcut
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(statusBarIndicatorStyle, forKey: .statusBarIndicatorStyle)
        try container.encode(statusBarDisplayMode, forKey: .statusBarDisplayMode)
        try container.encodeIfPresent(sessionAccentColor, forKey: .sessionAccentColor)
        try container.encodeIfPresent(weeklyAccentColor, forKey: .weeklyAccentColor)
        try container.encode(usesOneUsageColor, forKey: .usesOneUsageColor)
        try container.encode(usagePercentMode, forKey: .usagePercentMode)
        try container.encode(usageMeterLayout, forKey: .usageMeterLayout)
        try container.encode(pacingMarkersEnabled, forKey: .pacingMarkersEnabled)
        // Null, not left out, so a shortcut turned off stays off instead of coming back as the default.
        try container.encode(revealStatusItemTitleShortcut, forKey: .revealStatusItemTitleShortcut)
    }

    var effectiveWeeklyAccentColor: StatusItemAccentColor? {
        usesOneUsageColor ? sessionAccentColor : weeklyAccentColor ?? sessionAccentColor
    }

    var hasCustomUsageColors: Bool {
        sessionAccentColor != nil || weeklyAccentColor != nil || !usesOneUsageColor
    }

    mutating func resetUsageColors() {
        sessionAccentColor = nil
        weeklyAccentColor = nil
        usesOneUsageColor = true
    }
}
