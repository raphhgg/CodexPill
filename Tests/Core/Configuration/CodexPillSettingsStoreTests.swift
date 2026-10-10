import Foundation
import Testing

@testable import CodexPill

@MainActor
struct CodexPillSettingsStoreTests {
    @Test
    func pacingMarkersPreferencePersistsAcrossInstances() {
        let defaults = makeDefaults()
        let first = CodexPillSettingsStore(userDefaults: defaults)
        first.pacingMarkersEnabled = false

        let second = CodexPillSettingsStore(userDefaults: defaults)

        #expect(!second.pacingMarkersEnabled)
    }

    @Test
    func tokenUsagePreferencesPersistAcrossInstances() {
        let defaults = makeDefaults()

        let first = CodexPillSettingsStore(userDefaults: defaults)
        first.tokenUsageEnabled = true
        first.tokenUsageChartStyle = .sparkline
        first.tokenUsageLoadingAnimationStyle = .random
        first.tokenUsagePeakScope = .allTime

        let second = CodexPillSettingsStore(userDefaults: defaults)

        #expect(second.tokenUsageEnabled)
        #expect(second.tokenUsageChartStyle == .sparkline)
        #expect(second.tokenUsageLoadingAnimationStyle == .random)
        #expect(second.tokenUsagePeakScope == .allTime)
    }

    @Test
    func tokenUsagePreferencesMigrateHiddenPeriodsToThirtyDays() {
        let defaults = makeDefaults()
        defaults.set(CodexTokenUsagePeriod.last7Days.rawValue, forKey: "tokenUsagePeriod")

        let settings = CodexPillSettingsStore(userDefaults: defaults)

        #expect(settings.tokenUsagePeriod == .last30Days)
        #expect(defaults.object(forKey: "tokenUsagePeriod") as? Int == CodexTokenUsagePeriod.last30Days.rawValue)
    }

    @Test
    func progressAccentColorDefaultAndReset() {
        let defaults = makeDefaults()
        let settings = CodexPillSettingsStore(userDefaults: defaults)

        #expect(settings.progressAccentColor == nil)
        #expect(settings.hasCustomProgressAccentColor == false)

        settings.progressAccentColor = StatusItemAccentColor(red: 0.12, green: 0.45, blue: 0.78, alpha: 1)
        #expect(settings.hasCustomProgressAccentColor)

        settings.resetProgressAccentColor()

        #expect(settings.progressAccentColor == nil)
        #expect(settings.hasCustomProgressAccentColor == false)
    }

    @Test
    func progressAccentColorPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let accent = StatusItemAccentColor(red: 0.14, green: 0.55, blue: 0.31, alpha: 1)

        let first = CodexPillSettingsStore(userDefaults: defaults)
        first.progressAccentColor = accent

        let second = CodexPillSettingsStore(userDefaults: defaults)

        #expect(second.progressAccentColor == accent)
        #expect(second.hasCustomProgressAccentColor)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "CodexPillSettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

}
