import Foundation
import Observation

@MainActor
@Observable
final class TokenUsagePreferencesStore {
    var isEnabled: Bool {
        didSet {
            userDefaults.set(isEnabled, forKey: Self.isEnabledKey)
        }
    }

    var period: CodexTokenUsagePeriod {
        didSet {
            userDefaults.set(period.rawValue, forKey: Self.periodKey)
        }
    }

    var chartStyle: TokenUsageChartStyle {
        didSet {
            userDefaults.set(chartStyle.rawValue, forKey: Self.chartStyleKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let isEnabledKey = "tokenUsageEnabled"
    private static let periodKey = "tokenUsagePeriod"
    private static let chartStyleKey = "tokenUsageChartStyle"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        isEnabled = userDefaults.object(forKey: Self.isEnabledKey) as? Bool ?? false
        period = CodexTokenUsagePeriod(
            rawValue: userDefaults.object(forKey: Self.periodKey) as? Int ?? CodexTokenUsagePeriod.last30Days.rawValue
        ) ?? .last30Days
        chartStyle = userDefaults.string(forKey: Self.chartStyleKey)
            .flatMap(TokenUsageChartStyle.init(rawValue:)) ?? .dailyBars
    }
}
