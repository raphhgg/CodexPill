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
            sessionsDirectory: root,
            cacheFile: cacheFile(under: root),
            now: { now }
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
            sessionsDirectory: root,
            cacheFile: cacheFile(under: root),
            now: { now }
        )

        let firstLoad = await provider.load(period: .last7Days) { _ in }
        guard case .loaded(let selectedPeriodBuckets) = firstLoad else {
            Issue.record("Expected first token usage load to succeed")
            return
        }
        #expect(selectedPeriodBuckets.count == CodexTokenUsagePeriod.last7Days.dayCount)

        var secondProgressUpdates: [TokenUsageScanProgress] = []

        let secondLoad = await provider.load(period: .last7Days) { secondProgressUpdates.append($0) }
        guard case .loaded(let cachedBuckets) = secondLoad else {
            Issue.record("Expected cached token usage load to succeed")
            return
        }
        #expect(secondProgressUpdates.isEmpty)
        #expect(cachedBuckets.map(\.usage.totalTokens).contains(100))
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
            sessionsDirectory: root,
            cacheFile: cacheFile(under: root),
            now: { now }
        )
        _ = await provider.load(period: .last30Days) { _ in }
        var progressUpdates: [TokenUsageScanProgress] = []

        let shortPeriodLoad = await provider.load(period: .last7Days) { progressUpdates.append($0) }

        guard case .loaded(let buckets) = shortPeriodLoad else {
            Issue.record("Expected shorter period to be derived from cached longer period")
            return
        }
        #expect(progressUpdates.isEmpty)
        #expect(buckets.count == CodexTokenUsagePeriod.last7Days.dayCount)
        #expect(buckets.map(\.usage.totalTokens).contains(100))
        #expect(buckets.map(\.usage.totalTokens).contains(200) == false)
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
            sessionsDirectory: root,
            cacheFile: cacheFile,
            now: { now }
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
            sessionsDirectory: root,
            cacheFile: cacheFile,
            now: { now }
        )

        let cachedLoad = await secondProvider.load(period: .last7Days) { _ in }

        guard case .loaded(let cachedBuckets) = cachedLoad else {
            Issue.record("Expected persisted token usage cache to load")
            return
        }
        #expect(cachedBuckets.map(\.usage.totalTokens).contains(100))
        #expect(cachedBuckets.map(\.usage.totalTokens).contains(9000) == false)
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
}
