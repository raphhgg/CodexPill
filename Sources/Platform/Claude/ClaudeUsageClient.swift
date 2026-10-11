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
    case available(ClaudeUsageReport, planName: String?)
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

    func refresh(now: Date) async -> ClaudeUsageStatus {
        let allowingPrompt = promptAllowedOnNextRead
        promptAllowedOnNextRead = false
        if let rateLimitedUntil, now < rateLimitedUntil {
            return .rateLimited
        }

        let signIn: ClaudeCredentials
        switch credentials.lookup(allowingPrompt: allowingPrompt) {
        case .signedOut: return .signedOut
        case .keychainAccessNeeded: return .keychainAccessNeeded
        case .unreadable: return .signInUnreadable
        case let .credentials(found): signIn = found
        }
        let status = await usage(with: signIn, now: now)
        if case let .rateLimited(retryAfter) = status {
            rateLimitedUntil = now.addingTimeInterval(retryAfter ?? Self.defaultRetryAfter)
            return .rateLimited
        }
        return status.claudeUsageStatus
    }

    /// Reads a saved account's limits with that account's own sign-in. A wait Anthropic asks for here does not
    /// hold back the read of Claude Code's own sign-in.
    func refresh(savedSignIn: ClaudeCodeSignInSnapshot, now: Date) async -> ClaudeUsageStatus {
        guard let credentials = (try? ClaudeCredentials(json: savedSignIn.itemData)) ?? nil else { return .signInUnreadable }
        return await usage(with: credentials, now: now).claudeUsageStatus
    }

    private func usage(with signIn: ClaudeCredentials, now: Date) async -> UsageFetch {
        guard !signIn.isExpired(at: now) else { return .status(.signInExpired) }

        let data: Data
        do {
            data = try await webClient.usage(using: signIn.accessToken)
        } catch {
            switch error {
            case .unauthorized: return .status(.signInExpired)
            case .forbidden: return .status(.forbidden)
            case let .rateLimited(retryAfter): return .rateLimited(retryAfter: retryAfter)
            case .httpStatus: return .status(.serviceError)
            case .transport: return .status(.unreachable)
            }
        }

        do {
            return .status(.available(try ClaudeUsageAPI.parseUsage(data), planName: signIn.planName))
        } catch {
            return .status(.unexpectedResponse)
        }
    }
}

private enum UsageFetch {
    case status(ClaudeUsageStatus)
    case rateLimited(retryAfter: TimeInterval?)

    var claudeUsageStatus: ClaudeUsageStatus {
        switch self {
        case let .status(status): status
        case .rateLimited: .rateLimited
        }
    }
}
