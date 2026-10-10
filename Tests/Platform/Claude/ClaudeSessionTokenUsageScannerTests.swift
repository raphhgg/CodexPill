import Foundation
import Testing

@testable import CodexPill

struct ClaudeSessionTokenUsageScannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var interval: DateInterval {
        DateInterval(start: day(2026, 10, 1), end: day(2026, 10, 11))
    }

    @Test
    func countsEachResponseOnceWithCacheTokensByDayAndModel() throws {
        let root = try makeRoot([
            "-Users-me-app/session-a.jsonl": [
                #"{"type":"user","timestamp":"2026-10-09T10:00:00.000Z","message":{"role":"user","content":"secret prompt"}}"#,
                assistant(id: "m1", request: "r1", time: "2026-10-09T10:00:01.000Z", model: "claude-opus", input: 10, output: 5, cacheWrite: 100, cacheRead: 1000),
                // The same response written again for its next content block.
                assistant(id: "m1", request: "r1", time: "2026-10-09T10:00:02.000Z", model: "claude-opus", input: 10, output: 5, cacheWrite: 100, cacheRead: 1000),
                assistant(id: "m2", request: "r2", time: "2026-10-10T08:00:00.000Z", model: "claude-sonnet", input: 1, output: 2, cacheWrite: 0, cacheRead: 7),
                assistant(id: "m3", request: "r3", time: "2026-10-10T08:01:00.000Z", model: "<synthetic>", input: 0, output: 0, cacheWrite: 0, cacheRead: 0),
                "not json"
            ],
            "-Users-me-app/session-a/subagents/agent-1.jsonl": [
                assistant(id: "m4", request: "r4", time: "2026-10-10T09:00:00.000Z", model: "claude-haiku", input: 3, output: 3, cacheWrite: 0, cacheRead: 0)
            ]
        ])

        let result = try ClaudeSessionTokenUsageScanner(calendar: calendar).scan(
            projectsDirectory: root,
            interval: interval,
            cachedFileContributions: [],
            now: day(2026, 10, 10)
        )

        #expect(result.days.count == 10)
        #expect(result.days.first { $0.day == day(2026, 10, 9) }?.tokensByModel == ["claude-opus": 1115])
        #expect(result.days.first { $0.day == day(2026, 10, 10) }?.tokensByModel == ["claude-sonnet": 10, "claude-haiku": 6])
        #expect(result.fileContributions.map(\.cacheKey) == [
            "/-Users-me-app/session-a.jsonl",
            "/-Users-me-app/session-a/subagents/agent-1.jsonl"
        ])
    }

    @Test
    func countsAResponseCopiedIntoAResumedSessionOnce() throws {
        let row = assistant(id: "m1", request: "r1", time: "2026-10-09T10:00:00.000Z", model: "claude-opus", input: 1, output: 1, cacheWrite: 0, cacheRead: 8)
        let root = try makeRoot([
            "p/original.jsonl": [row],
            "p/resumed.jsonl": [row]
        ])

        let result = try ClaudeSessionTokenUsageScanner(calendar: calendar).scan(
            projectsDirectory: root,
            interval: interval,
            cachedFileContributions: [],
            now: day(2026, 10, 10)
        )

        #expect(result.days.reduce(0) { $0 + $1.totalTokens } == 10)
    }

    @Test
    func keepsHistoryForTranscriptsClaudeCodeDeleted() throws {
        let root = try makeRoot([
            "p/kept.jsonl": [
                assistant(id: "m1", request: "r1", time: "2026-10-09T10:00:00.000Z", model: "claude-opus", input: 4, output: 0, cacheWrite: 0, cacheRead: 0)
            ]
        ])
        let deleted = ClaudeTokenUsageFileContribution(
            cacheKey: "/p/deleted.jsonl",
            fileSize: 10,
            modificationDate: nil,
            rows: [ClaudeTokenUsageRow(key: "m0:r0", day: day(2026, 10, 2), model: "claude-opus", tokens: 50)]
        )

        let result = try ClaudeSessionTokenUsageScanner(calendar: calendar).scan(
            projectsDirectory: root,
            interval: interval,
            cachedFileContributions: [deleted],
            now: day(2026, 10, 10)
        )

        #expect(result.days.first { $0.day == day(2026, 10, 2) }?.totalTokens == 50)
        #expect(result.days.first { $0.day == day(2026, 10, 9) }?.totalTokens == 4)
        #expect(result.fileContributions.contains(deleted))
    }

    @Test
    func reusesCachedRowsForUnchangedFiles() throws {
        let root = try makeRoot([
            "p/a.jsonl": [
                assistant(id: "m1", request: "r1", time: "2026-10-09T10:00:00.000Z", model: "claude-opus", input: 4, output: 0, cacheWrite: 0, cacheRead: 0)
            ]
        ])
        let scanner = ClaudeSessionTokenUsageScanner(calendar: calendar)
        let first = try scanner.scan(projectsDirectory: root, interval: interval, cachedFileContributions: [], now: day(2026, 10, 10))
        var cached = first.fileContributions
        // A changed row count proves the cached copy is used instead of the file.
        cached[0].rows[0].tokens = 99

        let second = try scanner.scan(projectsDirectory: root, interval: interval, cachedFileContributions: cached, now: day(2026, 10, 10))

        #expect(second.days.reduce(0) { $0 + $1.totalTokens } == 99)
    }

    @Test
    func persistedRowsCarryNoPromptContent() throws {
        let root = try makeRoot([
            "p/a.jsonl": [
                #"{"type":"assistant","timestamp":"2026-10-09T10:00:00.000Z","requestId":"r1","message":{"id":"m1","model":"claude-opus","content":[{"type":"text","text":"PRIVATE-RESPONSE"}],"usage":{"input_tokens":1,"output_tokens":1}}}"#
            ]
        ])

        let result = try ClaudeSessionTokenUsageScanner(calendar: calendar).scan(
            projectsDirectory: root,
            interval: interval,
            cachedFileContributions: [],
            now: day(2026, 10, 10)
        )

        let encoded = try String(decoding: JSONEncoder().encode(result.fileContributions), as: UTF8.self)
        #expect(!encoded.contains("PRIVATE-RESPONSE"))
        #expect(result.days.reduce(0) { $0 + $1.totalTokens } == 2)
    }

    private func assistant(
        id: String,
        request: String,
        time: String,
        model: String,
        input: Int,
        output: Int,
        cacheWrite: Int,
        cacheRead: Int
    ) -> String {
        #"{"type":"assistant","timestamp":"\#(time)","requestId":"\#(request)","message":{"id":"\#(id)","model":"\#(model)","role":"assistant","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(cacheWrite),"cache_read_input_tokens":\#(cacheRead)}}}"#
    }

    private func makeRoot(_ files: [String: [String]]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for (path, lines) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(lines.joined(separator: "\n").utf8).write(to: url)
        }
        return root
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
