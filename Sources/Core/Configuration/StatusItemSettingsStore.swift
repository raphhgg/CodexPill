import Foundation
import Observation

struct StatusItemAccentColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

@MainActor
@Observable
final class StatusItemSettingsStore {
    var statusBarIndicatorStyle: StatusBarIndicatorStyle {
        didSet {
            userDefaults.set(statusBarIndicatorStyle.rawValue, forKey: Self.statusBarIndicatorStyleKey)
        }
    }

    var statusBarDisplayMode: StatusBarDisplayMode {
        didSet {
            userDefaults.set(statusBarDisplayMode.rawValue, forKey: Self.statusBarDisplayModeKey)
        }
    }

    var sessionAccentColor: StatusItemAccentColor? {
        didSet {
            persistColor(sessionAccentColor, key: Self.sessionAccentColorKey)
        }
    }

    var weeklyAccentColor: StatusItemAccentColor? {
        didSet {
            persistColor(weeklyAccentColor, key: Self.weeklyAccentColorKey)
        }
    }

    var usesOneUsageColor: Bool {
        didSet {
            userDefaults.set(usesOneUsageColor, forKey: Self.usesOneUsageColorKey)
        }
    }

    var usagePercentMode: UsagePercentMode {
        didSet {
            userDefaults.set(usagePercentMode.rawValue, forKey: Self.usagePercentModeKey)
        }
    }

    var usageMeterLayout: UsageMeterLayout {
        didSet {
            userDefaults.set(usageMeterLayout.rawValue, forKey: Self.usageMeterLayoutKey)
        }
    }

    var pacingMarkersEnabled: Bool {
        didSet {
            userDefaults.set(pacingMarkersEnabled, forKey: Self.pacingMarkersEnabledKey)
        }
    }

    var revealStatusItemTitleShortcut: KeyboardShortcut? {
        didSet {
            persistShortcut(revealStatusItemTitleShortcut, key: Self.revealStatusItemTitleShortcutKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let statusBarIndicatorStyleKey = "statusBarIndicatorStyle"
    private static let statusBarDisplayModeKey = "statusBarDisplayMode"
    private static let sessionAccentColorKey = "progressAccentColor"
    private static let weeklyAccentColorKey = "weeklyAccentColor"
    private static let usesOneUsageColorKey = "usesOneUsageColor"
    private static let usagePercentModeKey = "usagePercentMode"
    private static let usageMeterLayoutKey = "usageMeterLayout"
    private static let pacingMarkersEnabledKey = "pacingMarkersEnabled"
    private static let revealStatusItemTitleShortcutKey = "revealStatusItemTitleShortcut"
    private static let revealStatusItemTitleShortcutEnabledKey = "revealStatusItemTitleShortcutEnabled"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        statusBarIndicatorStyle = StatusBarIndicatorStyle(
            storedValue: userDefaults.string(forKey: Self.statusBarIndicatorStyleKey)
        )
        statusBarDisplayMode = userDefaults.string(forKey: Self.statusBarDisplayModeKey)
            .flatMap(StatusBarDisplayMode.init(rawValue:)) ?? .textOnHover
        sessionAccentColor = Self.loadColor(from: userDefaults, key: Self.sessionAccentColorKey)
        weeklyAccentColor = Self.loadColor(from: userDefaults, key: Self.weeklyAccentColorKey)
        usesOneUsageColor = userDefaults.object(forKey: Self.usesOneUsageColorKey) as? Bool ?? true
        usagePercentMode = userDefaults.string(forKey: Self.usagePercentModeKey)
            .flatMap(UsagePercentMode.init(rawValue:)) ?? .used
        usageMeterLayout = userDefaults.string(forKey: Self.usageMeterLayoutKey)
            .flatMap(UsageMeterLayout.init(rawValue:)) ?? .classic
        pacingMarkersEnabled = userDefaults.object(forKey: Self.pacingMarkersEnabledKey) as? Bool ?? true
        revealStatusItemTitleShortcut = Self.loadRevealShortcut(from: userDefaults)
    }

    var effectiveWeeklyAccentColor: StatusItemAccentColor? {
        usesOneUsageColor ? sessionAccentColor : weeklyAccentColor ?? sessionAccentColor
    }

    var hasCustomUsageColors: Bool {
        sessionAccentColor != nil || weeklyAccentColor != nil || !usesOneUsageColor
    }

    func resetUsageColors() {
        sessionAccentColor = nil
        weeklyAccentColor = nil
        usesOneUsageColor = true
    }

    private func persistColor(_ color: StatusItemAccentColor?, key: String) {
        guard let color else {
            userDefaults.removeObject(forKey: key)
            return
        }

        if let data = try? JSONEncoder().encode(color) {
            userDefaults.set(data, forKey: key)
        }
    }

    private func persistShortcut(_ shortcut: KeyboardShortcut?, key: String) {
        guard let shortcut else {
            userDefaults.removeObject(forKey: key)
            userDefaults.set(false, forKey: Self.revealStatusItemTitleShortcutEnabledKey)
            return
        }

        if let data = try? JSONEncoder().encode(shortcut) {
            userDefaults.set(data, forKey: key)
            userDefaults.set(true, forKey: Self.revealStatusItemTitleShortcutEnabledKey)
        }
    }

    private static func loadRevealShortcut(from userDefaults: UserDefaults) -> KeyboardShortcut? {
        if let enabled = userDefaults.object(forKey: revealStatusItemTitleShortcutEnabledKey) as? Bool,
           !enabled {
            return nil
        }

        return loadShortcut(
            from: userDefaults,
            key: revealStatusItemTitleShortcutKey
        ) ?? .defaultRevealStatusItemTitle
    }

    private static func loadShortcut(from userDefaults: UserDefaults, key: String) -> KeyboardShortcut? {
        guard let data = userDefaults.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
        else {
            return nil
        }
        return shortcut.isValid ? shortcut : nil
    }

    private static func loadColor(from userDefaults: UserDefaults, key: String) -> StatusItemAccentColor? {
        guard let data = userDefaults.data(forKey: key),
              let components = try? JSONDecoder().decode(StatusItemAccentColor.self, from: data)
        else {
            return nil
        }

        return components
    }
}
