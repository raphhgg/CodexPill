import Foundation
import Testing

@testable import CodexPill

struct ClaudeUsageReaderTests {
    private let capturedAt = Date(timeIntervalSince1970: 1760000000)

    @Test
    func missingFileIsNotConnected() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = ClaudeUsageReader(fileURL: root.appendingPathComponent("claude-usage.json"))

        #expect(try reader.read(now: capturedAt) == .notConnected)
    }

    @Test
    func emptyRateLimitsAreAwaitingUsage() throws {
        let status = try read(#"{"schema":1,"captured_at":1760000000,"rate_limits":{}}"#, now: 1760000060)

        #expect(status == .awaitingUsage(capturedAt: capturedAt))
    }

    @Test
    func emptyRateLimitsStayAwaitingUsageWhenOld() throws {
        let status = try read(#"{"schema":1,"captured_at":1760000000,"rate_limits":{}}"#, now: 1760900000)

        #expect(status == .awaitingUsage(capturedAt: capturedAt))
    }

    @Test
    func recentFileWithBothWindowsIsCurrent() throws {
        let status = try read(
            #"{"schema":1,"captured_at":1760000000,"rate_limits":{"seven_day":{"used_percentage":18,"resets_at":1760500000},"five_hour":{"used_percentage":42.500000,"resets_at":1760010000}}}"#,
            now: 1760000600
        )

        #expect(status == .current(ClaudeUsageSnapshot(
            capturedAt: capturedAt,
            windows: [
                ClaudeUsageWindow(kind: .fiveHour, usedPercent: 42.5, resetsAt: Date(timeIntervalSince1970: 1760010000)),
                ClaudeUsageWindow(kind: .sevenDay, usedPercent: 18, resetsAt: Date(timeIntervalSince1970: 1760500000)),
            ]
        )))
    }

    @Test
    func fileOlderThanAnHourIsStale() throws {
        let status = try read(
            #"{"schema":1,"captured_at":1760000000,"rate_limits":{"seven_day":{"used_percentage":18,"resets_at":1760500000}}}"#,
            now: 1760003601
        )

        #expect(status == .stale(ClaudeUsageSnapshot(
            capturedAt: capturedAt,
            windows: [ClaudeUsageWindow(kind: .sevenDay, usedPercent: 18, resetsAt: Date(timeIntervalSince1970: 1760500000))]
        )))
    }

    @Test
    func windowPastItsResetReadsAsZeroWithNoResetTime() throws {
        let status = try read(
            #"{"schema":1,"captured_at":1760000000,"rate_limits":{"five_hour":{"used_percentage":91,"resets_at":1760001000},"seven_day":{"used_percentage":30,"resets_at":1760500000}}}"#,
            now: 1760001000
        )

        #expect(status == .current(ClaudeUsageSnapshot(
            capturedAt: capturedAt,
            windows: [
                ClaudeUsageWindow(kind: .fiveHour, usedPercent: 0, resetsAt: nil),
                ClaudeUsageWindow(kind: .sevenDay, usedPercent: 30, resetsAt: Date(timeIntervalSince1970: 1760500000)),
            ]
        )))
    }

    @Test
    func absentWindowIsOmittedAndUnknownWindowsAreIgnored() throws {
        let status = try read(
            #"{"schema":1,"captured_at":1760000000,"extra":true,"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":1760010000,"note":"x"},"spend_limit":{"used_usd":3}}}"#,
            now: 1760000001
        )

        #expect(status == .current(ClaudeUsageSnapshot(
            capturedAt: capturedAt,
            windows: [ClaudeUsageWindow(kind: .fiveHour, usedPercent: 5, resetsAt: Date(timeIntervalSince1970: 1760010000))]
        )))
    }

    @Test
    func outOfRangePercentagesAreClampedRatherThanRejected() throws {
        let record = try ClaudeUsageRecord.parse(Data(
            #"{"schema":1,"captured_at":1760000000,"rate_limits":{"five_hour":{"used_percentage":104.2,"resets_at":1760010000},"seven_day":{"used_percentage":-3,"resets_at":1760500000}}}"#.utf8
        ))

        #expect(record.windows[.fiveHour]?.usedPercent == 100)
        #expect(record.windows[.sevenDay]?.usedPercent == 0)
    }

    @Test(arguments: [
        ("not json", ClaudeUsageParseError.notJSON),
        ("", .notJSON),
        (#"[1,2]"#, .notAnObject),
        (#"{"captured_at":1760000000,"rate_limits":{}}"#, .missingSchema),
        (#"{"schema":"1","captured_at":1760000000,"rate_limits":{}}"#, .missingSchema),
        (#"{"schema":2,"captured_at":1760000000,"rate_limits":{}}"#, .unsupportedSchema(2)),
        (#"{"schema":1,"rate_limits":{}}"#, .invalidCapturedAt),
        (#"{"schema":1,"captured_at":"yesterday","rate_limits":{}}"#, .invalidCapturedAt),
        (#"{"schema":1,"captured_at":true,"rate_limits":{}}"#, .invalidCapturedAt),
        (#"{"schema":1,"captured_at":1760000000}"#, .invalidRateLimits),
        (#"{"schema":1,"captured_at":1760000000,"rate_limits":[]}"#, .invalidRateLimits),
        (#"{"schema":1,"captured_at":1760000000,"rate_limits":{"five_hour":{"used_percentage":"42","resets_at":1760010000}}}"#, .invalidWindow(.fiveHour)),
        (#"{"schema":1,"captured_at":1760000000,"rate_limits":{"seven_day":{"used_percentage":42}}}"#, .invalidWindow(.sevenDay)),
        (#"{"schema":1,"captured_at":1760000000,"rate_limits":{"seven_day":7}}"#, .invalidWindow(.sevenDay)),
    ])
    func malformedFilesThrowSpecificErrors(contents: String, expected: ClaudeUsageParseError) throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("claude-usage.json")
        try Data(contents.utf8).write(to: file)

        #expect(throws: ClaudeUsageReadError.malformed(expected)) {
            try ClaudeUsageReader(fileURL: file).read(now: capturedAt)
        }
    }

    @Test
    func directoryAtFilePathIsUnreadable() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("claude-usage.json", isDirectory: true)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)

        #expect(throws: ClaudeUsageReadError.unreadable) {
            try ClaudeUsageReader(fileURL: file).read(now: capturedAt)
        }
    }

    private func read(_ contents: String, now: TimeInterval) throws -> ClaudeUsageStatus {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("claude-usage.json")
        try Data(contents.utf8).write(to: file)
        return try ClaudeUsageReader(fileURL: file).read(now: Date(timeIntervalSince1970: now))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeUsageReaderTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
