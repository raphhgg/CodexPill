import Foundation

@testable import Refill

/// Claude Code's Keychain item as a file that Refill is already allowed to read.
struct FileClaudeCodeKeychain: ClaudeKeychainReading {
    let fileURL: URL

    func credentialsData(allowingPrompt _: Bool) -> ClaudeKeychainRead {
        guard let data = try? Data(contentsOf: fileURL) else { return .notFound }
        return .found(data)
    }
}

/// A Claude Code process table the test sets.
final class ClaudeCodeProcessProbe: ClaudeCodeProcessDetecting, @unchecked Sendable {
    private let lock = NSLock()
    private var running = false

    var isRunning: Bool {
        get { lock.withLock { running } }
        set { lock.withLock { running = newValue } }
    }

    func isClaudeCodeRunning() -> Bool {
        isRunning
    }
}

/// The `claude` command as far as Refill runs it: `doctor` with Claude Code's own config, which renews an expired
/// sign-in through `renewClaudeCode`.
final class FakeClaudeCode: ClaudeCodeProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var installed = true
    private var commandLog: [String] = []
    var renewClaudeCode: (@Sendable () async -> Void)?

    var isInstalled: Bool {
        get { lock.withLock { installed } }
        set { lock.withLock { installed = newValue } }
    }

    /// Each run as `<arguments> in <CLAUDE_CONFIG_DIR's last path component>`, or `in default`.
    var commands: [String] { lock.withLock { commandLog } }

    var executable: URL? {
        isInstalled ? URL(fileURLWithPath: "/fake/bin/claude") : nil
    }

    func run(
        _ arguments: [String],
        configDirectory: String?,
        workingDirectory _: URL,
        timeout _: Duration
    ) async throws(ClaudeCodeCommandError) -> Int32 {
        lock.withLock {
            commandLog.append("\(arguments.joined(separator: " ")) in \(configDirectory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "default")")
        }
        guard arguments == ["doctor"] else { return 127 }
        await renewClaudeCode?()
        return 0
    }
}

/// `/api/oauth/usage` answering each fake access token with its own numbers. Unknown tokens get 401.
final class FakeClaudeUsageServer: ClaudeUsageWebClient, @unchecked Sendable {
    private let lock = NSLock()
    private var sessionPercents: [String: Int] = [:]
    private var tokens: [String] = []

    func answer(_ token: String, sessionPercent: Int) {
        lock.withLock { sessionPercents[token] = sessionPercent }
    }

    /// The bearer tokens that reached the server, in order.
    var requests: [String] { lock.withLock { tokens } }

    func usage(using token: ClaudeAccessToken) async throws(ClaudeUsageWebError) -> Data {
        let value = String(token.authorizationHeaderValue.dropFirst("Bearer ".count))
        let percent = lock.withLock {
            tokens.append(value)
            return sessionPercents[value]
        }
        guard let percent else { throw .unauthorized }
        return Data(#"{"five_hour":{"utilization":\#(percent),"resets_at":"2030-01-01T00:00:00Z"},"seven_day":{"utilization":21,"resets_at":"2030-01-05T00:00:00Z"}}"#.utf8)
    }
}
