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
            guard period == .last30Days else {
                period = .last30Days
                userDefaults.set(CodexTokenUsagePeriod.last30Days.rawValue, forKey: Self.periodKey)
                return
            }
            userDefaults.set(period.rawValue, forKey: Self.periodKey)
        }
    }

    var chartStyle: TokenUsageChartStyle {
        didSet {
            userDefaults.set(chartStyle.rawValue, forKey: Self.chartStyleKey)
        }
    }

    var loadingAnimationStyle: TokenUsageLoadingAnimationStyle {
        didSet {
            userDefaults.set(loadingAnimationStyle.rawValue, forKey: Self.loadingAnimationStyleKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let isEnabledKey = "tokenUsageEnabled"
    private static let periodKey = "tokenUsagePeriod"
    private static let chartStyleKey = "tokenUsageChartStyle"
    private static let loadingAnimationStyleKey = "tokenUsageLoadingAnimationStyle"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        isEnabled = userDefaults.object(forKey: Self.isEnabledKey) as? Bool ?? false
        period = .last30Days
        userDefaults.set(CodexTokenUsagePeriod.last30Days.rawValue, forKey: Self.periodKey)
        chartStyle = userDefaults.string(forKey: Self.chartStyleKey)
            .flatMap(TokenUsageChartStyle.init(rawValue:)) ?? .dailyBars
        loadingAnimationStyle = userDefaults.string(forKey: Self.loadingAnimationStyleKey)
            .flatMap(TokenUsageLoadingAnimationStyle.init(rawValue:)) ?? .waves
    }
}
