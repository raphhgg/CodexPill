import Foundation
import Testing

@testable import CodexPill

struct TokenUsageCacheBackedRefreshPolicyTests {
    @Test
    func displayRequiresCoveredWindowButRefreshCanReuseOverlappingWindow() {
        let calendar = utcCalendar()
        let policy = TokenUsageCacheBackedRefreshPolicy(calendar: calendar)
        let entry = TokenUsageCacheEntry(
            period: .last30Days,
            generatedAt: makeDate(2026, 5, 30),
            buckets: buckets(from: makeDate(2026, 5, 1), count: 30),
            fileContributions: [
                CodexSessionTokenUsageFileContribution(
                    cacheKey: "2026/05/30/session.jsonl",
                    day: makeDate(2026, 5, 30),
                    fileSize: 10,
                    modificationDate: nil,
                    buckets: [dailyUsage(makeDate(2026, 5, 30), totalTokens: 100)],
                    summary: CodexSessionTokenUsageScanSummary(
                        filesRead: 1,
                        tokenCountRowsRead: 1,
                        cumulativeRowsUsed: 0,
                        cumulativeRowsIgnored: 0,
                        malformedRowsIgnored: 0,
                        nonUsageRowsIgnored: 0
                    )
                )
            ],
            allTimePeak: nil,
            allTimePeakCoversAllHistory: nil
        )
        let now = makeDate(2026, 5, 31)

        #expect(policy.canDisplay(entry, for: .last30Days, peakScope: .currentPeriod, now: now) == false)
        #expect(policy.canSeedRefresh(entry, for: .last30Days, peakScope: .currentPeriod, now: now))
    }

    private func buckets(from start: Date, count: Int) -> [CodexDailyTokenUsage] {
        let calendar = utcCalendar()
        return (0..<count).map { offset in
            dailyUsage(
                calendar.date(byAdding: .day, value: offset, to: start) ?? start,
                totalTokens: offset
            )
        }
    }

    private func dailyUsage(_ day: Date, totalTokens: Int) -> CodexDailyTokenUsage {
        CodexDailyTokenUsage(
            day: day,
            usage: CodexTokenUsageTotals(
                inputTokens: 0,
                cachedInputTokens: 0,
                outputTokens: 0,
                reasoningOutputTokens: 0,
                totalTokens: totalTokens
            )
        )
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(
            calendar: utcCalendar(),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day
        ).date!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
