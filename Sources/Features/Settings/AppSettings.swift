import Foundation

extension Notification.Name {
    static let codexSwitchboardSettingsDidChange = Notification.Name("CodexSwitchboardSettingsDidChange")
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var refreshIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey)
            NotificationCenter.default.post(name: .codexSwitchboardSettingsDidChange, object: self)
        }
    }

    @Published var statusBarIndicatorStyle: StatusBarIndicatorStyle {
        didSet {
            UserDefaults.standard.set(statusBarIndicatorStyle.rawValue, forKey: Self.statusBarIndicatorStyleKey)
            NotificationCenter.default.post(name: .codexSwitchboardSettingsDidChange, object: self)
        }
    }

    @Published var statusBarMonochrome: Bool {
        didSet {
            UserDefaults.standard.set(statusBarMonochrome, forKey: Self.statusBarMonochromeKey)
            NotificationCenter.default.post(name: .codexSwitchboardSettingsDidChange, object: self)
        }
    }

    @Published var visibleInactiveAccountCount: Int {
        didSet {
            UserDefaults.standard.set(visibleInactiveAccountCount, forKey: Self.visibleInactiveAccountCountKey)
            NotificationCenter.default.post(name: .codexSwitchboardSettingsDidChange, object: self)
        }
    }

    let refreshIntervalOptions = [1, 2, 5, 10, 15, 30]
    let visibleInactiveAccountCountOptions = [2, 3, 5, 0]

    private static let refreshIntervalKey = "refreshIntervalMinutes"
    private static let statusBarIndicatorStyleKey = "statusBarIndicatorStyle"
    private static let statusBarMonochromeKey = "statusBarMonochrome"
    private static let visibleInactiveAccountCountKey = "visibleInactiveAccountCount"

    private init() {
        let storedValue = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
        refreshIntervalMinutes = refreshIntervalOptions.contains(storedValue) ? storedValue : 5
        let storedStyle = UserDefaults.standard.string(forKey: Self.statusBarIndicatorStyleKey)
        if storedStyle == "notchedSquare" {
            statusBarIndicatorStyle = .stackedBars
        } else if storedStyle == "splitCapsule" {
            statusBarIndicatorStyle = .twinPills
        } else {
            statusBarIndicatorStyle = storedStyle.flatMap(StatusBarIndicatorStyle.init(rawValue:)) ?? .dualArcBadge
        }
        statusBarMonochrome = UserDefaults.standard.bool(forKey: Self.statusBarMonochromeKey)

        let storedVisibleInactiveAccountCount = UserDefaults.standard.integer(forKey: Self.visibleInactiveAccountCountKey)
        visibleInactiveAccountCount = visibleInactiveAccountCountOptions.contains(storedVisibleInactiveAccountCount)
            ? storedVisibleInactiveAccountCount
            : 2
    }
}
