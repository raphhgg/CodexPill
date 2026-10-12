import Foundation

/// Tells whether Claude Code is running. A running Claude Code renews its own token, so CodexPill leaves renewal to it.
protocol ClaudeCodeProcessDetecting: Sendable {
    func isClaudeCodeRunning() -> Bool
}

/// Reads the process table with `ps` and counts only terminal Claude Code. The Claude desktop app runs its own copy
/// under `~/Library/Application Support/Claude/claude-code/`, started by its `disclaimer` helper; that copy keeps its
/// own sign-in, so it is ignored.
struct SystemClaudeCodeProcessDetector: ClaudeCodeProcessDetecting {
    var homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    /// When the process table can't be read, it reports Claude Code as running, so no renewal runs beside it.
    func isClaudeCodeRunning() -> Bool {
        guard let executables = Self.processTable(column: "comm="), let commandLines = Self.processTable(column: "args=") else {
            return true
        }
        return runsTerminalClaudeCode(executables: executables, commandLines: commandLines)
    }

    /// Takes the `comm=` and `args=` columns of `ps`.
    func runsTerminalClaudeCode(executables: [String], commandLines: [String]) -> Bool {
        executables.contains { !belongsToDesktopApp($0) && Self.isClaudeCodeExecutable($0) }
            || commandLines.contains { !belongsToDesktopApp($0) && Self.isClaudeCodeCommandLine($0) }
    }

    private func belongsToDesktopApp(_ line: String) -> Bool {
        line.hasPrefix(homeDirectory.appendingPathComponent("Library/Application Support/Claude/claude-code").path + "/")
            || line.hasPrefix("/Applications/Claude.app/")
    }

    /// The native installer runs `~/.local/share/claude/versions/<version>`; other installs run a file named `claude`.
    private static func isClaudeCodeExecutable(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent == "claude" || url.deletingLastPathComponent().path.hasSuffix("/claude/versions")
    }

    /// An npm install runs `node …/@anthropic-ai/claude-code/cli.js` and then sets its process title to `claude`.
    private static func isClaudeCodeCommandLine(_ commandLine: String) -> Bool {
        let program = commandLine.split(separator: " ", maxSplits: 1).first ?? ""
        return program == "claude" || program.hasSuffix("/claude") || commandLine.contains("/@anthropic-ai/claude-code/cli.js")
    }

    private static func processTable(column: String) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axww", "-o", column]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
