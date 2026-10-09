import Foundation
import Testing

@testable import CodexPill

struct ClaudeStatusLineInstallPlannerTests {
    private let relayPath = "/Users/fixture/Library/Application Support/CodexPill/bin/codexpill-claude-usage-relay.sh"

    @Test
    func installWithoutSettingsFileCreatesStatusLine() throws {
        let plan = try ClaudeStatusLineInstallPlanner.planInstall(settings: nil, relayPath: relayPath)

        let (settings, previousCommand) = try #require(writtenSettings(plan))
        #expect(previousCommand == nil)
        #expect(String(decoding: settings, as: UTF8.self) == """
        {
          "statusLine" : {
            "command" : "'/Users/fixture/Library/Application Support/CodexPill/bin/codexpill-claude-usage-relay.sh'",
            "type" : "command"
          }
        }

        """)
    }

    @Test
    func installWrapsPreviousCommandAndPreservesOtherKeys() throws {
        let original = """
        {
          "model": "opus",
          "permissions": {"allow": ["Bash(git status)"]},
          "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 2}
        }
        """

        let plan = try ClaudeStatusLineInstallPlanner.planInstall(settings: Data(original.utf8), relayPath: relayPath)

        let (settings, previousCommand) = try #require(writtenSettings(plan))
        #expect(previousCommand == "~/.claude/statusline.sh")
        #expect(try object(settings) == object(Data("""
        {
          "model": "opus",
          "permissions": {"allow": ["Bash(git status)"]},
          "statusLine": {
            "type": "command",
            "command": "'/Users/fixture/Library/Application Support/CodexPill/bin/codexpill-claude-usage-relay.sh' '~/.claude/statusline.sh'",
            "padding": 2
          }
        }
        """.utf8)))
    }

    @Test
    func installQuotesPreviousCommandContainingQuotes() throws {
        let original = #"{"statusLine":{"type":"command","command":"echo \"it's $(pwd)\""}}"#

        let plan = try ClaudeStatusLineInstallPlanner.planInstall(settings: Data(original.utf8), relayPath: "/r/codexpill-claude-usage-relay.sh")

        let (settings, previousCommand) = try #require(writtenSettings(plan))
        #expect(previousCommand == #"echo "it's $(pwd)""#)
        #expect(try statusLineCommand(settings) == #"'/r/codexpill-claude-usage-relay.sh' 'echo "it'\''s $(pwd)"'"#)
    }

    @Test
    func installingTwiceIsUnchanged() throws {
        let original = #"{"statusLine":{"type":"command","command":"~/.claude/statusline.sh"}}"#
        let first = try ClaudeStatusLineInstallPlanner.planInstall(settings: Data(original.utf8), relayPath: relayPath)
        let (installed, _) = try #require(writtenSettings(first))

        let second = try ClaudeStatusLineInstallPlanner.planInstall(settings: installed, relayPath: relayPath)

        #expect(second == .unchanged(.alreadyInstalled))
    }

    @Test
    func reinstallFromNewRelayPathRepointsAndKeepsPreviousCommand() throws {
        let installed = #"{"statusLine":{"type":"command","command":"'/Old Place/codexpill-claude-usage-relay.sh' 'echo it'\\''s'"}}"#

        let plan = try ClaudeStatusLineInstallPlanner.planInstall(settings: Data(installed.utf8), relayPath: "/New/codexpill-claude-usage-relay.sh")

        let (settings, previousCommand) = try #require(writtenSettings(plan))
        #expect(previousCommand == "echo it's")
        #expect(try statusLineCommand(settings) == #"'/New/codexpill-claude-usage-relay.sh' 'echo it'\''s'"#)
    }

    @Test
    func uninstallRestoresOriginalSettings() throws {
        let original = """
        {"env":{"FOO":"bar"},"statusLine":{"type":"command","command":"bunx ccusage statusline","padding":0,"refreshInterval":5}}
        """
        let install = try ClaudeStatusLineInstallPlanner.planInstall(settings: Data(original.utf8), relayPath: relayPath)
        let (installed, _) = try #require(writtenSettings(install))

        let uninstall = try ClaudeStatusLineInstallPlanner.planUninstall(settings: installed)

        let (restored, previousCommand) = try #require(writtenSettings(uninstall))
        #expect(previousCommand == "bunx ccusage statusline")
        #expect(try object(restored) == object(Data(original.utf8)))
    }

    @Test
    func uninstallWithoutPreviousCommandDropsStatusLine() throws {
        let original = #"{"model":"sonnet"}"#
        let install = try ClaudeStatusLineInstallPlanner.planInstall(settings: Data(original.utf8), relayPath: relayPath)
        let (installed, _) = try #require(writtenSettings(install))

        let uninstall = try ClaudeStatusLineInstallPlanner.planUninstall(settings: installed)

        let (restored, previousCommand) = try #require(writtenSettings(uninstall))
        #expect(previousCommand == nil)
        #expect(try object(restored) == object(Data(original.utf8)))
    }

    @Test
    func uninstallWithoutPreviousCommandKeepsOtherStatusLineKeys() throws {
        let installed = #"{"statusLine":{"type":"command","command":"'/r/codexpill-claude-usage-relay.sh'","padding":1}}"#

        let plan = try ClaudeStatusLineInstallPlanner.planUninstall(settings: Data(installed.utf8))

        let (restored, _) = try #require(writtenSettings(plan))
        #expect(try object(restored) == object(Data(#"{"statusLine":{"padding":1}}"#.utf8)))
    }

    @Test(arguments: [
        #"{"statusLine":{"type":"command","command":"~/.claude/my-status.sh"}}"#,
        #"{"statusLine":{"type":"command","command":"'/r/codexpill-claude-usage-relay.sh' 'a' 'b'"}}"#,
        #"{"statusLine":{"type":"command","command":"/r/codexpill-claude-usage-relay.sh"}}"#,
        #"{"statusLine":{"padding":2}}"#,
        #"{"model":"opus"}"#,
    ])
    func uninstallLeavesCommandsThatAreNotOursUnchanged(settings: String) throws {
        #expect(try ClaudeStatusLineInstallPlanner.planUninstall(settings: Data(settings.utf8)) == .unchanged(.notInstalled))
    }

    @Test
    func uninstallWithoutSettingsFileIsUnchanged() throws {
        #expect(try ClaudeStatusLineInstallPlanner.planUninstall(settings: nil) == .unchanged(.notInstalled))
    }

    @Test(arguments: [
        ("{not json", ClaudeStatusLinePlanError.settingsNotJSON),
        ("", .settingsNotJSON),
        ("[]", .settingsNotAnObject),
        (#""statusLine""#, .settingsNotAnObject),
        (#"{"statusLine":"~/.claude/statusline.sh"}"#, .statusLineNotAnObject),
        (#"{"statusLine":{"type":"command","command":["sh"]}}"#, .commandNotAString),
    ])
    func invalidSettingsAreRefused(settings: String, expected: ClaudeStatusLinePlanError) {
        #expect(throws: expected) {
            try ClaudeStatusLineInstallPlanner.planInstall(settings: Data(settings.utf8), relayPath: relayPath)
        }
        #expect(throws: expected) {
            try ClaudeStatusLineInstallPlanner.planUninstall(settings: Data(settings.utf8))
        }
    }

    private func writtenSettings(_ plan: ClaudeStatusLinePlan) -> (Data, String?)? {
        guard case let .write(settings, previousCommand) = plan else { return nil }
        return (settings, previousCommand)
    }

    private func statusLineCommand(_ settings: Data) throws -> String? {
        let root = try JSONSerialization.jsonObject(with: settings) as? [String: Any]
        return (root?["statusLine"] as? [String: Any])?["command"] as? String
    }

    private func object(_ data: Data) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}
