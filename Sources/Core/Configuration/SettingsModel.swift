import Foundation
import Observation
import os

/// The single writer of every settings group. Each change is saved as it happens. The groups the menu reads are
/// observed whole, so a new field needs no new observation.
@MainActor
@Observable
final class SettingsModel {
    var general: GeneralSettings {
        didSet { save(general, replacing: oldValue) }
    }

    var menuBar: MenuBarSettings {
        didSet { save(menuBar, replacing: oldValue) }
    }

    var tokenUsage: TokenUsageSettings {
        didSet { save(tokenUsage, replacing: oldValue) }
    }

    var codex: CodexSettings {
        didSet { save(codex, replacing: oldValue) }
    }

    /// Claude's and Cursor's usage sources also read and change their settings off the main actor.
    let claude: SettingsCell<ClaudeSettings>
    let cursor: SettingsCell<CursorSettings>

    @ObservationIgnored private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        general = preferences.load(GeneralSettings.self)
        menuBar = preferences.load(MenuBarSettings.self)
        tokenUsage = preferences.load(TokenUsageSettings.self)
        codex = preferences.load(CodexSettings.self)
        claude = SettingsCell(preferences: preferences)
        cursor = SettingsCell(preferences: preferences)
    }

    convenience init(userDefaults: UserDefaults) {
        self.init(preferences: Preferences(userDefaults: userDefaults))
    }

    private func save<Group: SettingsGroup>(_ settings: Group, replacing old: Group) {
        guard settings != old else { return }
        preferences.save(settings)
    }
}

/// One settings group that code off the main actor reads and changes, such as a usage source checking that its tool
/// is connected. Reads and changes take a lock, and a change is saved before the lock is released, so saves can't
/// land out of order.
final class SettingsCell<Group: SettingsGroup>: Sendable {
    private let preferences: Preferences
    private let state: OSAllocatedUnfairLock<Group>

    init(preferences: Preferences) {
        self.preferences = preferences
        state = OSAllocatedUnfairLock(initialState: preferences.load(Group.self))
    }

    var value: Group {
        state.withLock { $0 }
    }

    func update(_ apply: (inout Group) -> Void) {
        state.withLockUnchecked { stored in
            var updated = stored
            apply(&updated)
            guard updated != stored else { return }
            stored = updated
            preferences.save(updated)
        }
    }
}
