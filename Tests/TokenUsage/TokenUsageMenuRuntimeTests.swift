import Foundation
import Testing

@testable import CodexPill

@MainActor
struct TokenUsageMenuRuntimeTests {
    @Test
    func keepsOneRefreshForSamePeriod() async throws {
        let provider = TokenUsageRuntimeProviderProbe()
        var stateChanges: [TokenUsageMenuLoadState] = []
        let runtime = TokenUsageMenuRuntime(provider: provider) { state in
            stateChanges.append(state)
        }

        runtime.refreshIfNeeded(period: .last30Days, peakScope: .currentPeriod)
        runtime.refreshIfNeeded(period: .last30Days, peakScope: .currentPeriod)

        await waitUntil { await provider.loadCount == 1 }

        let buckets = [
            dailyUsage(daysAgo: 0, totalTokens: 108_637_804)
        ]
        await provider.finish(with: buckets)
        await waitUntil {
            stateChanges.contains(.loaded(TokenUsageMenuLoadedData(buckets: buckets, allTimePeak: nil)))
        }

        #expect(await provider.loadPeriods == [.last30Days])
        #expect(runtime.loadState == .loaded(TokenUsageMenuLoadedData(buckets: buckets, allTimePeak: nil)))
    }

    @Test
    func reusesLoadedDataBeforeFreshnessInterval() async throws {
        var now = Date(timeIntervalSince1970: 1_716_192_000)
        let provider = TokenUsageRuntimeProviderProbe()
        let runtime = TokenUsageMenuRuntime(
            provider: provider,
            freshnessInterval: 15 * 60,
            now: { now }
        ) { _ in }

        runtime.refreshIfNeeded(period: .last30Days, peakScope: .currentPeriod)
        await waitUntil { await provider.loadCount == 1 }

        let buckets = [
            dailyUsage(daysAgo: 0, totalTokens: 108_637_804)
        ]
        await provider.finish(with: buckets)
        await waitUntil {
            runtime.loadState == .loaded(TokenUsageMenuLoadedData(buckets: buckets, allTimePeak: nil))
        }

        now = now.addingTimeInterval((15 * 60) - 1)
        runtime.refreshIfNeeded(period: .last30Days, peakScope: .currentPeriod)
        await Task.yield()

        #expect(await provider.loadPeriods == [.last30Days])
        #expect(runtime.loadState == .loaded(TokenUsageMenuLoadedData(buckets: buckets, allTimePeak: nil)))
    }

    @Test
    func refreshesLoadedDataAfterFreshnessInterval() async throws {
        var now = Date(timeIntervalSince1970: 1_716_192_000)
        let provider = TokenUsageRuntimeProviderProbe()
        let runtime = TokenUsageMenuRuntime(
            provider: provider,
            freshnessInterval: 15 * 60,
            now: { now }
        ) { _ in }

        runtime.refreshIfNeeded(period: .last30Days, peakScope: .currentPeriod)
        await waitUntil { await provider.loadCount == 1 }

        let firstBuckets = [
            dailyUsage(daysAgo: 0, totalTokens: 108_637_804)
        ]
        await provider.finish(with: firstBuckets)
        await waitUntil {
            runtime.loadState == .loaded(TokenUsageMenuLoadedData(buckets: firstBuckets, allTimePeak: nil))
        }

        now = now.addingTimeInterval(15 * 60)
        runtime.refreshIfNeeded(period: .last30Days, peakScope: .currentPeriod)

        await waitUntil { await provider.loadCount == 2 }
        #expect(await provider.loadPeriods == [.last30Days, .last30Days])
        #expect(await provider.forceRefreshValues == [false, true])
    }

