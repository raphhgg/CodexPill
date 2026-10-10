import Foundation

/// Tells whether Claude Code is running. A running Claude Code keeps its sign-in in memory and writes it back when
/// it renews the token, which would undo a switch.
protocol ClaudeCodeProcessDetecting: Sendable {
    func isClaudeCodeRunning() -> Bool
}

/// Reads the process table with `ps`. It counts any `claude` executable, including the copy the Claude desktop app runs.
struct SystemClaudeCodeProcessDetector: ClaudeCodeProcessDetecting {
    /// When the process table can't be read, it reports Claude Code as running, so a switch is refused rather than risked.
    func isClaudeCodeRunning() -> Bool {
        guard let executables = Self.processTable(column: "comm="), let commandLines = Self.processTable(column: "args=") else {
            return true
        }
        return executables.contains(where: Self.isClaudeCodeExecutable) || commandLines.contains(where: Self.isClaudeCodeCommandLine)
    }

    /// The native installer runs `~/.local/share/claude/versions/<version>`; other installs run a file named `claude`.
    static func isClaudeCodeExecutable(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent == "claude" || url.deletingLastPathComponent().path.hasSuffix("/claude/versions")
    }

    /// An npm install runs under `node` and sets its process title, so its first argument reads `claude`.
    static func isClaudeCodeCommandLine(_ commandLine: String) -> Bool {
        commandLine.split(separator: " ", maxSplits: 1).first == "claude"
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
