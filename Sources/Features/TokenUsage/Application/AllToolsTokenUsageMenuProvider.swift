import Foundation

/// A tool other than Codex that can add its daily tokens to the Token Usage card.
struct TokenUsageToolSource: Sendable {
    enum Reading: Sendable {
        case days([ToolDailyTokenUsage])
        case unavailable
    }

    let tool: TokenUsageTool
    /// Only tools the user connected in rusage are read.
    let isConnected: @Sendable () -> Bool
    let read: @Sendable (DateInterval) async -> Reading
}

/// Adds connected tools' daily tokens to the Codex token usage load.
///
/// Codex keeps its own scan, cache, and all-time peak. The other tools are read for the visible period on
/// each load. The runtime calls `load` at most once per freshness interval.
struct AllToolsTokenUsageMenuProvider: TokenUsageMenuProviding {
    let codex: any TokenUsageMenuProviding
    let otherTools: [TokenUsageToolSource]
    var calendar: Calendar = .current
    var now: @Sendable () -> Date = { Date() }

    func load(
        period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        forceRefresh: Bool,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState {
        let interval = ToolTokenUsageDays.interval(dayCount: period.dayCount, endingAt: now(), calendar: calendar)
        // Codex's scan reports the card's progress, so it starts while the other tools are read.
        async let codexLoad = codex.load(period: period, peakScope: peakScope, forceRefresh: forceRefresh, progress: progress)
        var otherSeries: [ToolTokenUsageSeries] = []
        var unavailableTools: [TokenUsageTool] = []
        for source in otherTools where source.isConnected() {
            switch await source.read(interval) {
            case .days(let days):
                otherSeries.append(ToolTokenUsageSeries(tool: source.tool, days: days))
            case .unavailable:
                unavailableTools.append(source.tool)
            }
        }

        let codexState = await codexLoad
        if case .loading = codexState {
            return codexState
        }

        var data = TokenUsageMenuLoadedData(buckets: [], allTimePeak: nil)
        if case .loaded(let codexData) = codexState {
            data = codexData
            data.tools = [Self.codexSeries(from: codexData.buckets, in: interval, calendar: calendar)]
        } else {
            data.unavailableTools = [.codex]
        }
        data.tools += otherSeries
        data.unavailableTools += unavailableTools

        if data.tools.isEmpty {
            return .unavailable
        }
        return .loaded(data)
    }

    /// Codex's cached days, and an empty series for each connected tool so the card knows which tools to expect.
    func preview(period: CodexTokenUsagePeriod) async -> TokenUsageMenuLoadedData? {
        let interval = ToolTokenUsageDays.interval(dayCount: period.dayCount, endingAt: now(), calendar: calendar)
        var data = await codex.preview(period: period) ?? TokenUsageMenuLoadedData(buckets: [], allTimePeak: nil)
        let emptyDays = ToolTokenUsageDays.filled([], in: interval, calendar: calendar)
        data.tools = [Self.codexSeries(from: data.buckets, in: interval, calendar: calendar)]
            + otherTools.filter { $0.isConnected() }.map { ToolTokenUsageSeries(tool: $0.tool, days: emptyDays) }
        return data
    }

    static func codexSeries(
        from buckets: [CodexDailyTokenUsage],
        in interval: DateInterval,
        calendar: Calendar
    ) -> ToolTokenUsageSeries {
        let usage = buckets.map { bucket in
            ToolDailyTokenUsage(
                day: bucket.day,
                tokensByModel: bucket.tokensByModel
                    ?? (bucket.usage.totalTokens > 0 ? [CodexSessionTokenUsageScanner.unknownModel: bucket.usage.totalTokens] : [:])
            )
        }
        return ToolTokenUsageSeries(tool: .codex, days: ToolTokenUsageDays.filled(usage, in: interval, calendar: calendar))
    }
}

/// Claude Code's daily tokens from local transcripts, with scanned files cached on disk.
actor ClaudeCodeTokenUsageHistory {
    private struct CacheEntry: Codable {
        var fileContributions: [ClaudeTokenUsageFileContribution]
    }

    private static let cacheKey = "files"

    private let scanner: ClaudeSessionTokenUsageScanner
    private let projectsDirectory: URL
    private let cacheStore: TokenUsageCacheFileStore<CacheEntry>
    private let now: @Sendable () -> Date
    private var contributions: [ClaudeTokenUsageFileContribution]?

    init(
        scanner: ClaudeSessionTokenUsageScanner = ClaudeSessionTokenUsageScanner(),
        projectsDirectory: URL,
        cacheFile: URL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scanner = scanner
        self.projectsDirectory = projectsDirectory
        cacheStore = TokenUsageCacheFileStore(cacheFile: cacheFile, schemaVersion: 1)
        self.now = now
    }

    func read(_ interval: DateInterval) -> TokenUsageToolSource.Reading {
        let cached = contributions ?? cacheStore.readEntries().first?.fileContributions ?? []
        do {
            let result = try scanner.scan(
                projectsDirectory: projectsDirectory,
                interval: interval,
                cachedFileContributions: cached,
                now: now()
            )
            if result.fileContributions != cached {
                // Derived data: a failed write only means the next launch reads the files again.
                try? cacheStore.writeEntry(CacheEntry(fileContributions: result.fileContributions), forKey: Self.cacheKey)
            }
            contributions = result.fileContributions
            return .days(result.days)
        } catch {
            return .unavailable
        }
    }
}

extension TokenUsageToolSource {
    static func claudeCode(history: ClaudeCodeTokenUsageHistory, settings: ClaudeUsageSettingsStore) -> TokenUsageToolSource {
        TokenUsageToolSource(
            tool: .claudeCode,
            isConnected: { settings.isEnabled },
            read: { interval in await history.read(interval) }
        )
    }

    static func cursor(client: CursorTokenUsageClient, settings: CursorUsageSettingsStore) -> TokenUsageToolSource {
        TokenUsageToolSource(
            tool: .cursor,
            isConnected: { settings.isEnabled },
            read: { interval in
                do {
                    return .days(try await client.dailyUsage(in: interval))
                } catch {
                    return .unavailable
                }
            }
        )
    }
}
