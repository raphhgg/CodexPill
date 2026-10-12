import Foundation
import Observation

@MainActor
@Observable
final class MenuDisplaySettingsStore {
    var refreshIntervalMinutes: Int {
        didSet {
            userDefaults.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey)
        }
    }

    /// The order of the tool sections in the menu. The first one drives the menu bar icon.
    var toolOrder: [UsageProvider] {
        didSet {
            userDefaults.set(toolOrder.map(\.rawValue), forKey: Self.toolOrderKey)
        }
    }

    var masksEmails: Bool {
        didSet {
            userDefaults.set(masksEmails, forKey: Self.masksEmailsKey)
        }
    }

    /// Hides the Codex card and stops reading Codex, as Show Tools › Codex unchecked.
    var hidesCodex: Bool {
        didSet {
            userDefaults.set(hidesCodex, forKey: Self.hidesCodexKey)
        }
    }

    let refreshIntervalOptions = [1, 2, 5, 10, 15, 30]
    nonisolated static let defaultToolOrder: [UsageProvider] = [.claude, .codex, .cursor]

    private let userDefaults: UserDefaults

    private static let refreshIntervalKey = "refreshIntervalMinutes"
    private static let toolOrderKey = "toolOrder"
    private static let masksEmailsKey = "masksEmails"
    private static let hidesCodexKey = "hidesCodex"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedRefreshInterval = userDefaults.integer(forKey: Self.refreshIntervalKey)
        refreshIntervalMinutes = refreshIntervalOptions.contains(storedRefreshInterval) ? storedRefreshInterval : 5

        var storedOrder: [UsageProvider] = []
        for provider in (userDefaults.stringArray(forKey: Self.toolOrderKey) ?? []).compactMap(UsageProvider.init(rawValue:))
        where !storedOrder.contains(provider) {
            storedOrder.append(provider)
        }
        toolOrder = storedOrder + Self.defaultToolOrder.filter { !storedOrder.contains($0) }
        masksEmails = userDefaults.bool(forKey: Self.masksEmailsKey)
        hidesCodex = userDefaults.bool(forKey: Self.hidesCodexKey)
    }
}
