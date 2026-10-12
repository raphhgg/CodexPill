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

    var breakdown: TokenUsageBreakdown {
        didSet {
            userDefaults.set(breakdown.rawValue, forKey: Self.breakdownKey)
        }
    }

    /// Draws the card in shades of the text color, with dashes and marker shapes telling the tools apart.
    var isMonochrome: Bool {
        didSet {
            userDefaults.set(isMonochrome, forKey: Self.monochromeKey)
        }
    }

    var peakScope: TokenUsagePeakScope {
        didSet {
            userDefaults.set(peakScope.rawValue, forKey: Self.peakScopeKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let isEnabledKey = "tokenUsageEnabled"
    private static let periodKey = "tokenUsagePeriod"
    private static let chartStyleKey = "tokenUsageChartStyle"
    private static let breakdownKey = "tokenUsageBreakdown"
    private static let monochromeKey = "tokenUsageMonochrome"
    private static let peakScopeKey = "tokenUsagePeakScope"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        isEnabled = userDefaults.object(forKey: Self.isEnabledKey) as? Bool ?? false
        period = .last30Days
        userDefaults.set(CodexTokenUsagePeriod.last30Days.rawValue, forKey: Self.periodKey)
        chartStyle = TokenUsageChartStyle(storedValue: userDefaults.string(forKey: Self.chartStyleKey))
        breakdown = TokenUsageBreakdown(storedValue: userDefaults.string(forKey: Self.breakdownKey))
        isMonochrome = userDefaults.bool(forKey: Self.monochromeKey)
        peakScope = userDefaults.string(forKey: Self.peakScopeKey)
            .flatMap(TokenUsagePeakScope.init(rawValue:)) ?? .currentPeriod
    }
}
