import AppKit
import Foundation
import Observation

enum StatusBarProgressColorDefaults {
    static let accent = NSColor.controlAccentColor
}

@MainActor
@Observable
final class AppSettings {
    private struct StoredColorComponents: Codable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    var refreshIntervalMinutes: Int {
        didSet {
            userDefaults.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey)
        }
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

    var visibleInactiveAccountCount: Int {
        didSet {
            userDefaults.set(visibleInactiveAccountCount, forKey: Self.visibleInactiveAccountCountKey)
        }
    }

    var progressAccentColor: NSColor {
        didSet {
            persistColor(progressAccentColor, key: Self.progressAccentColorKey)
        }
    }

    let refreshIntervalOptions = [1, 2, 5, 10, 15, 30]
    let visibleInactiveAccountCountOptions = [2, 3, 5, 0]

    private let userDefaults: UserDefaults

    private static let refreshIntervalKey = "refreshIntervalMinutes"
    private static let statusBarIndicatorStyleKey = "statusBarIndicatorStyle"
    private static let statusBarMonochromeKey = "statusBarMonochrome"
    private static let statusBarDisplayModeKey = "statusBarDisplayMode"
    private static let visibleInactiveAccountCountKey = "visibleInactiveAccountCount"
    private static let progressAccentColorKey = "progressAccentColor"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedRefreshInterval = userDefaults.integer(forKey: Self.refreshIntervalKey)
        refreshIntervalMinutes = refreshIntervalOptions.contains(storedRefreshInterval) ? storedRefreshInterval : 5

        let storedStyle = userDefaults.string(forKey: Self.statusBarIndicatorStyleKey)
        if storedStyle == "notchedSquare" {
            statusBarIndicatorStyle = .stackedBars
        } else if storedStyle == "splitCapsule" {
            statusBarIndicatorStyle = .twinPills
        } else {
            statusBarIndicatorStyle = storedStyle.flatMap(StatusBarIndicatorStyle.init(rawValue:)) ?? .dualArcBadge
        }

        statusBarMonochrome = userDefaults.bool(forKey: Self.statusBarMonochromeKey)
        statusBarDisplayMode = userDefaults.string(forKey: Self.statusBarDisplayModeKey)
            .flatMap(StatusBarDisplayMode.init(rawValue:)) ?? .textOnHover

        let storedVisibleInactiveAccountCount = userDefaults.integer(forKey: Self.visibleInactiveAccountCountKey)
        visibleInactiveAccountCount = visibleInactiveAccountCountOptions.contains(storedVisibleInactiveAccountCount)
            ? storedVisibleInactiveAccountCount
            : 2

        progressAccentColor = Self.loadColor(
            from: userDefaults,
            key: Self.progressAccentColorKey,
            defaultColor: StatusBarProgressColorDefaults.accent
        )
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
