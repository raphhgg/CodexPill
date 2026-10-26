import Foundation

/// App-wide settings: how often tools refresh, the menu's tool order, email masking and the theme.
struct GeneralSettings: SettingsGroup {
    static let key = "settings.general.v1"
    static let defaults = GeneralSettings()
    static let refreshIntervalOptions = [1, 2, 5, 10, 15, 30]
    static let defaultToolOrder: [UsageProvider] = [.claude, .codex, .cursor]

    /// One of `refreshIntervalOptions`.
    var refreshIntervalMinutes = 5
    /// The order of the tool sections in the menu, every tool once. The first one drives the menu bar icon.
    var toolOrder = GeneralSettings.defaultToolOrder
    var masksEmails = false
    var theme = AppTheme.defaultTheme
}

extension GeneralSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        refreshIntervalMinutes = Self.refreshInterval(container.value(.refreshIntervalMinutes, or: defaults.refreshIntervalMinutes))
        // Decoded as names, so a tool this build doesn't know drops alone instead of the whole order.
        toolOrder = Self.completeToolOrder(container.value(.toolOrder, or: [String]()).compactMap(UsageProvider.init(rawValue:)))
        masksEmails = container.value(.masksEmails, or: defaults.masksEmails)
        theme = container.value(.theme, or: defaults.theme)
    }

    /// `minutes` when it is one of the options, the default otherwise.
    static func refreshInterval(_ minutes: Int) -> Int {
        refreshIntervalOptions.contains(minutes) ? minutes : defaults.refreshIntervalMinutes
    }

    /// `order` without repeats, followed by the tools it leaves out in their default order.
    static func completeToolOrder(_ order: [UsageProvider]) -> [UsageProvider] {
        var complete: [UsageProvider] = []
        for provider in order + defaultToolOrder where !complete.contains(provider) {
            complete.append(provider)
        }
        return complete
    }
}
