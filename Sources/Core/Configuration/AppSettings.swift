import AppKit
import Foundation
import Observation

enum StatusBarProgressColorDefaults {
    static let accent = NSColor.controlAccentColor
}

struct PersistedRemoteHostState: Codable, Equatable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case host
        case installedAccountIDs
        case desiredAccountID
        case verifiedAccount
        case detectedAccountID
        case verificationStatus
        case lastVerificationError
        case activeAccount
    }

    enum VerificationStatus: String, Codable, Equatable {
        case unverified
        case verifying
        case verified
        case failed
    }

    var host: RemoteHost
    var installedAccountIDs: [UUID]
    var desiredAccountID: UUID?
    var verifiedAccount: CodexAccount?
    var detectedAccountID: UUID?
    var verificationStatus: VerificationStatus
    var lastVerificationError: String?

    var id: String {
        host.destination
    }

    var activeAccount: CodexAccount? {
        get { verifiedAccount }
        set {
            verifiedAccount = newValue
            detectedAccountID = nil
            verificationStatus = newValue == nil ? .unverified : .verified
            lastVerificationError = nil
            if desiredAccountID == nil {
                desiredAccountID = newValue?.id
            }
        }
    }

    init(
        host: RemoteHost,
        installedAccountIDs: [UUID] = [],
        desiredAccountID: UUID? = nil,
        verifiedAccount: CodexAccount? = nil,
        detectedAccountID: UUID? = nil,
        verificationStatus: VerificationStatus? = nil,
        lastVerificationError: String? = nil
    ) {
        self.host = host
        self.installedAccountIDs = installedAccountIDs
        self.desiredAccountID = desiredAccountID
        self.verifiedAccount = verifiedAccount
        self.detectedAccountID = detectedAccountID
        self.verificationStatus = verificationStatus ?? (verifiedAccount == nil ? .unverified : .verified)
        self.lastVerificationError = lastVerificationError
    }

    init(host: RemoteHost, installedAccountIDs: [UUID] = [], activeAccount: CodexAccount? = nil) {
        self.init(
            host: host,
            installedAccountIDs: installedAccountIDs,
            desiredAccountID: activeAccount?.id,
            verifiedAccount: activeAccount,
            verificationStatus: activeAccount == nil ? .unverified : .verified,
            lastVerificationError: nil
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        host = try container.decode(RemoteHost.self, forKey: .host)
        installedAccountIDs = try container.decodeIfPresent([UUID].self, forKey: .installedAccountIDs) ?? []

        let desiredAccountID = try container.decodeIfPresent(UUID.self, forKey: .desiredAccountID)
        let verifiedAccount = try container.decodeIfPresent(CodexAccount.self, forKey: .verifiedAccount)
        let detectedAccountID = try container.decodeIfPresent(UUID.self, forKey: .detectedAccountID)
        let verificationStatus = try container.decodeIfPresent(VerificationStatus.self, forKey: .verificationStatus)
        let lastVerificationError = try container.decodeIfPresent(String.self, forKey: .lastVerificationError)

        if desiredAccountID != nil || verifiedAccount != nil || verificationStatus != nil || detectedAccountID != nil || lastVerificationError != nil {
            self.desiredAccountID = desiredAccountID
            self.verifiedAccount = verifiedAccount
            self.detectedAccountID = detectedAccountID
            self.verificationStatus = verificationStatus ?? (verifiedAccount == nil ? .unverified : .verified)
            self.lastVerificationError = lastVerificationError
            return
        }

        let legacyActiveAccount = try container.decodeIfPresent(CodexAccount.self, forKey: .activeAccount)
        self.desiredAccountID = legacyActiveAccount?.id
        self.verifiedAccount = nil
        self.detectedAccountID = nil
        self.verificationStatus = legacyActiveAccount == nil ? .unverified : .unverified
        self.lastVerificationError = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(installedAccountIDs, forKey: .installedAccountIDs)
        try container.encodeIfPresent(desiredAccountID, forKey: .desiredAccountID)
        try container.encodeIfPresent(verifiedAccount, forKey: .verifiedAccount)
        try container.encodeIfPresent(detectedAccountID, forKey: .detectedAccountID)
        try container.encode(verificationStatus, forKey: .verificationStatus)
        try container.encodeIfPresent(lastVerificationError, forKey: .lastVerificationError)
    }
}

