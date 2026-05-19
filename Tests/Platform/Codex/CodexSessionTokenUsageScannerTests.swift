import Foundation
import Testing

@testable import CodexPill

struct CodexSessionTokenUsageScannerTests {
    @Test
    func scanBucketsLastTokenUsageRowsBySessionDay() throws {
        let root = try makeSessionRoot(files: [
            "2026/04/20/session-a.jsonl": """
            {"type":"event_msg","payload":{"model":"gpt-5.2"}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30,"reasoning_output_tokens":5,"total_tokens":155}}}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":40,"cached_input_tokens":10,"output_tokens":15,"reasoning_output_tokens":0,"total_tokens":65}}}}
            """,
            "2026/04/21/session-b.jsonl": """
            {"type":"event_msg","payload":{"type":"turn_context","model":"gpt-5.3-codex"}}
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
        #expect(result.buckets[0].models == ["gpt-5.2"])
        #expect(result.buckets[1].usage.totalTokens == 43)
        #expect(result.buckets[1].models == ["gpt-5.3-codex"])
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
    func scanSkipsRowsOutsideRangeAndMalformedPrivateContent() throws {
        let root = try makeSessionRoot(files: [
            "2026/03/31/old.jsonl": """
            {"type":"event_msg","payload":{"type":"token_count","last_token_usage":{"total_tokens":999}}}
            """,
            "2026/04/20/current.jsonl": """
            {"type":"event_msg","payload":{"type":"message","content":"private prompt text must be ignored"}}
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
        #expect(result.summary.malformedRowsIgnored == 1)
        #expect(result.summary.nonUsageRowsIgnored == 1)
    }

    private func makeSessionRoot(files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
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
