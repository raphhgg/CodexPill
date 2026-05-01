import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class StatusItemSettingsStore {
    private struct StoredColorComponents: Codable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

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

    var progressAccentColor: NSColor {
        didSet {
            persistColor(progressAccentColor, key: Self.progressAccentColorKey)
        }
    }

    var pacingMarkersEnabled: Bool {
        didSet {
            userDefaults.set(pacingMarkersEnabled, forKey: Self.pacingMarkersEnabledKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let statusBarIndicatorStyleKey = "statusBarIndicatorStyle"
    private static let statusBarMonochromeKey = "statusBarMonochrome"
    private static let statusBarDisplayModeKey = "statusBarDisplayMode"
    private static let progressAccentColorKey = "progressAccentColor"
    private static let pacingMarkersEnabledKey = "pacingMarkersEnabled"

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
        progressAccentColor = Self.loadColor(
            from: userDefaults,
            key: Self.progressAccentColorKey,
            defaultColor: StatusBarProgressColorDefaults.accent
        )
        pacingMarkersEnabled = userDefaults.object(forKey: Self.pacingMarkersEnabledKey) as? Bool ?? true
    }

    var hasCustomProgressAccentColor: Bool {
        !Self.colorsEqual(progressAccentColor, StatusBarProgressColorDefaults.accent)
    }

    func resetProgressAccentColor() {
        progressAccentColor = StatusBarProgressColorDefaults.accent
    }

    private func persistColor(_ color: NSColor, key: String) {
        let normalized = Self.normalizedColor(color)
        let components = StoredColorComponents(
            red: Double(normalized.redComponent),
            green: Double(normalized.greenComponent),
            blue: Double(normalized.blueComponent),
            alpha: Double(normalized.alphaComponent)
        )

        if Self.colorsEqual(color, StatusBarProgressColorDefaults.accent) {
            userDefaults.removeObject(forKey: key)
            return
        }

        if let data = try? JSONEncoder().encode(components) {
            userDefaults.set(data, forKey: key)
        }
    }

    private static func loadColor(from userDefaults: UserDefaults, key: String, defaultColor: NSColor) -> NSColor {
        guard let data = userDefaults.data(forKey: key),
              let components = try? JSONDecoder().decode(StoredColorComponents.self, from: data)
        else {
            return defaultColor
        }

        return NSColor(
            deviceRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.alpha
        )
    }

    private static func normalizedColor(_ color: NSColor) -> NSColor {
        if let deviceRGB = color.usingColorSpace(.deviceRGB) {
            return deviceRGB
        }

        if let sRGB = color.usingColorSpace(.sRGB) {
            return sRGB
        }

        return color
    }

    private static func colorsEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = normalizedColor(lhs)
        let right = normalizedColor(rhs)

        return abs(left.redComponent - right.redComponent) < 0.001
            && abs(left.greenComponent - right.greenComponent) < 0.001
            && abs(left.blueComponent - right.blueComponent) < 0.001
            && abs(left.alphaComponent - right.alphaComponent) < 0.001
    }
}
