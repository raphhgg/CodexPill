import Foundation

/// Claude Code's OAuth access token. It is only ever placed in the `Authorization` header and never printed.
struct ClaudeAccessToken: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let value: String

    init?(_ value: String) {
        guard !value.isEmpty else { return nil }
        self.value = value
    }

    var authorizationHeaderValue: String {
        "Bearer \(value)"
    }

    var description: String {
        "ClaudeAccessToken(redacted)"
    }

    var debugDescription: String {
        description
    }

    var customMirror: Mirror {
        Mirror(self, children: EmptyCollection<Mirror.Child>())
    }
}

/// The parts of Claude Code's sign-in that CodexPill uses. The refresh token is never decoded.
struct ClaudeCredentials: Sendable {
    let accessToken: ClaudeAccessToken
    let expiresAt: Date?
    let subscriptionType: String?
    /// The plan with its usage multiplier, such as `max_20x` from `rateLimitTier` `default_claude_max_20x`, or the
    /// plan alone when Claude Code recorded no multiplier.
    let planName: String?

    /// Parses Claude Code's credentials JSON. Returns nil when it holds no Claude sign-in, for example only `mcpOAuth`,
    /// and throws when it is not credentials JSON at all.
    init?(json data: Data) throws {
        guard
            let oauth = try JSONDecoder().decode(CredentialsDTO.self, from: data).claudeAiOauth,
            let accessToken = oauth.accessToken.flatMap(ClaudeAccessToken.init)
        else {
            return nil
        }
        self.accessToken = accessToken
        expiresAt = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
        subscriptionType = oauth.subscriptionType.flatMap { $0.isEmpty ? nil : $0 }
        let multiplier = oauth.rateLimitTier?.split(separator: "_").last.flatMap { $0.hasSuffix("x") && Int($0.dropLast()) != nil ? $0 : nil }
        planName = subscriptionType.map { plan in multiplier.map { "\(plan)_\($0)" } ?? plan }
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
    let rateLimitTier: String?
}