enum PersistedAccountNotificationReason: String, Codable, Equatable {
    case whenBlocked
    case whenOut

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "whenBlocked":
            self = .whenBlocked
        case "whenOut", "beforeYouRunOut":
            self = .whenOut
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown persisted notification reason: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct PersistedAccountNotificationWindow: Codable, Equatable {
    var sessionResetAt: Date?
    var weeklyResetAt: Date?
}

struct PersistedAccountNotificationRecord: Codable, Equatable {
    var reason: PersistedAccountNotificationReason
    var window: PersistedAccountNotificationWindow
    var notifiedAt: Date
}

struct PersistedAccountNotificationState: Codable, Equatable, Identifiable {
    var accountID: UUID
    var isArmed: Bool
    var lastNotification: PersistedAccountNotificationRecord?

    var id: UUID { accountID }

    init(
        accountID: UUID,
        isArmed: Bool = true,
        lastNotification: PersistedAccountNotificationRecord? = nil
    ) {
        self.accountID = accountID
        self.isArmed = isArmed
        self.lastNotification = lastNotification
    }
}

@MainActor
@Observable
final class MenuPreferencesStore {
    var refreshIntervalMinutes: Int {
        didSet {
            userDefaults.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey)
        }
    }

    var visibleInactiveAccountCount: Int {
        didSet {
            userDefaults.set(visibleInactiveAccountCount, forKey: Self.visibleInactiveAccountCountKey)
        }
    }

    let refreshIntervalOptions = [1, 2, 5, 10, 15, 30]
    let visibleInactiveAccountCountOptions = [2, 3, 5, 0]

    private let userDefaults: UserDefaults

    private static let refreshIntervalKey = "refreshIntervalMinutes"
    private static let visibleInactiveAccountCountKey = "visibleInactiveAccountCount"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedRefreshInterval = userDefaults.integer(forKey: Self.refreshIntervalKey)
        refreshIntervalMinutes = refreshIntervalOptions.contains(storedRefreshInterval) ? storedRefreshInterval : 5

        let storedVisibleInactiveAccountCount = userDefaults.integer(forKey: Self.visibleInactiveAccountCountKey)
        visibleInactiveAccountCount = visibleInactiveAccountCountOptions.contains(storedVisibleInactiveAccountCount)
            ? storedVisibleInactiveAccountCount
            : 2
    }
}

@MainActor
@Observable
final class StatusBarPreferencesStore {
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

    private let userDefaults: UserDefaults

