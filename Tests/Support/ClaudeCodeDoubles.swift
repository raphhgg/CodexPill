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
