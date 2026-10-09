import Foundation
import Testing

@testable import CodexPill

struct ClaudeCodeUsageTests {
    private let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func connectedRelayOutputBecomesSessionAndWeeklyUsage() async throws {
        let fixture = try ClaudeCodeFixture()
        defer { fixture.remove() }
        try fixture.writeSettings(#"{"statusLine": {"type": "command", "command": "'\#(fixture.relayPath)'"}}"#)
        try fixture.writeRelayOutput(
            #"{"schema":1,"captured_at":1800000000,"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1800003600},"seven_day":{"used_percentage":18,"resets_at":1800300000}}}"#
        )

        let reading = await fixture.usage.readUsage(now: capturedAt.addingTimeInterval(600))

        #expect(reading == .snapshot(UsageSnapshot(
            provider: .claude,
            planName: nil,
            windows: [
                UsageWindow(kind: .session, usedPercent: 43, resetsAt: Date(timeIntervalSince1970: 1_800_003_600), durationMinutes: 300),
                UsageWindow(kind: .weekly, usedPercent: 18, resetsAt: Date(timeIntervalSince1970: 1_800_300_000), durationMinutes: 10_080)
            ],
            fetchedAt: capturedAt
        )))
    }

    @Test
    func windowPastItsResetReadsAsZeroWithNoResetTime() async throws {
        let fixture = try ClaudeCodeFixture()
        defer { fixture.remove() }
        try fixture.writeSettings(#"{"statusLine": {"type": "command", "command": "'\#(fixture.relayPath)'"}}"#)
        try fixture.writeRelayOutput(
            #"{"schema":1,"captured_at":1800000000,"rate_limits":{"five_hour":{"used_percentage":97,"resets_at":1800003600}}}"#
        )

        let reading = await fixture.usage.readUsage(now: capturedAt.addingTimeInterval(7_200))

        #expect(reading == .snapshot(UsageSnapshot(
            provider: .claude,
            planName: nil,
            windows: [UsageWindow(kind: .session, usedPercent: 0, resetsAt: nil, durationMinutes: 300)],
            fetchedAt: capturedAt
        )))
    }

    @Test
    func readingFollowsTheStatusLineThenTheRelayFile() async throws {
        let fixture = try ClaudeCodeFixture()
        defer { fixture.remove() }
        let relayOutput = #"{"schema":1,"captured_at":1800000000,"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":1800003600}}}"#
        try fixture.writeRelayOutput(relayOutput)
        try fixture.writeSettings(#"{"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}}"#)

        #expect(await fixture.usage.readUsage(now: capturedAt) == .notConnected)

        try fixture.writeSettings(#"{"statusLine": {"type": "command", "command": "'\#(fixture.relayPath)' '~/.claude/statusline.sh'"}}"#)
        try FileManager.default.removeItem(at: fixture.usage.reader.fileURL)

        #expect(await fixture.usage.readUsage(now: capturedAt) == .awaitingUsage)

        try fixture.writeRelayOutput(#"{"schema":1,"captured_at":1800000000,"rate_limits":{}}"#)

        #expect(await fixture.usage.readUsage(now: capturedAt) == .awaitingUsage)

        try fixture.writeRelayOutput(#"{"schema":2,"captured_at":1800000000,"rate_limits":{}}"#)

        #expect(await fixture.usage.readUsage(now: capturedAt) == .unavailable(.readFailed))
    }

    @Test
    func connectWrapsTheExistingStatusLineAndDisconnectRestoresIt() async throws {
        let fixture = try ClaudeCodeFixture()
        defer { fixture.remove() }
        try fixture.writeSettings("""
        {"env": {"ANTHROPIC_LOG": "error"}, "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0}}
        """)
        let original = try fixture.settingsObject()

        let connect = try #require(try fixture.usage.connectionChange())

        #expect(connect == ClaudeStatusLineChange(
            settingsPath: fixture.settingsURL.path,
            before: """
            {
              "command" : "~/.claude/statusline.sh",
              "padding" : 0,
              "type" : "command"
            }
            """,
            after: """
            {
              "command" : "'\(fixture.relayPath)' '~/.claude/statusline.sh'",
              "padding" : 0,
              "type" : "command"
            }
            """
        ))

        try fixture.usage.connect(confirming: connect)
        try fixture.writeRelayOutput(#"{"schema":1,"captured_at":1800000000,"rate_limits":{}}"#)

        #expect(try fixture.usage.connectionChange() == nil)
        #expect(await fixture.usage.readUsage(now: capturedAt) == .awaitingUsage)

        let disconnect = try #require(try fixture.usage.disconnectionChange())

        #expect(disconnect.before == connect.after)
        #expect(disconnect.after == connect.before)

        try fixture.usage.disconnect(confirming: disconnect)

        #expect(try fixture.settingsObject() == original)
        #expect(!FileManager.default.fileExists(atPath: fixture.relayPath))
        #expect(!FileManager.default.fileExists(atPath: fixture.usage.reader.fileURL.path))
        #expect(await fixture.usage.readUsage(now: capturedAt) == .notConnected)
        #expect(try fixture.usage.disconnectionChange() == nil)
    }

    @Test
    func connectWithoutAStatusLineAddsOneAndDisconnectRemovesTheKey() throws {
        let fixture = try ClaudeCodeFixture()
        defer { fixture.remove() }
        try fixture.writeSettings(#"{"model": "opus"}"#)

        let connect = try #require(try fixture.usage.connectionChange())

        #expect(connect.before == nil)
        #expect(connect.after == """
        {
          "command" : "'\(fixture.relayPath)'",
          "type" : "command"
        }
        """)

        try fixture.usage.connect(confirming: connect)
        try fixture.usage.disconnect(confirming: try #require(try fixture.usage.disconnectionChange()))

        #expect(try fixture.settingsObject() == ["model": "opus"])
    }

    @Test
    func connectRefusesWhenSettingsChangedAfterTheConsentPreview() throws {
        let fixture = try ClaudeCodeFixture()
        defer { fixture.remove() }
        try fixture.writeSettings(#"{"statusLine": {"type": "command", "command": "old.sh"}}"#)
        let connect = try #require(try fixture.usage.connectionChange())
        let edited = #"{"statusLine": {"type": "command", "command": "new.sh"}}"#
        try fixture.writeSettings(edited)

        #expect(throws: ClaudeStatusLineInstallError.settingsChanged) {
            try fixture.usage.connect(confirming: connect)
        }
        #expect(try String(contentsOf: fixture.settingsURL, encoding: .utf8) == edited)
        #expect(!FileManager.default.fileExists(atPath: fixture.relayPath))
    }
}
