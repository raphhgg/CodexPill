import Foundation

/// A Claude OAuth secret. It prints as `<Type>(redacted)` and reflects no children, so it never reaches a log or `dump`.
protocol RedactedClaudeSecret: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}

extension RedactedClaudeSecret {
    var description: String {
        "\(Self.self)(redacted)"
    }

    var debugDescription: String {
        description
    }

    var customMirror: Mirror {
        Mirror(self, children: EmptyCollection<Mirror.Child>())
    }
}

/// A Claude OAuth access token. It is only ever placed in the `Authorization` header.
struct ClaudeAccessToken: RedactedClaudeSecret {
    /// Read only to build a request or to store CodexPill's own sign-in in its Keychain item.
    let exposedValue: String

    init?(_ value: String) {
        guard !value.isEmpty else { return nil }
        exposedValue = value
    }

    var authorizationHeaderValue: String {
        "Bearer \(exposedValue)"
    }
}

/// The refresh token of CodexPill's own Claude sign-in. Claude Code's refresh token is never decoded.
struct ClaudeRefreshToken: RedactedClaudeSecret {
    /// Read only to build a token request or to store CodexPill's own sign-in in its Keychain item.
    let exposedValue: String

    init?(_ value: String) {
        guard !value.isEmpty else { return nil }
        exposedValue = value
    }
}

/// The parts of Claude Code's sign-in that CodexPill uses. The refresh token is never decoded.
struct ClaudeCredentials: Sendable {
    let accessToken: ClaudeAccessToken
    let expiresAt: Date?
    let subscriptionType: String?

    /// Parses Claude Code's credentials JSON. Returns nil when it holds no Claude sign-in, for example only `mcpOAuth`.
    init?(json data: Data) {
        guard
            let payload = try? JSONDecoder().decode(CredentialsDTO.self, from: data),
            let oauth = payload.claudeAiOauth,
            let accessToken = oauth.accessToken.flatMap(ClaudeAccessToken.init)
        else {
            return nil
        }
        self.accessToken = accessToken
        expiresAt = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
        subscriptionType = oauth.subscriptionType.flatMap { $0.isEmpty ? nil : $0 }
    }

    func isExpired(at now: Date) -> Bool {
        expiresAt.map { $0 <= now } ?? false
    }
}

private struct CredentialsDTO: Decodable {
    let claudeAiOauth: OAuthDTO?
}

private struct OAuthDTO: Decodable {
    let accessToken: String?
    let expiresAt: Double?
    let subscriptionType: String?
}
