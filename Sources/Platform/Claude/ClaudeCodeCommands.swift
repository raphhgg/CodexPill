import Foundation

enum ClaudeCodeCommandError: Error, Equatable, Sendable {
    case notInstalled
    case launchFailed
    /// The user cancelled, so the command was stopped.
    case cancelled
    case timedOut
}

/// Runs the `claude` executable. Cancelling the calling task stops it.
protocol ClaudeCodeProcessRunning: Sendable {
    /// Where `claude` is installed, or nil when it is not.
    var executable: URL? { get }
    /// Runs `claude` and returns its exit status. `configDirectory` becomes `CLAUDE_CONFIG_DIR` exactly as given, or
    /// stays unset so Claude Code uses its own default folder.
    func run(
        _ arguments: [String],
        configDirectory: String?,
        workingDirectory: URL,
        timeout: Duration
    ) async throws(ClaudeCodeCommandError) -> Int32
}

/// Runs `claude doctor`, which makes Claude Code renew its own expired live sign-in. Claude Code writes the result
/// itself, in its own config folder. CodexPill never writes Claude Code's files or Keychain item.
struct ClaudeCodeCommands: Sendable {
    /// Claude Code renews a sign-in that is past its expiry whenever this runs. It makes no model call.
    static let renewalArguments = ["doctor"]
    static let renewalTimeout: Duration = .seconds(2 * 60)

    let processes: any ClaudeCodeProcessRunning

    var isInstalled: Bool {
        processes.executable != nil
    }

    /// `configDirectory` is Claude Code's own `CLAUDE_CONFIG_DIR`, or nil for its default folder.
    func renewClaudeCode(configDirectory: String?) async throws(ClaudeCodeCommandError) {
        _ = try await processes.run(
            Self.renewalArguments,
            configDirectory: configDirectory,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            timeout: Self.renewalTimeout
        )
    }
}

/// Finds `claude` where its installers put it, since a menu bar app gets no shell `PATH`, and runs it with a minimal
/// environment: none of the user's shell variables, such as an API key, reach it.
struct SystemClaudeCodeProcessRunner: ClaudeCodeProcessRunning {
    var homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    /// Isolated runs pass their own folder, so they never run the real `claude`.
    var searchDirectories: [URL]?

    var executable: URL? {
        let directories = searchDirectories ?? [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".claude/local", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        ]
        return directories
            .map { $0.appendingPathComponent("claude") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func run(
        _ arguments: [String],
        configDirectory: String?,
        workingDirectory: URL,
        timeout: Duration
    ) async throws(ClaudeCodeCommandError) -> Int32 {
        guard let executable else { throw .notInstalled }
        guard !Task.isCancelled else { throw .cancelled }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        var environment = [
            "HOME": homeDirectory.path,
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "PATH": "\(executable.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": NSTemporaryDirectory(),
        ]
        environment["CLAUDE_CONFIG_DIR"] = configDirectory
        process.environment = environment
        // Stdin stays open and empty until `claude` exits, so it never waits on a terminal.
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let running = RunningClaudeCode(process: process)
        do {
            try process.run()
        } catch {
            throw .launchFailed
        }
        let timer = Task {
            try await Task.sleep(for: timeout)
            running.stop(.timedOut)
        }
        let status = await withTaskCancellationHandler {
            await running.exitStatus()
        } onCancel: {
            running.stop(.cancelled)
        }
        timer.cancel()
        try? input.fileHandleForWriting.close()
        if let reason = running.stopReason { throw reason }
        return status
    }
}

private final class RunningClaudeCode: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var status: Int32?
    private var waiter: CheckedContinuation<Int32, Never>?
    private var reason: ClaudeCodeCommandError?

    init(process: Process) {
        self.process = process
        process.terminationHandler = { [weak self] process in
            self?.finish(process.terminationStatus)
        }
    }

    var stopReason: ClaudeCodeCommandError? {
        lock.withLock { reason }
    }

    func exitStatus() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    func stop(_ stopReason: ClaudeCodeCommandError) {
        let isRunning = lock.withLock {
            reason = reason ?? stopReason
            return status == nil
        }
        if isRunning {
            process.terminate()
        }
    }

    private func finish(_ exitStatus: Int32) {
        let continuation = lock.withLock {
            status = exitStatus
            defer { waiter = nil }
            return waiter
        }
        continuation?.resume(returning: exitStatus)
    }
}
