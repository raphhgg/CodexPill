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

/// Isolated runs keep CodexPill's own sign-in in a file instead of the Keychain.
struct ValidationClaudeSignInKeychain: ClaudeSignInStoring {
    static let fileName = "claude-sign-in-item.json"

    let fileURL: URL

    func read(allowingPrompt _: Bool) -> ClaudeKeychainRead {
        (try? Data(contentsOf: fileURL)).map(ClaudeKeychainRead.found) ?? .notFound
    }

    func save(_ signIn: ClaudeSignIn, allowingPrompt _: Bool) -> Bool {
        (try? signIn.keychainData.write(to: fileURL, options: .atomic)) != nil
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Isolated runs answer every token request with a fixture body. A missing file reads as a network failure,
/// and a body whose `error` is `invalid_grant` reads as a rejected sign-in.
struct ValidationClaudeTokenEndpoint: ClaudeTokenEndpoint {
    static let fileName = "claude-token-response.json"

    let fileURL: URL

    func exchange(code _: String, pkce _: ClaudePKCE, state _: String, redirectURI _: URL, now: Date) async throws(ClaudeTokenError) -> ClaudeSignIn {
        try response(now: now, currentRefreshToken: nil)
    }

    func refresh(_ refreshToken: ClaudeRefreshToken, now: Date) async throws(ClaudeTokenError) -> ClaudeSignIn {
        try response(now: now, currentRefreshToken: refreshToken)
    }

    func revoke(_: ClaudeRefreshToken) async {}

    private func response(now: Date, currentRefreshToken: ClaudeRefreshToken?) throws(ClaudeTokenError) -> ClaudeSignIn {
        guard let data = try? Data(contentsOf: fileURL) else { throw .transport }
        let status = String(decoding: data, as: UTF8.self).contains("invalid_grant") ? 400 : 200
        return try ClaudeOAuth.signIn(fromTokenResponse: data, status: status, receivedAt: now, currentRefreshToken: currentRefreshToken)
    }
}

/// Isolated runs never open a browser or a port. The authorize URL is written to `claude-authorize-url.txt`,
/// and the callback is the request line a script writes to `claude-browser-callback.txt`.
struct ValidationClaudeRedirectReceiver: ClaudeOAuthRedirectReceiver {
    static let authorizeURLFileName = "claude-authorize-url.txt"
    static let callbackFileName = "claude-browser-callback.txt"

    let rootDirectory: URL
    let redirectURI = ClaudeOAuth.redirectURI(port: 54_545)

    func nextCallback() async throws -> ClaudeOAuthCallback {
        let fileURL = rootDirectory.appendingPathComponent(Self.callbackFileName)
        while true {
            if let data = try? Data(contentsOf: fileURL) {
                try? FileManager.default.removeItem(at: fileURL)
                let requestLine = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if let callback = ClaudeOAuth.callback(fromRequestLine: requestLine) {
                    return callback
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    func stop() {}

    func recordAuthorizeURL(_ url: URL) {
        try? Data(url.absoluteString.utf8).write(to: rootDirectory.appendingPathComponent(Self.authorizeURLFileName))
    }
}
