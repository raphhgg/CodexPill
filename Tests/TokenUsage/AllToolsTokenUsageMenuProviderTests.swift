import Foundation
import Testing

@testable import CodexPill

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
        let card = TokenUsageMenuCard.make(style: .dailyBars, period: .last30Days, loadState: state, calendar: calendar)

        #expect(card.showsTools)
        #expect(card.buckets.count == 30)
        #expect(card.todayTokenCount == 400)
        #expect(card.buckets.last?.segments == [
            TokenUsageBarSegment(tool: .codex, tokenCount: 100),
            TokenUsageBarSegment(tool: .claudeCode, tokenCount: 300)
        ])
        #expect(card.toolSummaries.map(\.tool) == [.codex, .claudeCode, .cursor])
        #expect(card.toolSummaries[0].modelsSummary == "gpt-a 75% · gpt-b 25%")
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
        let card = TokenUsageMenuCard.make(style: .dailyBars, period: .last30Days, loadState: state, calendar: calendar)

        #expect(!card.showsTools)
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
        let card = TokenUsageMenuCard.make(style: .dailyBars, period: .last30Days, loadState: state, calendar: calendar)

        #expect(card.toolSummaries.map(\.tool) == [.claudeCode, .codex])
        #expect(card.toolSummaries.last?.isUnavailable == true)
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
