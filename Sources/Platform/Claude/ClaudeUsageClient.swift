import Foundation

enum ClaudeUsageStatus: Equatable, Sendable {
    case signedOut
    case keychainAccessNeeded
    /// The credentials file or Keychain item exists but could not be read or parsed.
    case signInUnreadable
    /// The token has expired or Anthropic rejected it (401). Claude Code renews it when it next runs.
    case signInExpired
    /// Anthropic knows the token but refuses the usage read (403), for example a token without the profile scope.
    case forbidden
    /// Anthropic answered 429, or its `Retry-After` has not passed yet.
    case rateLimited
    case unreachable
    case serviceError
    case unexpectedResponse
    case available(ClaudeUsageReport, planName: String?, email: String?)
}

/// Reads Claude Code's sign-in and fetches its usage, once per call. It holds no token between calls.
actor ClaudeUsageClient {
    static let defaultRetryAfter: TimeInterval = 5 * 60

    private let credentials: ClaudeCredentialsSource
    private let webClient: any ClaudeUsageWebClient
    private var promptAllowedOnNextRead = false
    private var rateLimitedUntil: Date?

    init(credentials: ClaudeCredentialsSource, webClient: any ClaudeUsageWebClient) {
        self.credentials = credentials
        self.webClient = webClient
    }

    /// Lets the next read show the Keychain prompt. Call it only from a user action.
    func allowKeychainPromptOnNextRead() {
        promptAllowedOnNextRead = true
    }

    /// When Claude Code's live sign-in expires, read without the Keychain prompt. Nil when it can't be read.
    func liveSignInExpiry() -> Date? {
        guard case let .credentials(signIn) = credentials.lookup(allowingPrompt: false) else { return nil }
        return signIn.expiresAt
    }

    func refresh(now: Date) async -> ClaudeUsageStatus {
        let allowingPrompt = promptAllowedOnNextRead
        promptAllowedOnNextRead = false
        if let rateLimitedUntil, now < rateLimitedUntil {
            return .rateLimited
        }

        let signIn: ClaudeCredentials
        switch credentials.lookup(allowingPrompt: allowingPrompt) {
        case .signedOut: return .signedOut
        case .keychainAccessNeeded:
            UsageReadFailure.keychainAccess.log(for: .claude)
            return .keychainAccessNeeded
        case .unreadable:
            UsageReadFailure.parse.log(for: .claude)
            return .signInUnreadable
        case let .credentials(found): signIn = found
        }
        guard !signIn.isExpired(at: now) else { return .signInExpired }

        let data: Data
        do {
            data = try await webClient.usage(using: signIn.accessToken)
        } catch {
            UsageReadFailure(error).log(for: .claude)
            switch error {
            case .unauthorized: return .signInExpired
            case .forbidden: return .forbidden
            case let .rateLimited(retryAfter):
                rateLimitedUntil = now.addingTimeInterval(retryAfter ?? Self.defaultRetryAfter)
                return .rateLimited
            case .httpStatus: return .serviceError
            case .transport: return .unreachable
            }
        }

        do {
            return .available(try ClaudeUsageAPI.parseUsage(data), planName: signIn.planName, email: signIn.email)
        } catch {
            UsageReadFailure.parse.log(for: .claude)
            return .unexpectedResponse
        }
    }
}
