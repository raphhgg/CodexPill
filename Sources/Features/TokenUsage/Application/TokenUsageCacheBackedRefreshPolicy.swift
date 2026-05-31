import Foundation

struct TokenUsageCacheEntry: Codable, Equatable {
    var period: CodexTokenUsagePeriod
    var generatedAt: Date
    var buckets: [CodexDailyTokenUsage]
    var fileContributions: [CodexSessionTokenUsageFileContribution]?
    var allTimePeak: CodexDailyTokenUsage?
    var allTimePeakCoversAllHistory: Bool?

    var hasAllTimePeak: Bool {
        allTimePeak != nil && allTimePeakCoversAllHistory == true
    }

    func coversCurrentWindow(
        for period: CodexTokenUsagePeriod,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard buckets.count >= period.dayCount,
              let firstDay = buckets.first?.day,
              let lastDay = buckets.last?.day
        else {
            return false
        }

        let today = calendar.startOfDay(for: now)
        let firstRequiredDay = calendar.date(
            byAdding: .day,
            value: 1 - period.dayCount,
            to: today
        ) ?? today

        return firstDay <= firstRequiredDay && lastDay == today
    }

    func overlapsCurrentWindow(
        for period: CodexTokenUsagePeriod,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let firstDay = buckets.first?.day,
              let lastDay = buckets.last?.day
        else {
            return false
        }

        let today = calendar.startOfDay(for: now)
        let firstRequiredDay = calendar.date(
            byAdding: .day,
            value: 1 - period.dayCount,
            to: today
        ) ?? today

        return firstDay <= today && lastDay >= firstRequiredDay
    }
}

struct TokenUsageCacheBackedRefreshPolicy: Sendable {
    private let calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    func displayEntry(
        from entries: [TokenUsageCacheEntry],
        covering period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        now: Date
    ) -> TokenUsageCacheEntry? {
        entries
            .filter { canDisplay($0, for: period, peakScope: peakScope, now: now) }
            .sorted { $0.period.dayCount < $1.period.dayCount }
            .first
    }

    func refreshSeedEntry(
        from entries: [TokenUsageCacheEntry],
        covering period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        now: Date
    ) -> TokenUsageCacheEntry? {
        entries
            .filter { canSeedRefresh($0, for: period, peakScope: peakScope, now: now) }
            .sorted { $0.period.dayCount < $1.period.dayCount }
            .first
    }

    func allTimePeak(from entries: [TokenUsageCacheEntry]) -> CodexDailyTokenUsage? {
        entries
            .filter(\.hasAllTimePeak)
            .compactMap(\.allTimePeak)
            .max { $0.usage.totalTokens < $1.usage.totalTokens }
    }

    func canDisplay(
        _ entry: TokenUsageCacheEntry,
        for period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        now: Date
    ) -> Bool {
        entry.period.dayCount >= period.dayCount &&
            (peakScope == .currentPeriod || entry.hasAllTimePeak) &&
            entry.coversCurrentWindow(for: period, now: now, calendar: calendar)
    }

    func canSeedRefresh(
        _ entry: TokenUsageCacheEntry,
        for period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        now: Date
    ) -> Bool {
        entry.fileContributions?.isEmpty == false &&
            entry.period.dayCount >= period.dayCount &&
            (peakScope == .currentPeriod || entry.hasAllTimePeak) &&
            entry.overlapsCurrentWindow(for: period, now: now, calendar: calendar)
    }
}
