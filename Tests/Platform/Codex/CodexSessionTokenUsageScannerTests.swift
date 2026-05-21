import Foundation
import Testing

@testable import CodexPill

struct CodexSessionTokenUsageScannerTests {
    @Test
    func scanBucketsLastTokenUsageRowsBySessionDay() throws {
        let root = try makeSessionRoot(files: [
            "2026/04/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"turn_context"}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30,"reasoning_output_tokens":5,"total_tokens":155}}}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":40,"cached_input_tokens":10,"output_tokens":15,"reasoning_output_tokens":0,"total_tokens":65}}}}
            """,
            "2026/04/21/session-b.jsonl": """
            {"type":"event_msg","payload":{"type":"turn_context"}}
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"input_tokens":11,"cached_input_tokens":2,"output_tokens":13,"reasoning_output_tokens":17,"total_tokens":43}}}
            """
        ])

        let result = try CodexSessionTokenUsageScanner().scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            )
        )

        #expect(result.buckets.map(\.day) == [
            makeDate(2026, 4, 20),
            makeDate(2026, 4, 21)
        ])
        #expect(result.buckets[0].usage.totalTokens == 220)
        #expect(result.buckets[0].usage.inputTokens == 140)
        #expect(result.buckets[0].usage.cachedInputTokens == 30)
        #expect(result.buckets[0].usage.outputTokens == 45)
        #expect(result.buckets[0].usage.reasoningOutputTokens == 5)
        #expect(result.buckets[1].usage.totalTokens == 43)
        #expect(result.summary.tokenCountRowsRead == 3)
        #expect(result.summary.filesRead == 2)
    }

    @Test
    func scanDerivesPositiveDeltasFromCumulativeTotalUsageWhenLastUsageIsMissing() throws {
        let root = try makeSessionRoot(files: [
            "2026/04/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30,"reasoning_output_tokens":5,"total_tokens":155}}}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":140,"cached_input_tokens":30,"output_tokens":45,"reasoning_output_tokens":5,"total_tokens":220}}}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":130,"cached_input_tokens":30,"output_tokens":45,"reasoning_output_tokens":5,"total_tokens":210}}}}
            """
        ])

        let result = try CodexSessionTokenUsageScanner().scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            )
        )

        let bucket = try #require(result.buckets.first)
        #expect(bucket.usage.totalTokens == 220)
        #expect(bucket.usage.inputTokens == 140)
        #expect(bucket.usage.cachedInputTokens == 30)
        #expect(bucket.usage.outputTokens == 45)
        #expect(bucket.usage.reasoningOutputTokens == 5)
        #expect(result.summary.cumulativeRowsUsed == 2)
        #expect(result.summary.cumulativeRowsIgnored == 1)
    }

    @Test
    func scanIgnoresForkedCumulativeHistoryThatDropsBelowHighestObservedTotal() throws {
        let root = try makeSessionRoot(files: [
            "2026/04/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":200}}}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":150}}}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":180}}}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":230}}}}
            """
        ])

        let result = try CodexSessionTokenUsageScanner().scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            )
        )

        let bucket = try #require(result.buckets.first)
        #expect(bucket.usage.totalTokens == 230)
        #expect(result.summary.cumulativeRowsUsed == 3)
        #expect(result.summary.cumulativeRowsIgnored == 2)
    }

    @Test
    func scanKeepsTotalButDropsUnreliableComponentDeltas() throws {
        let root = try makeSessionRoot(files: [
            "2026/04/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":200}}}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":110,"cached_input_tokens":40,"output_tokens":70,"reasoning_output_tokens":0,"total_tokens":220}}}}
            """
        ])

        let result = try CodexSessionTokenUsageScanner().scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            )
        )

        let bucket = try #require(result.buckets.first)
        #expect(bucket.usage.totalTokens == 220)
        #expect(bucket.usage.inputTokens == 100)
        #expect(bucket.usage.cachedInputTokens == 50)
        #expect(bucket.usage.outputTokens == 50)
        #expect(bucket.usage.reasoningOutputTokens == 0)
        #expect(result.summary.cumulativeRowsUsed == 2)
    }

    @Test
    func scanAcceptsTokenCountRowsWithWhitespaceAroundTypeColon() throws {
        let root = try makeSessionRoot(files: [
            "2026/04/20/session-a.jsonl": """
            {"type" : "event_msg","payload":{"type" : "token_count","last_token_usage":{"total_tokens":321}}}
            """
        ])

        let result = try CodexSessionTokenUsageScanner().scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            )
        )

        #expect(result.buckets.map(\.usage.totalTokens) == [321])
        #expect(result.summary.tokenCountRowsRead == 1)
    }

    @Test
    func scanDoesNotLetLastUsageReadFollowingCumulativeUsageObject() throws {
        let root = try makeSessionRoot(files: [
            "2026/04/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{},"total_token_usage":{"total_tokens":321}}}
            """
        ])

        let result = try CodexSessionTokenUsageScanner().scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            )
        )

        #expect(result.buckets.map(\.usage.totalTokens) == [321])
        #expect(result.summary.cumulativeRowsUsed == 1)
    }

    @Test
    func scanSkipsRowsOutsideRangeAndMalformedPrivateContent() throws {
        let root = try makeSessionRoot(files: [
            "2026/03/31/old.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":999}}}
            """,
            "2026/04/20/current.jsonl": """
            {"type":"event_msg","payload":{"type":"message","redacted":true}}
            not json
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":10}}}
            """
        ])

        let result = try CodexSessionTokenUsageScanner().scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            )
        )

        #expect(result.buckets.map(\.usage.totalTokens) == [10])
        #expect(result.summary.filesRead == 1)
        #expect(result.summary.malformedRowsIgnored == 0)
        #expect(result.summary.nonUsageRowsIgnored == 2)
    }

    @Test
    func scanRecentPeriodReturnsZeroFilledDailyBucketsForSelectedWindow() throws {
        let root = try makeSessionRoot(files: [
            "2026/04/14/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":10}}}
            """,
            "2026/04/19/session-b.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":20}}}
            """,
            "2026/04/20/session-c.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":30}}}
            """
        ])

        let result = try CodexSessionTokenUsageScanner().scan(
            sessionsDirectory: root,
            period: .last7Days,
            now: makeDate(2026, 4, 20)
        )

        #expect(result.buckets.map(\.day) == [
            makeDate(2026, 4, 14),
            makeDate(2026, 4, 15),
            makeDate(2026, 4, 16),
            makeDate(2026, 4, 17),
            makeDate(2026, 4, 18),
            makeDate(2026, 4, 19),
            makeDate(2026, 4, 20)
        ])
        #expect(result.buckets.map(\.usage.totalTokens) == [10, 0, 0, 0, 0, 20, 30])
        #expect(result.summary.filesRead == 3)
    }

    @Test
    func scanReportsFileProgressWithoutExposingSessionPaths() throws {
        let root = try makeSessionRoot(files: [
            "2026/04/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":10}}}
            """,
            "2026/04/21/session-b.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":20}}}
            """
        ])
        var progressUpdates: [TokenUsageScanProgress] = []

        _ = try CodexSessionTokenUsageScanner().scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            ),
            progress: { progressUpdates.append($0) }
        )

        #expect(progressUpdates == [
            TokenUsageScanProgress(scannedFiles: 0, totalFiles: 2),
            TokenUsageScanProgress(scannedFiles: 1, totalFiles: 2),
            TokenUsageScanProgress(scannedFiles: 2, totalFiles: 2)
        ])
        #expect(progressUpdates.map(\.message).contains { $0.contains("session-a") } == false)
        #expect(progressUpdates.map(\.message).contains { $0.contains(root.path) } == false)
    }

    @Test
    func scanRecentPeriodsSupportSevenThirtyAndNinetyDayWindows() throws {
        let root = try makeSessionRoot(files: [:])
        let scanner = CodexSessionTokenUsageScanner()
        let now = makeDate(2026, 4, 20)

        for period in CodexTokenUsagePeriod.allCases {
            let result = try scanner.scan(
                sessionsDirectory: root,
                period: period,
                now: now
            )

            #expect(result.buckets.count == period.dayCount)
            #expect(result.buckets.first?.usage == .zero)
            #expect(result.buckets.last?.usage == .zero)
        }
    }

    @Test
    func scanSkipsOversizedSessionFilesToKeepTokenUsageMenuResponsive() throws {
        let oversizedMessage = String(repeating: "x", count: 256)
        let root = try makeSessionRoot(files: [
            "2026/04/20/oversized.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":999},"message":"\(oversizedMessage)"}}
            """,
            "2026/04/20/current.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":10}}}
            """
        ])
        let scanner = CodexSessionTokenUsageScanner(maximumScannableFileByteCount: 200)

        let result = try scanner.scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            )
        )

        #expect(result.buckets.map(\.usage.totalTokens) == [10])
        #expect(result.summary.filesRead == 1)
        #expect(result.summary.nonUsageRowsIgnored == 1)
    }

    @Test
    func scanReadsLargeFilesWhenFileSizeCapIsDisabled() throws {
        let oversizedMessage = String(repeating: "x", count: 256)
        let root = try makeSessionRoot(files: [
            "2026/04/20/large-session.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":999},"message":"\(oversizedMessage)"}}
            """,
            "2026/04/20/current.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":10}}}
            """
        ])
        let scanner = CodexSessionTokenUsageScanner(maximumScannableFileByteCount: 0)

        let result = try scanner.scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            )
        )

        #expect(result.buckets.map(\.usage.totalTokens) == [1009])
        #expect(result.summary.filesRead == 2)
    }

    @Test
    func scanDropsOversizedLinesWithoutKeepingThemInMemory() throws {
        let oversizedMessage = String(repeating: "x", count: 256)
        let root = try makeSessionRoot(files: [
            "2026/04/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"type":"message","text":"\(oversizedMessage)"}}
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":10}}}
            """
        ])
        let scanner = CodexSessionTokenUsageScanner(maximumLineByteCount: 128)

        let result = try scanner.scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            )
        )

        #expect(result.buckets.map(\.usage.totalTokens) == [10])
        #expect(result.summary.malformedRowsIgnored == 1)
    }

    @Test
    func scanAppliesConfiguredByteBudgetPerDay() throws {
        let root = try makeSessionRoot(files: [
            "2026/04/20/older-day.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":100}}}
            """,
            "2026/04/21/newer-day-a.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":10}}}
            """,
            "2026/04/21/newer-day-b.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":20}}}
            """
        ])
        let scanner = CodexSessionTokenUsageScanner(maximumDailyScanByteBudget: 128)

        let result = try scanner.scan(
            sessionsDirectory: root,
            dayRange: DateInterval(
                start: makeDate(2026, 4, 1),
                end: makeDate(2026, 5, 1)
            )
        )

        #expect(result.buckets.map(\.day) == [
            makeDate(2026, 4, 20),
            makeDate(2026, 4, 21)
        ])
        #expect(result.buckets.map(\.usage.totalTokens) == [100, 20])
        #expect(result.summary.filesRead == 2)
        #expect(result.summary.nonUsageRowsIgnored == 1)
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
