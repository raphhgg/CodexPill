import Foundation
import Testing

@testable import Refill

/// Each process is a `comm=` line and an `args=` line, as `ps -axww` prints them.
struct ClaudeCodeProcessDetectorTests {
    private let detector = SystemClaudeCodeProcessDetector(homeDirectory: URL(fileURLWithPath: "/Users/someone"))

    private static let desktopApp = [
        (
            "/Applications/Claude.app/Contents/MacOS/Claude",
            "/Applications/Claude.app/Contents/MacOS/Claude"
        ),
        (
            "/Applications/Claude.app/Contents/Helpers/disclaimer",
            "/Applications/Claude.app/Contents/Helpers/disclaimer --pgroup -- /Users/someone/Library/Application Support/Claude/claude-code/2.1.295/9d6405864fdc/claude.app/Contents/MacOS/claude --output-format stream-json --verbose"
        ),
        (
            "/Users/someone/Library/Application Support/Claude/claude-code/2.1.295/9d6405864fdc/claude.app/Contents/MacOS/claude",
            "/Users/someone/Library/Application Support/Claude/claude-code/2.1.295/9d6405864fdc/claude.app/Contents/MacOS/claude --output-format stream-json --verbose --input-format stream-json"
        ),
    ]

    private func runs(_ processes: [(String, String)]) -> Bool {
        detector.runsTerminalClaudeCode(executables: processes.map(\.0), commandLines: processes.map(\.1))
    }

    @Test
    func theDesktopAppsOwnClaudeCodeDoesNotCount() {
        #expect(runs(Self.desktopApp) == false)
    }

    @Test
    func terminalClaudeCodeCountsInEveryWayItIsInstalled() {
        #expect(runs([("/Users/someone/.local/share/claude/versions/2.1.294", "claude --resume")]))
        #expect(runs([("/opt/homebrew/bin/claude", "/opt/homebrew/bin/claude")]))
        #expect(runs([("node", "claude")]))
        #expect(runs([("/usr/local/bin/node", "node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js")]))
    }

    @Test
    func terminalClaudeCodeCountsBesideTheDesktopApp() {
        #expect(runs(Self.desktopApp + [("/Users/someone/.local/share/claude/versions/2.1.294", "claude")]))
    }

    @Test
    func otherProcessesDoNotCount() {
        #expect(runs([("/usr/bin/vim", "vim claude.md"), ("/usr/bin/claude-helper", "claude-helper")]) == false)
    }
}
