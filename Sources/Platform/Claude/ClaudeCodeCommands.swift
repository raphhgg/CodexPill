import CryptoKit
import Foundation

enum ClaudeCodeCommandError: Error, Equatable, Sendable {
    case notInstalled
    case launchFailed
    /// The user cancelled, so the command was stopped.
    case cancelled
    case timedOut
    /// Claude Code's login failed or saved no Claude sign-in.
    case signInFailed
    /// The sign-in has no account record, so Refill can't tell which account it is.
    case accountUnknown
    /// Refill could not make its throwaway config folder.
    case folderUnavailable
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

/// Claude Code's Keychain items for throwaway config folders.
protocol ClaudeCodeFolderKeychain: Sendable {
    func read(service: String) -> Data?
    /// True when the item is gone afterwards, including when there was none.
    func delete(service: String) -> Bool
}

/// Claude Code's own login and renewal. For saved accounts they run in a throwaway config folder so the user's Claude
/// Code sign-in is never read or changed. Refill only copies out the sign-in Claude Code saved there, then deletes
/// the folder and its Keychain item, also when the run fails or is cancelled.
///
/// With `CLAUDE_CONFIG_DIR` set, Claude Code saves its sign-in in the Keychain item
/// `Claude Code-credentials-<first 8 hex of sha256(CLAUDE_CONFIG_DIR)>`, or in `.credentials.json` when the Keychain
/// refuses, and its account record in `.claude.json` in that folder.
struct ClaudeCodeCommands: Sendable {
    static let loginArguments = ["auth", "login", "--claudeai"]
    /// Claude Code renews a sign-in that is past its expiry whenever this runs. It makes no model call.
    static let renewalArguments = ["doctor"]
    static let loginTimeout: Duration = .seconds(15 * 60)
    static let renewalTimeout: Duration = .seconds(2 * 60)

    let processes: any ClaudeCodeProcessRunning
    let keychain: any ClaudeCodeFolderKeychain
    /// Holds every throwaway config folder. Refill owns it.
    let root: URL
    var newFolderName: @Sendable () -> String = { UUID().uuidString }

    var isInstalled: Bool {
        processes.executable != nil
    }

    static func keychainService(forConfigDirectory path: String) -> String {
        let digest = SHA256.hash(data: Data(path.precomposedStringWithCanonicalMapping.utf8))
        return "Claude Code-credentials-" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// Signs in through Claude Code's login in the browser and returns the sign-in it saved.
    func signIn() async throws(ClaudeCodeCommandError) -> ClaudeCodeSignInSnapshot {
        try await inThrowawayFolder { folder throws(ClaudeCodeCommandError) in
            let status = try await processes.run(
                Self.loginArguments,
                configDirectory: folder.path,
                workingDirectory: folder,
                timeout: Self.loginTimeout
            )
            guard status == 0, let signIn = savedSignIn(in: folder) else { throw .signInFailed }
            guard signIn.identity != nil else { throw .accountUnknown }
            return signIn
        }
    }

    /// Lets Claude Code renew a saved sign-in. Returns the renewed sign-in, or nil when Claude Code changed nothing.
    func renew(_ saved: ClaudeCodeSignInSnapshot) async throws(ClaudeCodeCommandError) -> ClaudeCodeSignInSnapshot? {
        try await inThrowawayFolder { folder throws(ClaudeCodeCommandError) in
            do {
                try write(saved.credentialsFileData, to: folder.appendingPathComponent(".credentials.json"))
                try write(saved.globalConfigData, to: folder.appendingPathComponent(".claude.json"))
            } catch {
                throw .folderUnavailable
            }
            _ = try await processes.run(
                Self.renewalArguments,
                configDirectory: folder.path,
                workingDirectory: folder,
                timeout: Self.renewalTimeout
            )
            guard let renewed = savedSignIn(in: folder), !renewed.hasSameCredentials(as: saved), renewed.identity == saved.identity else {
                return nil
            }
            return renewed
        }
    }

    /// Signs Claude Code itself in, in its own config folder. Only for a Claude Code with no sign-in, which has
    /// nothing to lose: a sign-in made elsewhere could not be switched in, because a switch updates Claude Code's item.
    func signInToClaudeCode(configDirectory: String?) async throws(ClaudeCodeCommandError) {
        guard isInstalled else { throw .notInstalled }
        let status = try await processes.run(
            Self.loginArguments,
            configDirectory: configDirectory,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            timeout: Self.loginTimeout
        )
        guard status == 0 else { throw .signInFailed }
    }

    /// Lets Claude Code renew its own live sign-in, in its own config folder. Claude Code writes the result itself.
    func renewClaudeCode(configDirectory: String?) async throws(ClaudeCodeCommandError) {
        _ = try await processes.run(
            Self.renewalArguments,
            configDirectory: configDirectory,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            timeout: Self.renewalTimeout
        )
    }

    /// Deletes folders and Keychain items an earlier run left behind when Refill quit in the middle of it.
    func removeLeftovers() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        folders.forEach(discard)
    }

    private func inThrowawayFolder<Result>(
        _ body: (URL) async throws(ClaudeCodeCommandError) -> Result
    ) async throws(ClaudeCodeCommandError) -> Result {
        guard isInstalled else { throw .notInstalled }
        let folder = root.appendingPathComponent(newFolderName(), isDirectory: true)
        do {
            try FilePermissionHardening.createPrivateDirectory(at: folder)
        } catch {
            throw .folderUnavailable
        }
        defer { discard(folder) }
        return try await body(folder)
    }

    /// Claude Code reads its Keychain item first and falls back to `.credentials.json`, so Refill does too.
    private func savedSignIn(in folder: URL) -> ClaudeCodeSignInSnapshot? {
        let credentials = keychain.read(service: Self.keychainService(forConfigDirectory: folder.path))
            ?? (try? ClaudeCredentialsSource.contentsIfPresent(of: folder.appendingPathComponent(".credentials.json")))
        let globalConfig = try? ClaudeCredentialsSource.contentsIfPresent(of: folder.appendingPathComponent(".claude.json"))
        return credentials.flatMap { ClaudeCodeSignInSnapshot(credentials: $0, globalConfig: globalConfig) }
    }

    private func write(_ data: Data, to file: URL) throws {
        try data.write(to: file, options: .atomic)
        try FilePermissionHardening.repairPrivateFile(at: file)
    }

    private func discard(_ folder: URL) {
        _ = keychain.delete(service: Self.keychainService(forConfigDirectory: folder.path))
        try? FileManager.default.removeItem(at: folder)
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
        // `claude auth login` also accepts a pasted code on stdin, so stdin stays open and empty until it exits.
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