    @Test
    func refreshesLoadedDataWhenLocalDayChangesEvenBeforeFreshnessInterval() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 60 * 60) ?? .current
        var now = date(2026, 5, 20, 23, 58, calendar: calendar)
        let provider = TokenUsageRuntimeProviderProbe()
        let runtime = TokenUsageMenuRuntime(
            provider: provider,
            freshnessInterval: 15 * 60,
            calendar: calendar,
            now: { now }
        ) { _ in }

        runtime.refreshIfNeeded(period: .last30Days, peakScope: .currentPeriod)
        await waitUntil { await provider.loadCount == 1 }
        await provider.finish(with: [dailyUsage(daysAgo: 0, totalTokens: 100)])
        await waitUntil { runtime.loadState.hasCachedData }

        now = date(2026, 5, 21, 0, 1, calendar: calendar)
        runtime.refreshIfNeeded(period: .last30Days, peakScope: .currentPeriod)

        await waitUntil { await provider.loadCount == 2 }
        #expect(await provider.loadPeriods == [.last30Days, .last30Days])
        #expect(await provider.forceRefreshValues == [false, true])
    }

    @Test
    func switchingToAllTimePeakKeepsLoadedChartWhileHistoricalPeakScans() async throws {
        let provider = TokenUsageRuntimeProviderProbe()
        let runtime = TokenUsageMenuRuntime(provider: provider) { _ in }

        runtime.refreshIfNeeded(period: .last30Days, peakScope: .currentPeriod)
        await waitUntil { await provider.loadCount == 1 }

        let buckets = [
            dailyUsage(daysAgo: 0, totalTokens: 108_637_804)
        ]
        await provider.finish(with: buckets)
        await waitUntil {
            runtime.loadState == .loaded(TokenUsageMenuLoadedData(buckets: buckets, allTimePeak: nil))
        }

        runtime.handlePeriodChange(period: .last30Days, peakScope: .allTime)
        await waitUntil { await provider.loadCount == 2 }

        guard case .loaded(let scanningData) = runtime.loadState else {
            Issue.record("Expected all-time peak scan to preserve the existing chart")
            return
        }
        #expect(scanningData.buckets == buckets)
        #expect(scanningData.allTimePeak == nil)
        #expect(scanningData.allTimePeakProgress?.scannedFiles == 1)

        let historicalPeak = dailyUsage(daysAgo: 120, totalTokens: 9_800_000_000)
        await provider.finish(with: TokenUsageMenuLoadedData(buckets: buckets, allTimePeak: historicalPeak))
        await waitUntil {
            runtime.loadState == .loaded(TokenUsageMenuLoadedData(buckets: buckets, allTimePeak: historicalPeak))
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping () async -> Bool
    ) async {
        let start = ContinuousClock.now
        while await !condition() {
            if ContinuousClock.now - start > timeout {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func dailyUsage(daysAgo: Int, totalTokens: Int) -> CodexDailyTokenUsage {
        let day = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -daysAgo,
            to: Date(timeIntervalSince1970: 1_716_192_000)
        ) ?? Date(timeIntervalSince1970: 1_716_192_000)
        return CodexDailyTokenUsage(
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

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}

private actor TokenUsageRuntimeProviderProbe: TokenUsageMenuProviding {
    private(set) var loadPeriods: [CodexTokenUsagePeriod] = []
    private(set) var forceRefreshValues: [Bool] = []
    private var loadContinuation: CheckedContinuation<TokenUsageMenuLoadState, Never>?

    func load(
        period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        forceRefresh: Bool,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState {
        loadPeriods.append(period)
        forceRefreshValues.append(forceRefresh)
        progress(TokenUsageScanProgress(scannedFiles: 0, totalFiles: 2))
        progress(TokenUsageScanProgress(scannedFiles: 1, totalFiles: 2))
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func finish(with buckets: [CodexDailyTokenUsage]) {
        finish(with: TokenUsageMenuLoadedData(buckets: buckets, allTimePeak: nil))
    }

    func finish(with data: TokenUsageMenuLoadedData) {
        loadContinuation?.resume(returning: .loaded(data))
        loadContinuation = nil
    }

    var loadCount: Int {
        loadPeriods.count
    }
}
