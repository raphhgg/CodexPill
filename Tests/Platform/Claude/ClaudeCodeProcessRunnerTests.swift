import Foundation
import Testing

@testable import CodexPill

/// The real runner, with a shell script standing in for `claude`.
struct ClaudeCodeProcessRunnerTests {
    @Test
    func claudeRunsWithItsConfigFolderExactlyAsGivenAndNoneOfTheUsersShellVariables() async throws {
        let fixture = try ScriptFixture(script: """
        #!/bin/sh
        printf '%s\\n' "$*" > "$PWD/arguments"
        printf '%s\\n' "$CLAUDE_CONFIG_DIR" > "$PWD/config-dir"
        env | cut -d= -f1 | sort > "$PWD/variables"
        exit 3
        """)
        defer { fixture.remove() }

        let status = try await fixture.runner.run(
            ["doctor"],
            configDirectory: "/tmp/Application Support/Claude Config",
            workingDirectory: fixture.root,
            timeout: .seconds(30)
        )

        #expect(status == 3)
        #expect(try fixture.output("arguments") == "doctor\n")
        #expect(try fixture.output("config-dir") == "/tmp/Application Support/Claude Config\n")
        #expect(try fixture.output("variables").split(separator: "\n").filter { !["PWD", "SHLVL", "_"].contains($0) }
            == ["CLAUDE_CONFIG_DIR", "HOME", "LOGNAME", "PATH", "TMPDIR", "USER"])
    }

    @Test
    func cancellingStopsAClaudeThatIsStillWaiting() async throws {
        let fixture = try ScriptFixture(script: """
        #!/bin/sh
        touch "$PWD/started"
        read line
        touch "$PWD/finished"
        """)
        defer { fixture.remove() }

        let runner = fixture.runner
        let root = fixture.root
        let run = Task {
            try await runner.run(["doctor"], configDirectory: nil, workingDirectory: root, timeout: .seconds(30))
        }
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("started").path) {
            await Task.yield()
        }
        run.cancel()

        await #expect(throws: ClaudeCodeCommandError.cancelled) { try await run.value }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("finished").path) == false)
    }

    @Test
    func aMissingClaudeIsReportedWithoutRunningAnything() async throws {
        let runner = SystemClaudeCodeProcessRunner(searchDirectories: [URL(fileURLWithPath: "/nonexistent-codexpill-test")])

        #expect(runner.executable == nil)
        await #expect(throws: ClaudeCodeCommandError.notInstalled) {
            try await runner.run(["doctor"], configDirectory: nil, workingDirectory: URL(fileURLWithPath: "/"), timeout: .seconds(1))
        }
    }
}

private struct ScriptFixture {
    let root: URL
    let runner: SystemClaudeCodeProcessRunner

    init(script: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeCodeProcessRunnerTests-\(UUID().uuidString)", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let claude = bin.appendingPathComponent("claude")
        try Data(script.utf8).write(to: claude)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        runner = SystemClaudeCodeProcessRunner(searchDirectories: [bin])
    }

    func output(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
