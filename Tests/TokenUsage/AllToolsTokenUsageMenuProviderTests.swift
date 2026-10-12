import Foundation
import Testing

@testable import Refill

struct AllToolsTokenUsageMenuProviderTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test
    func addsConnectedToolsAndStacksThemInTheCard() async throws {
        let now = day(2026, 10, 10)
        let interval = ToolTokenUsageDays.interval(dayCount: 30, endingAt: now, calendar: calendar)
        let codexBuckets = ToolTokenUsageDays.filled([], in: interval, calendar: calendar).map {
            CodexDailyTokenUsage(day: $0.day, usage: .zero)
        }.dropLast() + [CodexDailyTokenUsage(
            day: now,
            usage: CodexTokenUsageTotals(inputTokens: 80, cachedInputTokens: 0, outputTokens: 20, reasoningOutputTokens: 0, totalTokens: 100),
            tokensByModel: ["gpt-a": 75, "gpt-b": 25]
        )]
        let provider = AllToolsTokenUsageMenuProvider(
            codex: FixedCodexProvider(state: .loaded(TokenUsageMenuLoadedData(buckets: Array(codexBuckets), allTimePeak: nil))),
            otherTools: [
                TokenUsageToolSource(tool: .claudeCode, isConnected: { true }, read: { interval in
                    .days(ToolTokenUsageDays.filled([ToolDailyTokenUsage(day: now, tokensByModel: ["claude-opus": 300])], in: interval, calendar: calendar))
                }),
                TokenUsageToolSource(tool: .cursor, isConnected: { true }, read: { _ in .unavailable }),
                TokenUsageToolSource(tool: .cursor, isConnected: { false }, read: { _ in Issue.record("read while disconnected"); return .unavailable })
            ],
            calendar: calendar,
            now: { now }
        )

        let state = await provider.load(period: .last30Days, peakScope: .currentPeriod, forceRefresh: false) { _ in }
        let card = TokenUsageMenuCard.make(period: .last30Days, loadState: state, calendar: calendar, now: now)

        #expect(card.days.count == 30)
        #expect(card.todayTokenCount == 400)
        #expect(card.tokenCount(for: .codex, onDay: 29) == 100)
        #expect(card.tokenCount(for: .claudeCode, onDay: 29) == 300)
        #expect(card.toolSummaries.map(\.tool) == [.codex, .claudeCode, .cursor])
        #expect(card.toolSummaries[0].models.map(\.name) == ["GPT-a", "GPT-b"])
        #expect(card.toolSummaries[1].periodTokenCount == 300)
        #expect(card.toolSummaries[2].isUnavailable)
    }

    @Test
    func codexOnlyKeepsTheSingleToolCard() async {
        let provider = AllToolsTokenUsageMenuProvider(
            codex: FixedCodexProvider(state: .loaded(TokenUsageMenuLoadedData(buckets: [], allTimePeak: nil))),
            otherTools: [TokenUsageToolSource(tool: .claudeCode, isConnected: { false }, read: { _ in .unavailable })],
            calendar: calendar,
            now: { day(2026, 10, 10) }
        )

        let state = await provider.load(period: .last30Days, peakScope: .currentPeriod, forceRefresh: false) { _ in }
        let card = TokenUsageMenuCard.make(period: .last30Days, loadState: state, calendar: calendar, now: day(2026, 10, 10))

        #expect(card.toolSummaries.map(\.tool) == [.codex])
    }

    @Test
    func showsOtherToolsWhenCodexIsUnavailable() async {
        let provider = AllToolsTokenUsageMenuProvider(
            codex: FixedCodexProvider(state: .unavailable),
            otherTools: [TokenUsageToolSource(tool: .claudeCode, isConnected: { true }, read: { interval in
                .days(ToolTokenUsageDays.filled([], in: interval, calendar: calendar))
            })],
            calendar: calendar,
            now: { day(2026, 10, 10) }
        )

        let state = await provider.load(period: .last30Days, peakScope: .currentPeriod, forceRefresh: false) { _ in }
        let card = TokenUsageMenuCard.make(period: .last30Days, loadState: state, calendar: calendar, now: day(2026, 10, 10))

        #expect(card.toolSummaries.map(\.tool) == [.codex, .claudeCode])
        #expect(card.toolSummaries.first?.isUnavailable == true)
    }

    @Test
    func codexProgressCarriesTheToolsAlreadyRead() async {
        let now = day(2026, 10, 10)
        let recorder = TokenUsageProgressRecorder()
        let provider = AllToolsTokenUsageMenuProvider(
            codex: ProgressingCodexProvider(),
            otherTools: [
                TokenUsageToolSource(tool: .claudeCode, isConnected: { true }, read: { interval in
                    .days(ToolTokenUsageDays.filled([ToolDailyTokenUsage(day: now, tokensByModel: ["claude-opus-5-5": 7])], in: interval, calendar: calendar))
                }),
                TokenUsageToolSource(tool: .cursor, isConnected: { true }, read: { _ in .unavailable }),
            ],
            calendar: calendar,
            now: { now }
        )

        _ = await provider.load(period: .last30Days, peakScope: .currentPeriod, forceRefresh: false) { recorder.append($0) }

        let progress = recorder.updates.first
        #expect(progress?.otherTools.map(\.tool) == [.claudeCode])
        #expect(progress?.otherTools.first?.totalTokens == 7)
        #expect(progress?.unavailableTools == [.cursor])
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private struct FixedCodexProvider: TokenUsageMenuProviding {
    let state: TokenUsageMenuLoadState

    func load(
        period _: CodexTokenUsagePeriod,
        peakScope _: TokenUsagePeakScope,
        forceRefresh _: Bool,
        progress _: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState {
        state
    }
}

private struct ProgressingCodexProvider: TokenUsageMenuProviding {
    func load(
        period _: CodexTokenUsagePeriod,
        peakScope _: TokenUsagePeakScope,
        forceRefresh _: Bool,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState {
        progress(TokenUsageScanProgress(scannedFiles: 1, totalFiles: 2))
        return .loaded(TokenUsageMenuLoadedData(buckets: [], allTimePeak: nil))
    }
}
