import AppKit
import Foundation
import Observation

enum StatusBarProgressColorDefaults {
    static let accent = NSColor.controlAccentColor
}

struct PersistedRemoteHostState: Codable, Equatable, Identifiable {
    var host: RemoteHost
    var installedAccountIDs: [UUID]
    var activeAccount: CodexAccount?

    var id: String {
        host.destination
    }

    init(host: RemoteHost, installedAccountIDs: [UUID] = [], activeAccount: CodexAccount? = nil) {
        self.host = host
        self.installedAccountIDs = installedAccountIDs
        self.activeAccount = activeAccount
    }
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

    var remoteHostStates: [PersistedRemoteHostState] {
        didSet {
            persistCodable(remoteHostStates, key: Self.remoteHostsKey)
        }
    }

    var configuredRemoteHost: RemoteHost? {
        get { remoteHostStates.first?.host }
        set {
            if let newValue {
                upsertRemoteHost(newValue)
            } else if let first = remoteHostStates.first {
                removeRemoteHost(destination: first.host.destination)
            }
        }
    }

    var remoteHostInstalledAccountIDs: [UUID] {
        get { remoteHostStates.first?.installedAccountIDs ?? [] }
        set {
            guard let host = remoteHostStates.first?.host else { return }
            updateRemoteHostState(for: host) { state in
                state.installedAccountIDs = newValue
            }
        }
    }

    var remoteHostActiveAccount: CodexAccount? {
        get { remoteHostStates.first?.activeAccount }
        set {
            guard let host = remoteHostStates.first?.host else { return }
            updateRemoteHostState(for: host) { state in
                state.activeAccount = newValue
            }
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
    private static let remoteHostsKey = "remoteHosts"
    private static let remoteHostKey = "remoteHost"
    private static let remoteHostInstalledAccountIDsKey = "remoteHostInstalledAccountIDs"
    private static let remoteHostActiveAccountKey = "remoteHostActiveAccount"

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
        remoteHostStates = Self.loadCodable(from: userDefaults, key: Self.remoteHostsKey)
            ?? Self.loadLegacyRemoteHostStates(from: userDefaults)
    }

    var hasCustomProgressAccentColor: Bool {
        !Self.colorsEqual(progressAccentColor, StatusBarProgressColorDefaults.accent)
    }

    func resetProgressAccentColor() {
        progressAccentColor = StatusBarProgressColorDefaults.accent
    }

    func upsertRemoteHost(_ host: RemoteHost) {
        updateRemoteHostState(for: host) { _ in }
    }

    func removeRemoteHost(destination: String) {
        remoteHostStates.removeAll { $0.host.destination == destination }
    }

    func remoteHostState(for destination: String) -> PersistedRemoteHostState? {
        remoteHostStates.first(where: { $0.host.destination == destination })
    }

    func updateRemoteHostState(for host: RemoteHost, mutate: (inout PersistedRemoteHostState) -> Void) {
        if let index = remoteHostStates.firstIndex(where: { $0.host.destination == host.destination }) {
            var updated = remoteHostStates[index]
            updated.host = host
            mutate(&updated)
            remoteHostStates[index] = updated
            return
        }

        var state = PersistedRemoteHostState(host: host)
        mutate(&state)
        remoteHostStates.append(state)
        remoteHostStates.sort { $0.host.displayName.localizedCaseInsensitiveCompare($1.host.displayName) == .orderedAscending }
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

    private func persistCodable<T: Codable>(_ value: T?, key: String) {
        guard let value else {
            userDefaults.removeObject(forKey: key)
            return
        }

        if let data = try? JSONEncoder().encode(value) {
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

    private static func loadCodable<T: Codable>(from userDefaults: UserDefaults, key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func loadLegacyRemoteHostStates(from userDefaults: UserDefaults) -> [PersistedRemoteHostState] {
        guard let host: RemoteHost = loadCodable(from: userDefaults, key: Self.remoteHostKey) else {
            return []
        }

        let installedAccountIDs: [UUID] = loadCodable(from: userDefaults, key: Self.remoteHostInstalledAccountIDsKey) ?? []
        let activeAccount: CodexAccount? = loadCodable(from: userDefaults, key: Self.remoteHostActiveAccountKey)
        return [PersistedRemoteHostState(host: host, installedAccountIDs: installedAccountIDs, activeAccount: activeAccount)]
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
