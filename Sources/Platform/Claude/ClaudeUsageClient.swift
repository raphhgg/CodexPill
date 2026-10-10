import Foundation

enum ClaudeUsageStatus: Equatable, Sendable {
    case signedOut
    case keychainAccessNeeded
    /// The token has expired or Anthropic rejected it. Claude Code renews it when it next runs.
    case signInExpired
    /// Anthropic could not be reached, asked CodexPill to slow down, or sent something unexpected.
    case unavailable
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
            return .unavailable
        }

        let signIn: ClaudeCredentials
        switch credentials.lookup(allowingPrompt: allowingPrompt) {
        case .signedOut: return .signedOut
        case .keychainAccessNeeded: return .keychainAccessNeeded
        case .unreadable: return .unavailable
        case let .credentials(found): signIn = found
        }
        guard !signIn.isExpired(at: now) else { return .signInExpired }

        let data: Data
        do {
            data = try await webClient.usage(using: signIn.accessToken)
        } catch ClaudeUsageWebError.unauthorized {
            return .signInExpired
        } catch let ClaudeUsageWebError.rateLimited(retryAfter) {
            rateLimitedUntil = now.addingTimeInterval(retryAfter ?? Self.defaultRetryAfter)
            return .unavailable
        } catch {
            return .unavailable
        }

        guard let report = try? ClaudeUsageAPI.parseUsage(data) else { return .unavailable }
        return .available(report, planName: signIn.subscriptionType)
    }
}
