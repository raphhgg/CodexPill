import Foundation
import Testing

@testable import CodexPill

struct LocalCodexSessionTokenUsageMenuProviderTests {
    @Test
    func forwardsScanProgressOnColdLoad() async throws {
        let now = makeDate(2026, 5, 20)
        let root = try makeSessionRoot(files: [
            "2026/05/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":100}}}
            """,
            "2026/05/19/session-b.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":200}}}
            """
        ])
        let provider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile(under: root),
            now: { now },
            calendar: utcCalendar()
        )
        var progressUpdates: [TokenUsageScanProgress] = []

        _ = await provider.load(period: .last7Days) { progressUpdates.append($0) }

        #expect(progressUpdates.first == TokenUsageScanProgress(scannedFiles: 0, totalFiles: 2))
        #expect(progressUpdates.last == TokenUsageScanProgress(scannedFiles: 2, totalFiles: 2))
    }

    @Test
    func scansSelectedPeriodAndCachesResult() async throws {
        let now = makeDate(2026, 5, 20)
        let root = try makeSessionRoot(files: [
            "2026/05/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":100}}}
            """,
            "2026/04/21/session-b.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":200}}}
            """
        ])
        let provider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile(under: root),
            now: { now },
            calendar: utcCalendar()
        )

        let firstLoad = await provider.load(period: .last7Days) { _ in }
        guard case .loaded(let selectedPeriodData) = firstLoad else {
            Issue.record("Expected first token usage load to succeed")
            return
        }
        #expect(selectedPeriodData.buckets.count == CodexTokenUsagePeriod.last7Days.dayCount)

        var secondProgressUpdates: [TokenUsageScanProgress] = []

        let secondLoad = await provider.load(period: .last7Days) { secondProgressUpdates.append($0) }
        guard case .loaded(let cachedData) = secondLoad else {
            Issue.record("Expected cached token usage load to succeed")
            return
        }
        #expect(secondProgressUpdates.isEmpty)
        #expect(cachedData.buckets.map(\.usage.totalTokens).contains(100))
    }

    @Test
    func allTimePeakScopeScansHistoricalPeakOutsideSelectedPeriod() async throws {
        let now = makeDate(2026, 5, 20)
        let root = try makeSessionRoot(files: [
            "2026/05/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":100}}}
            """,
            "2026/01/10/session-b.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":9000}}}
            """
        ])
        let provider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile(under: root),
            now: { now },
            calendar: utcCalendar()
        )

        let load = await provider.load(period: .last7Days, peakScope: .allTime) { _ in }

        guard case .loaded(let data) = load else {
            Issue.record("Expected all-time peak load to succeed")
            return
        }
        #expect(data.buckets.count == CodexTokenUsagePeriod.last7Days.dayCount)
        #expect(data.buckets.map(\.usage.totalTokens).contains(9000) == false)
        #expect(data.allTimePeak?.usage.totalTokens == 9000)
    }

    @Test
    func allTimePeakScopeDoesNotReuseCurrentPeriodPeakAsHistoricalPeak() async throws {
        let now = makeDate(2026, 5, 20)
        let root = try makeSessionRoot(files: [
            "2026/05/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":100}}}
            """,
            "2026/01/10/session-b.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":9000}}}
            """
        ])
        let provider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile(under: root),
            now: { now },
            calendar: utcCalendar()
        )
        _ = await provider.load(period: .last7Days, peakScope: .currentPeriod) { _ in }
        var progressUpdates: [TokenUsageScanProgress] = []

        let load = await provider.load(period: .last7Days, peakScope: .allTime) { progressUpdates.append($0) }

        guard case .loaded(let data) = load else {
            Issue.record("Expected all-time peak load to succeed")
            return
        }
        #expect(progressUpdates.isEmpty == false)
        #expect(data.buckets.map(\.usage.totalTokens).contains(9000) == false)
        #expect(data.allTimePeak?.usage.totalTokens == 9000)
    }

    @Test
    func derivesShorterPeriodFromLongerCachedPeriod() async throws {
        let now = makeDate(2026, 5, 20)
        let root = try makeSessionRoot(files: [
            "2026/05/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":100}}}
            """,
            "2026/05/10/session-b.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":200}}}
            """
        ])
        let provider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile(under: root),
            now: { now },
            calendar: utcCalendar()
        )
        _ = await provider.load(period: .last30Days) { _ in }
        var progressUpdates: [TokenUsageScanProgress] = []

        let shortPeriodLoad = await provider.load(period: .last7Days) { progressUpdates.append($0) }

        guard case .loaded(let data) = shortPeriodLoad else {
            Issue.record("Expected shorter period to be derived from cached longer period")
            return
        }
        #expect(progressUpdates.isEmpty)
        #expect(data.buckets.count == CodexTokenUsagePeriod.last7Days.dayCount)
        #expect(data.buckets.map(\.usage.totalTokens).contains(100))
        #expect(data.buckets.map(\.usage.totalTokens).contains(200) == false)
    }

    @Test
    func reusesPersistedCacheWhenSessionFilesChanged() async throws {
        let now = makeDate(2026, 5, 20)
        let root = try makeSessionRoot(files: [
            "2026/05/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":100}}}
            """
        ])
        let cacheFile = cacheFile(under: root)
        let firstProvider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile,
            now: { now },
            calendar: utcCalendar()
        )
        _ = await firstProvider.load(period: .last7Days) { _ in }

        let newSession = try writeSessionFile(
            at: "2026/05/19/session-b.jsonl",
            under: root,
            contents: """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":9000}}}
            """
        )
        try touch(newSession, modificationDate: Date().addingTimeInterval(60))
        let secondProvider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile,
            now: { now },
            calendar: utcCalendar()
        )

        let cachedLoad = await secondProvider.load(period: .last7Days) { _ in }

        guard case .loaded(let cachedData) = cachedLoad else {
            Issue.record("Expected persisted token usage cache to load")
            return
        }
        #expect(cachedData.buckets.map(\.usage.totalTokens).contains(100))
        #expect(cachedData.buckets.map(\.usage.totalTokens).contains(9000) == false)
    }

    @Test
    func forceRefreshRescansSameDayInsteadOfReusingCurrentWindowCache() async throws {
        let now = makeDate(2026, 5, 20)
        let root = try makeSessionRoot(files: [
            "2026/05/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":100}}}
            """
        ])
        let cacheFile = cacheFile(under: root)
        let provider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile,
            now: { now },
            calendar: utcCalendar()
        )
        _ = await provider.load(period: .last7Days) { _ in }
        try writeSessionFile(
            at: "2026/05/20/session-b.jsonl",
            under: root,
            contents: """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":9000}}}
            """
        )
        var progressUpdates: [TokenUsageScanProgress] = []

        let refreshedLoad = await provider.load(
            period: .last7Days,
            forceRefresh: true
        ) { progressUpdates.append($0) }

        guard case .loaded(let refreshedData) = refreshedLoad else {
            Issue.record("Expected force-refreshed token usage load to succeed")
            return
        }
        #expect(progressUpdates.isEmpty == false)
        #expect(refreshedData.buckets.last?.day == now)
        #expect(refreshedData.buckets.last?.usage.totalTokens == 9100)
    }

    @Test
    func refreshesPersistedCacheWhenCachedBucketsDoNotCoverCurrentPeriod() async throws {
        let root = try makeSessionRoot(files: [
            "2026/05/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":100}}}
            """
        ])
        let cacheFile = cacheFile(under: root)
        let firstProvider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile,
            now: { makeDate(2026, 5, 20) },
            calendar: utcCalendar()
        )
        _ = await firstProvider.load(period: .last30Days) { _ in }

        try writeSessionFile(
            at: "2026/05/28/session-b.jsonl",
            under: root,
            contents: """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":500}}}
            """
        )
        let secondProvider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile,
            now: { makeDate(2026, 5, 28) },
            calendar: utcCalendar()
        )
        var progressUpdates: [TokenUsageScanProgress] = []

        let refreshedLoad = await secondProvider.load(period: .last30Days) { progressUpdates.append($0) }

        guard case .loaded(let refreshedData) = refreshedLoad else {
            Issue.record("Expected stale token usage cache to refresh")
            return
        }
        #expect(progressUpdates.isEmpty == false)
        #expect(refreshedData.buckets.count == CodexTokenUsagePeriod.last30Days.dayCount)
        #expect(refreshedData.buckets.last?.day == makeDate(2026, 5, 28))
        #expect(refreshedData.buckets.last?.usage.totalTokens == 500)
    }

    @Test
    func reusesWiderPersistedCacheWhenNarrowerPersistedCacheIsStale() async throws {
        let root = try makeSessionRoot(files: [
            "2026/05/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":100}}}
            """
        ])
        let cacheFile = cacheFile(under: root)
        let staleNarrowProvider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile,
            now: { makeDate(2026, 5, 20) },
            calendar: utcCalendar()
        )
        _ = await staleNarrowProvider.load(period: .last30Days) { _ in }

        try writeSessionFile(
            at: "2026/05/28/session-b.jsonl",
            under: root,
            contents: """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":500}}}
            """
        )
        let freshWideProvider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile,
            now: { makeDate(2026, 5, 28) },
            calendar: utcCalendar()
        )
        _ = await freshWideProvider.load(period: .last90Days) { _ in }

        let secondProvider = LocalCodexSessionTokenUsageMenuProvider(
            scanner: CodexSessionTokenUsageScanner(calendar: utcCalendar()),
            sessionsDirectory: root,
            cacheFile: cacheFile,
            now: { makeDate(2026, 5, 28) },
            calendar: utcCalendar()
        )
        var progressUpdates: [TokenUsageScanProgress] = []

        let cachedLoad = await secondProvider.load(period: .last30Days) { progressUpdates.append($0) }

        guard case .loaded(let cachedData) = cachedLoad else {
            Issue.record("Expected wider persisted token usage cache to load")
            return
        }
        #expect(progressUpdates.isEmpty)
        #expect(cachedData.buckets.count == CodexTokenUsagePeriod.last30Days.dayCount)
        #expect(cachedData.buckets.last?.day == makeDate(2026, 5, 28))
        #expect(cachedData.buckets.last?.usage.totalTokens == 500)
    }

    private func cacheFile(under root: URL) -> URL {
        root
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("token-usage-cache.json")
    }

    private func makeSessionRoot(files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        for (path, contents) in files {
            try writeSessionFile(at: path, under: root, contents: contents)
        }
        return root
    }

    @discardableResult
    private func writeSessionFile(at path: String, under root: URL, contents: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func touch(_ url: URL, modificationDate: Date) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: url.path
        )
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