    private static let statusBarIndicatorStyleKey = "statusBarIndicatorStyle"
    private static let statusBarMonochromeKey = "statusBarMonochrome"
    private static let statusBarDisplayModeKey = "statusBarDisplayMode"
    private static let progressAccentColorKey = "progressAccentColor"

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

@MainActor
@Observable
final class RemoteHostSettingsStore {
    var remoteHostStates: [PersistedRemoteHostState] {
        didSet {
            persistCodable(remoteHostStates, key: Self.remoteHostsKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let remoteHostsKey = "remoteHosts"
    private static let remoteHostKey = "remoteHost"
    private static let remoteHostInstalledAccountIDsKey = "remoteHostInstalledAccountIDs"
    private static let remoteHostActiveAccountKey = "remoteHostActiveAccount"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        remoteHostStates = Self.loadCodable(from: userDefaults, key: Self.remoteHostsKey)
            ?? Self.loadLegacyRemoteHostStates(from: userDefaults)
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
        get { remoteHostStates.first?.verifiedAccount }
        set {
            guard let host = remoteHostStates.first?.host else { return }
            updateRemoteHostState(for: host) { state in
                state.verifiedAccount = newValue
                state.detectedAccountID = nil
                state.verificationStatus = newValue == nil ? .unverified : .verified
                state.lastVerificationError = nil
                if state.desiredAccountID == nil {
                    state.desiredAccountID = newValue?.id
                }
            }
        }
    }

    var remoteHostDesiredAccountID: UUID? {
        get { remoteHostStates.first?.desiredAccountID }
        set {
            guard let host = remoteHostStates.first?.host else { return }
            updateRemoteHostState(for: host) { state in
                state.desiredAccountID = newValue
            }
        }
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

    private func persistCodable<T: Codable>(_ value: T?, key: String) {
        guard let value else {
            userDefaults.removeObject(forKey: key)
            return
        }

        if let data = try? JSONEncoder().encode(value) {
            userDefaults.set(data, forKey: key)
        }
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
        return [
            PersistedRemoteHostState(
                host: host,
                installedAccountIDs: installedAccountIDs,
                desiredAccountID: activeAccount?.id,
                verifiedAccount: nil,
                verificationStatus: .unverified
            )
        ]
    }
}

@MainActor
@Observable
final class NotificationPreferencesStore {
    var notificationsWhenBlockedEnabled: Bool {
        didSet {
            userDefaults.set(notificationsWhenBlockedEnabled, forKey: Self.notificationsWhenBlockedEnabledKey)
        }
    }

    var notificationsWhenOutEnabled: Bool {
        didSet {
            userDefaults.set(notificationsWhenOutEnabled, forKey: Self.notificationsWhenOutEnabledKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let notificationsWhenBlockedEnabledKey = "notificationsWhenBlockedEnabled"
    private static let notificationsWhenOutEnabledKey = "notificationsWhenOutEnabled"
    private static let legacyNotificationsBeforeYouRunOutEnabledKey = "notificationsBeforeYouRunOutEnabled"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        notificationsWhenBlockedEnabled = userDefaults.bool(forKey: Self.notificationsWhenBlockedEnabledKey)
        notificationsWhenOutEnabled = userDefaults.object(forKey: Self.notificationsWhenOutEnabledKey) as? Bool
            ?? userDefaults.bool(forKey: Self.legacyNotificationsBeforeYouRunOutEnabledKey)
    }
}

@MainActor
@Observable
final class NotificationStateStore {
    var accountNotificationStates: [PersistedAccountNotificationState] {
        didSet {
            persistCodable(accountNotificationStates, key: Self.accountNotificationStatesKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let accountNotificationStatesKey = "accountNotificationStates"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        accountNotificationStates = Self.loadCodable(from: userDefaults, key: Self.accountNotificationStatesKey) ?? []
    }

    func accountNotificationState(for accountID: UUID) -> PersistedAccountNotificationState? {
        accountNotificationStates.first(where: { $0.accountID == accountID })
    }

    func updateAccountNotificationState(
        for accountID: UUID,
        mutate: (inout PersistedAccountNotificationState) -> Void
    ) {
        if let index = accountNotificationStates.firstIndex(where: { $0.accountID == accountID }) {
            var updated = accountNotificationStates[index]
            mutate(&updated)
            accountNotificationStates[index] = updated
            return
        }

        var state = PersistedAccountNotificationState(accountID: accountID)
        mutate(&state)
        accountNotificationStates.append(state)
        accountNotificationStates.sort { $0.accountID.uuidString < $1.accountID.uuidString }
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

    private static func loadCodable<T: Codable>(from userDefaults: UserDefaults, key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor
@Observable
final class AppSettings {
    let menuPreferences: MenuPreferencesStore
    let statusBarPreferences: StatusBarPreferencesStore
    let remoteHostSettings: RemoteHostSettingsStore
    let notificationPreferences: NotificationPreferencesStore
    let notificationState: NotificationStateStore

    init(userDefaults: UserDefaults = .standard) {
        menuPreferences = MenuPreferencesStore(userDefaults: userDefaults)
        statusBarPreferences = StatusBarPreferencesStore(userDefaults: userDefaults)
        remoteHostSettings = RemoteHostSettingsStore(userDefaults: userDefaults)
        notificationPreferences = NotificationPreferencesStore(userDefaults: userDefaults)
        notificationState = NotificationStateStore(userDefaults: userDefaults)
    }

    var refreshIntervalMinutes: Int {
        get { menuPreferences.refreshIntervalMinutes }
        set { menuPreferences.refreshIntervalMinutes = newValue }
    }

    var visibleInactiveAccountCount: Int {
        get { menuPreferences.visibleInactiveAccountCount }
        set { menuPreferences.visibleInactiveAccountCount = newValue }
    }

    var statusBarIndicatorStyle: StatusBarIndicatorStyle {
        get { statusBarPreferences.statusBarIndicatorStyle }
        set { statusBarPreferences.statusBarIndicatorStyle = newValue }
    }

    var statusBarMonochrome: Bool {
        get { statusBarPreferences.statusBarMonochrome }
        set { statusBarPreferences.statusBarMonochrome = newValue }
    }

    var statusBarDisplayMode: StatusBarDisplayMode {
        get { statusBarPreferences.statusBarDisplayMode }
        set { statusBarPreferences.statusBarDisplayMode = newValue }
    }

    var progressAccentColor: NSColor {
        get { statusBarPreferences.progressAccentColor }
        set { statusBarPreferences.progressAccentColor = newValue }
    }

    var hasCustomProgressAccentColor: Bool {
        statusBarPreferences.hasCustomProgressAccentColor
    }

    var remoteHostStates: [PersistedRemoteHostState] {
        get { remoteHostSettings.remoteHostStates }
        set { remoteHostSettings.remoteHostStates = newValue }
    }

    var configuredRemoteHost: RemoteHost? {
        get { remoteHostSettings.configuredRemoteHost }
        set { remoteHostSettings.configuredRemoteHost = newValue }
    }

    var remoteHostInstalledAccountIDs: [UUID] {
        get { remoteHostSettings.remoteHostInstalledAccountIDs }
        set { remoteHostSettings.remoteHostInstalledAccountIDs = newValue }
    }

    var remoteHostActiveAccount: CodexAccount? {
        get { remoteHostSettings.remoteHostActiveAccount }
        set { remoteHostSettings.remoteHostActiveAccount = newValue }
    }

    var remoteHostDesiredAccountID: UUID? {
        get { remoteHostSettings.remoteHostDesiredAccountID }
        set { remoteHostSettings.remoteHostDesiredAccountID = newValue }
    }

    var notificationsWhenBlockedEnabled: Bool {
        get { notificationPreferences.notificationsWhenBlockedEnabled }
        set { notificationPreferences.notificationsWhenBlockedEnabled = newValue }
    }

    var notificationsWhenOutEnabled: Bool {
        get { notificationPreferences.notificationsWhenOutEnabled }
        set { notificationPreferences.notificationsWhenOutEnabled = newValue }
    }

    var accountNotificationStates: [PersistedAccountNotificationState] {
        get { notificationState.accountNotificationStates }
        set { notificationState.accountNotificationStates = newValue }
    }

    var refreshIntervalOptions: [Int] {
        menuPreferences.refreshIntervalOptions
    }

    var visibleInactiveAccountCountOptions: [Int] {
        menuPreferences.visibleInactiveAccountCountOptions
    }

    func resetProgressAccentColor() {
        statusBarPreferences.resetProgressAccentColor()
    }

    func upsertRemoteHost(_ host: RemoteHost) {
        remoteHostSettings.upsertRemoteHost(host)
    }

    func removeRemoteHost(destination: String) {
        remoteHostSettings.removeRemoteHost(destination: destination)
    }

    func remoteHostState(for destination: String) -> PersistedRemoteHostState? {
        remoteHostSettings.remoteHostState(for: destination)
    }

    func updateRemoteHostState(for host: RemoteHost, mutate: (inout PersistedRemoteHostState) -> Void) {
        remoteHostSettings.updateRemoteHostState(for: host, mutate: mutate)
    }

    func accountNotificationState(for accountID: UUID) -> PersistedAccountNotificationState? {
        notificationState.accountNotificationState(for: accountID)
    }

    func updateAccountNotificationState(
        for accountID: UUID,
        mutate: (inout PersistedAccountNotificationState) -> Void
    ) {
        notificationState.updateAccountNotificationState(for: accountID, mutate: mutate)
    }
}
