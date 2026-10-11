import Foundation

@testable import Refill

/// Claude Code's Keychain item as a file. A background read is refused until one read that allows a prompt
/// succeeds, like a fresh Keychain access rule. `failsUpdates` makes every update fail.
final class FileClaudeCodeKeychain: ClaudeCodeKeychainItem, @unchecked Sendable {
    static let fileName = "claude-keychain-item.json"

    private let fileURL: URL
    private let lock = NSLock()
    private var isAllowed = false
    private var updatesFail = false

    var failsUpdates: Bool {
        get { lock.withLock { updatesFail } }
        set { lock.withLock { updatesFail = newValue } }
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func credentialsData(allowingPrompt: Bool) -> ClaudeKeychainRead {
        guard let data = try? Data(contentsOf: fileURL) else { return .notFound }
        return lock.withLock {
            isAllowed = isAllowed || allowingPrompt
            return isAllowed ? .found(data) : .needsPermission
        }
    }

    /// Like the Keychain, an update needs an existing item.
    func updateCredentialsData(_ data: Data) -> Bool {
        guard !failsUpdates, FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }
}

/// Refill's saved Claude Code accounts as `claude-code-account-<id>.json` files. `failsSaves` makes every save fail,
/// like a Keychain that refuses the change. `beforeSave` runs on the saving thread, so a test can hold a save there.
final class FileClaudeCodeAccountItems: ClaudeCodeAccountItemStoring, @unchecked Sendable {
    let rootDirectory: URL
    private let lock = NSLock()
    private var savesFail = false
    private var saveHook: (@Sendable () -> Void)?

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    var failsSaves: Bool {
        get { lock.withLock { savesFail } }
        set { lock.withLock { savesFail = newValue } }
    }

    func read(_ id: UUID) throws(ClaudeCodeAccountError) -> Data? {
        do {
            return try ClaudeCredentialsSource.contentsIfPresent(of: fileURL(for: id))
        } catch {
            throw .savedAccountsUnreadable
        }
    }

    var beforeSave: (@Sendable () -> Void)? {
        get { lock.withLock { saveHook } }
        set { lock.withLock { saveHook = newValue } }
    }

    func save(_ data: Data, for id: UUID) -> Bool {
        beforeSave?()
        guard !failsSaves else { return false }
        return (try? data.write(to: fileURL(for: id), options: .atomic)) != nil
    }

    func delete(_ id: UUID) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL(for: id).path) else { return true }
        return (try? FileManager.default.removeItem(at: fileURL(for: id))) != nil
    }

    private func fileURL(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent("claude-code-account-\(id.uuidString).json")
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
