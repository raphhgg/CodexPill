import Foundation

@testable import CodexPill

/// Claude Code's Keychain item as a file. A background read is refused until one read that allows a prompt
/// succeeds, like a fresh Keychain access rule.
final class FileClaudeCodeKeychain: ClaudeCodeKeychainItem, @unchecked Sendable {
    static let fileName = "claude-keychain-item.json"

    private let fileURL: URL
    private let lock = NSLock()
    private var isAllowed = false

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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }
}

/// CodexPill's saved Claude Code accounts as `claude-code-account-<id>.json` files.
struct FileClaudeCodeAccountItems: ClaudeCodeAccountItemStoring {
    let rootDirectory: URL

    func read(_ id: UUID) -> Data? {
        try? Data(contentsOf: fileURL(for: id))
    }

    func save(_ data: Data, for id: UUID) -> Bool {
        (try? data.write(to: fileURL(for: id), options: .atomic)) != nil
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    private func fileURL(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent("claude-code-account-\(id.uuidString).json")
    }
}
