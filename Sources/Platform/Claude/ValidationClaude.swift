import Foundation

/// Isolated runs read a fake credentials item from a file instead of the Keychain. A background read is refused
/// until one read that allows a prompt succeeds, so the "Allow Keychain access" flow can be exercised.
final class ValidationClaudeKeychain: ClaudeKeychainReading, @unchecked Sendable {
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
}

/// Isolated runs read a usage response from disk instead of calling Anthropic. A missing file reads as a network failure.
struct ValidationClaudeUsageWebClient: ClaudeUsageWebClient {
    static let fileName = "claude-usage-response.json"

    let fileURL: URL

    func usage(using _: ClaudeAccessToken) async throws -> Data {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw ClaudeUsageWebError.transport
        }
        return data
    }
}
