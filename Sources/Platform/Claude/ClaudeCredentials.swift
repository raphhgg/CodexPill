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

/// The parts of Claude Code's sign-in that Refill uses. The refresh token is never decoded.
struct ClaudeCredentials: Sendable {
    let accessToken: ClaudeAccessToken
    let expiresAt: Date?
    let subscriptionType: String?
    /// The plan with its usage multiplier, such as `max_20x` from the tier `default_claude_max_20x`, or the plan alone
    /// when Claude Code recorded no multiplier.
    let planName: String?
    /// The signed-in account's email, from Claude Code's account record.
    let email: String?

    /// Parses Claude Code's credentials JSON. Returns nil when it holds no Claude sign-in, for example only `mcpOAuth`,
    /// and throws when it is not credentials JSON at all.
    ///
    /// The tier and the email come from the account record (`oauthAccount`) in `globalConfig`, because the credentials
    /// keep the tier from sign-in time even after the plan changes. The credentials' own `rateLimitTier` is used only
    /// when the account record has none.
    init?(json data: Data, globalConfig: Data? = nil) throws {
        guard
            let oauth = try JSONDecoder().decode(CredentialsDTO.self, from: data).claudeAiOauth,
            let accessToken = oauth.accessToken.flatMap(ClaudeAccessToken.init)
        else {
            return nil
        }
        self.accessToken = accessToken
        expiresAt = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
        subscriptionType = oauth.subscriptionType.flatMap { $0.isEmpty ? nil : $0 }
        let account = globalConfig.flatMap { try? JSONDecoder().decode(AccountRecordDTO.self, from: $0).oauthAccount }
        let tier = [account?.organizationRateLimitTier, account?.userRateLimitTier, oauth.rateLimitTier]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let multiplier = tier?.split(separator: "_").last.flatMap { $0.hasSuffix("x") && Int($0.dropLast()) != nil ? $0 : nil }
        planName = subscriptionType.map { plan in multiplier.map { "\(plan)_\($0)" } ?? plan }
        email = account?.emailAddress.flatMap { $0.isEmpty ? nil : $0 }
    }

    func isExpired(at now: Date) -> Bool {
        expiresAt.map { $0 <= now } ?? false
    }
}

private struct CredentialsDTO: Decodable {
    let claudeAiOauth: OAuthDTO?
}

private struct AccountRecordDTO: Decodable {
    struct Account: Decodable {
        let organizationRateLimitTier: String?
        let userRateLimitTier: String?
        let emailAddress: String?
    }

    let oauthAccount: Account?
}

private struct OAuthDTO: Decodable {
    let accessToken: String?
    let expiresAt: Double?
    let subscriptionType: String?
    let rateLimitTier: String?
}
