import CryptoKit
import Foundation

@testable import Refill

/// The `claude` command and its Keychain, as far as Refill uses them, following what Claude Code 2.1.294 does.
/// A login with `CLAUDE_CONFIG_DIR` saves the sign-in in `Claude Code-credentials-<first 8 hex of sha256(dir)>` and the
/// account record in `<dir>/.claude.json`. `doctor` renews an expired sign-in into that item and deletes
/// `.credentials.json`. Without `CLAUDE_CONFIG_DIR`, a login signs Claude Code itself in through `signInClaudeCode` and
/// `doctor` renews Claude Code's own sign-in through `renewClaudeCode`.
final class FakeClaudeCode: ClaudeCodeProcessRunning, ClaudeCodeFolderKeychain, @unchecked Sendable {
    enum Login {
        case signsIn(credentials: Data, globalConfig: Data)
        case savesThenFails(credentials: Data)
        /// Waits for the browser until the gate opens or the task is cancelled, then signs in.
        case waitsForBrowser(TestGate, credentials: Data, globalConfig: Data)
    }

    enum Renewal {
        case changesNothing
        /// `meanwhile` runs while Claude Code renews, such as another writer changing the saved copy.
        case renews(credentials: Data, meanwhile: (@Sendable () -> Void)? = nil)
        case renewsAfter(TestGate, credentials: Data)
    }

    private let lock = NSLock()
    private var installed = true
    private var loginBehavior: Login = .savesThenFails(credentials: Data())
    private var renewalBehavior: Renewal = .changesNothing
    private var items: [String: Data] = [:]
    private var commandLog: [String] = []
    private var deleted: [String] = []
    var signInClaudeCode: (@Sendable () throws -> Void)?
    var renewClaudeCode: (@Sendable () async -> Void)?

    var isInstalled: Bool {
        get { lock.withLock { installed } }
        set { lock.withLock { installed = newValue } }
    }

    var login: Login {
        get { lock.withLock { loginBehavior } }
        set { lock.withLock { loginBehavior = newValue } }
    }

    var renewal: Renewal {
        get { lock.withLock { renewalBehavior } }
        set { lock.withLock { renewalBehavior = newValue } }
    }

    /// Each run as `<arguments> in <CLAUDE_CONFIG_DIR's last path component>`, or `in default`.
    var commands: [String] { lock.withLock { commandLog } }
    var deletedServices: [String] { lock.withLock { deleted } }
    var remainingItems: [String] { lock.withLock { items.keys.sorted() } }

    static func service(for configDirectory: String) -> String {
        let digest = SHA256.hash(data: Data(configDirectory.utf8))
        return "Claude Code-credentials-" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

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
        guard let configDirectory else {
            switch arguments {
            case ["auth", "login", "--claudeai"]:
                do {
                    try signInClaudeCode?()
                    return 0
                } catch {
                    return 1
                }
            case ["doctor"]:
                await renewClaudeCode?()
                return 0
            default:
                return 127
            }
        }
        let folder = URL(fileURLWithPath: configDirectory, isDirectory: true)
        let service = Self.service(for: configDirectory)

        switch arguments {
        case ["auth", "login", "--claudeai"]:
            switch login {
            case let .signsIn(credentials, globalConfig):
                save(credentials, as: service)
                try? globalConfig.write(to: folder.appendingPathComponent(".claude.json"))
                return 0
            case let .savesThenFails(credentials):
                save(credentials, as: service)
                return 1
            case let .waitsForBrowser(gate, credentials, globalConfig):
                await withTaskCancellationHandler {
                    await gate.pass()
                } onCancel: {
                    Task { await gate.open() }
                }
                guard !Task.isCancelled else { throw .cancelled }
                save(credentials, as: service)
                try? globalConfig.write(to: folder.appendingPathComponent(".claude.json"))
                return 0
            }
        case ["doctor"]:
            switch renewal {
            case .changesNothing:
                break
            case let .renews(credentials, meanwhile):
                meanwhile?()
                renew(folder, to: credentials, as: service)
            case let .renewsAfter(gate, credentials):
                await gate.pass()
                renew(folder, to: credentials, as: service)
            }
            return 0
        default:
            return 127
        }
    }

    func read(service: String) -> Data? {
        lock.withLock { items[service] }
    }

    func delete(service: String) -> Bool {
        lock.withLock {
            deleted.append(service)
            items[service] = nil
            return true
        }
    }

    private func save(_ data: Data, as service: String) {
        lock.withLock { items[service] = data }
    }

    private func renew(_ folder: URL, to credentials: Data, as service: String) {
        save(credentials, as: service)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(".credentials.json"))
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
