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

    var statusBarMonochrome: Bool {
        didSet {
            userDefaults.set(statusBarMonochrome, forKey: Self.statusBarMonochromeKey)
        }
    }

    var statusBarDisplayMode: StatusBarDisplayMode {
        didSet {
            userDefaults.set(statusBarDisplayMode.rawValue, forKey: Self.statusBarDisplayModeKey)
        }
    }

    var progressAccentColor: StatusItemAccentColor? {
        didSet {
            persistColor(progressAccentColor, key: Self.progressAccentColorKey)
        }
    }

    var usageBarDisplayMode: UsageBarDisplayMode {
        didSet {
            userDefaults.set(usageBarDisplayMode.rawValue, forKey: Self.usageBarDisplayModeKey)
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
    private static let statusBarMonochromeKey = "statusBarMonochrome"
    private static let statusBarDisplayModeKey = "statusBarDisplayMode"
    private static let progressAccentColorKey = "progressAccentColor"
    private static let usageBarDisplayModeKey = "usageBarDisplayMode"
    private static let pacingMarkersEnabledKey = "pacingMarkersEnabled"
    private static let revealStatusItemTitleShortcutKey = "revealStatusItemTitleShortcut"
    private static let revealStatusItemTitleShortcutEnabledKey = "revealStatusItemTitleShortcutEnabled"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedStyle = userDefaults.string(forKey: Self.statusBarIndicatorStyleKey)
        if storedStyle == "notchedSquare" {
            statusBarIndicatorStyle = .stackedBars
        } else if storedStyle == "splitCapsule" {
            statusBarIndicatorStyle = .twinPills
        } else {
            statusBarIndicatorStyle = storedStyle.flatMap(StatusBarIndicatorStyle.init(rawValue:)) ?? .twinPills
        }

        statusBarMonochrome = userDefaults.object(forKey: Self.statusBarMonochromeKey) as? Bool ?? true
        statusBarDisplayMode = userDefaults.string(forKey: Self.statusBarDisplayModeKey)
            .flatMap(StatusBarDisplayMode.init(rawValue:)) ?? .textOnHover
        progressAccentColor = Self.loadColor(from: userDefaults, key: Self.progressAccentColorKey)
        usageBarDisplayMode = userDefaults.string(forKey: Self.usageBarDisplayModeKey)
            .flatMap(UsageBarDisplayMode.init(rawValue:)) ?? .used
        pacingMarkersEnabled = userDefaults.object(forKey: Self.pacingMarkersEnabledKey) as? Bool ?? true
        revealStatusItemTitleShortcut = Self.loadRevealShortcut(from: userDefaults)
    }

    var hasCustomProgressAccentColor: Bool {
        progressAccentColor != nil
    }

    func resetProgressAccentColor() {
        progressAccentColor = nil
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
