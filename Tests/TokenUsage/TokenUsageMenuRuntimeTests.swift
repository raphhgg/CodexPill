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

        runtime.refreshIfNeeded(period: .last30Days)
        runtime.refreshIfNeeded(period: .last30Days)

        await waitUntil { await provider.loadCount == 1 }

        let buckets = [
            dailyUsage(daysAgo: 0, totalTokens: 108_637_804)
        ]
        await provider.finish(with: buckets)
        await waitUntil {
            stateChanges.contains(.loaded(buckets))
        }

        #expect(await provider.loadPeriods == [.last30Days])
        #expect(runtime.loadState == .loaded(buckets))
    }

    @Test
    func doesNotRefreshLoadedDataForMenuReopen() async throws {
        let provider = TokenUsageRuntimeProviderProbe()
        let runtime = TokenUsageMenuRuntime(provider: provider) { _ in }

        runtime.refreshIfNeeded(period: .last30Days)
        await waitUntil { await provider.loadCount == 1 }

        let buckets = [
            dailyUsage(daysAgo: 0, totalTokens: 108_637_804)
        ]
        await provider.finish(with: buckets)
        await waitUntil {
            runtime.loadState == .loaded(buckets)
        }

        runtime.refreshIfNeeded(period: .last30Days)
        await Task.yield()

        #expect(await provider.loadPeriods == [.last30Days])
        #expect(runtime.loadState == .loaded(buckets))
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
}

private actor TokenUsageRuntimeProviderProbe: TokenUsageMenuProviding {
    private(set) var loadPeriods: [CodexTokenUsagePeriod] = []
    private var loadContinuation: CheckedContinuation<TokenUsageMenuLoadState, Never>?

    func load(
        period: CodexTokenUsagePeriod,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState {
        loadPeriods.append(period)
        progress(TokenUsageScanProgress(scannedFiles: 0, totalFiles: 2))
        progress(TokenUsageScanProgress(scannedFiles: 1, totalFiles: 2))
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func finish(with buckets: [CodexDailyTokenUsage]) {
        loadContinuation?.resume(returning: .loaded(buckets))
        loadContinuation = nil
    }

    var loadCount: Int {
        loadPeriods.count
    }
}
