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
    func previewHasCodexCachedDaysAndAnEmptySeriesPerConnectedTool() async throws {
        let now = day(2026, 10, 10)
        let yesterday = day(2026, 10, 9)
        let cachedDay = CodexDailyTokenUsage(
            day: yesterday,
            usage: CodexTokenUsageTotals(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 40),
            tokensByModel: ["gpt-a": 40]
        )
        let provider = AllToolsTokenUsageMenuProvider(
            codex: FixedCodexProvider(state: .unavailable, preview: TokenUsageMenuLoadedData(buckets: [cachedDay], allTimePeak: nil)),
            otherTools: [
                TokenUsageToolSource(tool: .claudeCode, isConnected: { true }, read: { _ in Issue.record("read for a preview"); return .unavailable }),
                TokenUsageToolSource(tool: .cursor, isConnected: { false }, read: { _ in .unavailable }),
            ],
            calendar: calendar,
            now: { now }
        )

        let preview = try #require(await provider.preview(period: .last30Days))

        #expect(preview.tools.map(\.tool) == [.codex, .claudeCode])
        #expect(preview.tools.map(\.totalTokens) == [40, 0])
    }

    @Test(.timeLimit(.minutes(1)))
    func reportsCodexProgressWhileOtherToolsAreRead() async {
        let codexReported = TestGate()
        let provider = AllToolsTokenUsageMenuProvider(
            codex: FixedCodexProvider(
                state: .loaded(TokenUsageMenuLoadedData(buckets: [], allTimePeak: nil)),
                progress: TokenUsageScanProgress(scannedFiles: 0, totalFiles: 3)
            ),
            otherTools: [TokenUsageToolSource(tool: .claudeCode, isConnected: { true }, read: { interval in
                await codexReported.pass()
                return .days(ToolTokenUsageDays.filled([], in: interval, calendar: calendar))
            })],
            calendar: calendar,
            now: { day(2026, 10, 10) }
        )
        let progressUpdates = TokenUsageProgressRecorder()

        let state = await provider.load(period: .last30Days, peakScope: .currentPeriod, forceRefresh: false) { progress in
            progressUpdates.append(progress)
            Task { await codexReported.open() }
        }

        #expect(progressUpdates.updates == [TokenUsageScanProgress(scannedFiles: 0, totalFiles: 3)])
        guard case .loaded(let data) = state else {
            Issue.record("Expected the load to finish")
            return
        }
        #expect(data.tools.map(\.tool) == [.codex, .claudeCode])
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private struct FixedCodexProvider: TokenUsageMenuProviding {
    let state: TokenUsageMenuLoadState
    var preview: TokenUsageMenuLoadedData? = nil
    var progress: TokenUsageScanProgress? = nil

    func preview(period _: CodexTokenUsagePeriod) async -> TokenUsageMenuLoadedData? {
        preview
    }

    func load(
        period _: CodexTokenUsagePeriod,
        peakScope _: TokenUsagePeakScope,
        forceRefresh _: Bool,
        progress report: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState {
        progress.map(report)
        return state
    }
}
