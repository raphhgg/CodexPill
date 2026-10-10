import Foundation

/// A tool other than Codex that can add its daily tokens to the Token Usage card.
struct TokenUsageToolSource: Sendable {
    enum Reading: Sendable {
        case days([ToolDailyTokenUsage])
        case unavailable
    }

    let tool: TokenUsageTool
    /// Only tools the user connected in CodexPill are read.
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
        let codexState = await codex.load(
            period: period,
            peakScope: peakScope,
            forceRefresh: forceRefresh,
            progress: progress
        )
        if case .loading = codexState {
            return codexState
        }

        let interval = ToolTokenUsageDays.interval(dayCount: period.dayCount, endingAt: now(), calendar: calendar)
        var data = TokenUsageMenuLoadedData(buckets: [], allTimePeak: nil)
        if case .loaded(let codexData) = codexState {
            data = codexData
            data.tools = [Self.codexSeries(from: codexData.buckets, in: interval, calendar: calendar)]
        } else {
            data.unavailableTools = [.codex]
        }

        for source in otherTools where source.isConnected() {
            switch await source.read(interval) {
            case .days(let days):
                data.tools.append(ToolTokenUsageSeries(tool: source.tool, days: days))
            case .unavailable:
                data.unavailableTools.append(source.tool)
            }
        }

        if data.tools.isEmpty {
            return .unavailable
        }
        return .loaded(data)
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
