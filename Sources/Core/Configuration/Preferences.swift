import Foundation
import os

/// One group of settings, stored as one JSON value under `key`. A field that is missing or no longer decodes takes
/// its default, so adding or changing a field keeps the rest of the group.
protocol SettingsGroup: Codable, Equatable, Sendable {
    static var key: String { get }
    static var defaults: Self { get }
    /// The group as rusage stored it before settings were grouped, one flat key per field. Read while `key` is
    /// missing, so nothing has to be migrated.
    static func legacy(in userDefaults: UserDefaults) -> Self
}

/// The `UserDefaults` codec. It is the only code that reads or writes settings, and it holds no copies.
///
///   "settings.general.v1"     JSON GeneralSettings
///   "settings.menuBar.v1"     JSON MenuBarSettings
///   "settings.tokenUsage.v1"  JSON TokenUsageSettings
///   "settings.codex.v1"       JSON CodexSettings
///   "settings.claude.v1"      JSON ClaudeSettings
///   "settings.cursor.v1"      JSON CursorSettings
struct Preferences {
    let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    /// The stored group. A missing value gives the legacy keys' value, and one that no longer decodes gives the
    /// defaults.
    func load<Group: SettingsGroup>(_ group: Group.Type) -> Group {
        guard let data = userDefaults.data(forKey: Group.key) else { return Group.legacy(in: userDefaults) }
        do {
            return try JSONDecoder().decode(Group.self, from: data)
        } catch {
            preferencesLogger.error("Stored \(Group.key, privacy: .public) no longer decodes; using defaults")
            return Group.defaults
        }
    }

    func save<Group: SettingsGroup>(_ settings: Group) {
        do {
            userDefaults.set(try JSONEncoder().encode(settings), forKey: Group.key)
        } catch {
            preferencesLogger.fault("Failed to encode \(Group.key, privacy: .public)")
        }
    }
}

private let preferencesLogger = Logger(subsystem: "com.raphhgg.rusage", category: "Preferences")

extension KeyedDecodingContainer {
    /// The stored value, or `fallback` when it is missing or no longer decodes.
    func value<Value: Decodable>(_ key: Key, or fallback: Value) -> Value {
        (try? decodeIfPresent(Value.self, forKey: key)) ?? fallback
    }
}
