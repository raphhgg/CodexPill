import Foundation

enum ClaudeUsageStatus: Equatable, Sendable {
    case signedOut
    case keychainAccessNeeded
    /// The credentials file or Keychain item exists but could not be read or parsed.
    case signInUnreadable
    /// The sign-in has expired or Anthropic rejected it (401).
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

/// Fetches Claude usage with the sign-in the user connected: CodexPill's own, or Claude Code's while that is unexpired.
/// It never falls back from one to the other, and it refreshes only its own sign-in, one refresh at a time.
actor ClaudeUsageClient {
    static let defaultRetryAfter: TimeInterval = 5 * 60

    private let claudeCode: ClaudeCredentialsSource
    private let signInStore: any ClaudeSignInStoring
    private let tokenEndpoint: any ClaudeTokenEndpoint
    private let webClient: any ClaudeUsageWebClient
    private var promptAllowedOnNextRead = false
    private var rateLimitedUntil: Date?
    /// A rotated sign-in the Keychain refused to save. It wins over the stored one until a save succeeds,
    /// because the refresh token in the Keychain may already be spent.
    private var unsavedSignIn: ClaudeSignIn?
    private var refreshInFlight: Task<Result<ClaudeSignIn, ClaudeTokenError>, Never>?

    init(
        claudeCode: ClaudeCredentialsSource,
        signInStore: any ClaudeSignInStoring,
        tokenEndpoint: any ClaudeTokenEndpoint,
        webClient: any ClaudeUsageWebClient
    ) {
        self.claudeCode = claudeCode
        self.signInStore = signInStore
        self.tokenEndpoint = tokenEndpoint
        self.webClient = webClient
    }

    /// Lets the next read show the Keychain prompt. Call it only from a user action.
    func allowKeychainPromptOnNextRead() {
        promptAllowedOnNextRead = true
    }

    /// True when Claude Code's sign-in can be read without a prompt and is unexpired, so connecting needs no browser.
    func hasUsableClaudeCodeSignIn(now: Date) -> Bool {
        guard case let .credentials(credentials) = claudeCode.lookup(allowingPrompt: false) else { return false }
        return !credentials.isExpired(at: now)
    }

    /// Saves a new sign-in right after the user signed in.
    func store(_ signIn: ClaudeSignIn) {
        rateLimitedUntil = nil
        unsavedSignIn = signInStore.save(signIn, allowingPrompt: true) ? nil : signIn
    }

    /// Deletes CodexPill's own sign-in and asks Anthropic to revoke it. Claude Code's sign-in is untouched.
    func forgetSignIn() async {
        let stored: ClaudeSignIn? = if case let .found(data) = signInStore.read(allowingPrompt: false) {
            ClaudeSignIn(keychainData: data)
        } else {
            nil
        }
        let signIn = unsavedSignIn ?? stored
        unsavedSignIn = nil
        signInStore.delete()
        if let signIn {
            await tokenEndpoint.revoke(signIn.refreshToken)
        }
    }

    func refresh(now: Date, using source: ClaudeSignInSource) async -> ClaudeUsageStatus {
        let allowingPrompt = promptAllowedOnNextRead
        promptAllowedOnNextRead = false
        if let rateLimitedUntil, now < rateLimitedUntil {
            return .rateLimited
        }

        let token: ClaudeAccessToken
        let planName: String?
        let renewable: ClaudeSignIn?
        let lookup = switch source {
        case .claudeCode: claudeCodeToken(now: now, allowingPrompt: allowingPrompt)
        case .codexPill: await ownToken(now: now, allowingPrompt: allowingPrompt)
        }
        switch lookup {
        case let .stop(status): return status
        case let .token(found, plan, renewal): (token, planName, renewable) = (found, plan, renewal)
        }

        var response = await usage(using: token)
        if case .failure(.unauthorized) = response, let renewable {
            guard case let .success(refreshed) = await refreshOnce(renewable, now: now, allowingPrompt: allowingPrompt) else {
                return .signInExpired
            }
            response = await usage(using: refreshed.accessToken)
        }

        let data: Data
        switch response {
        case let .success(body):
            data = body
        case let .failure(error):
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
            return .available(try ClaudeUsageAPI.parseUsage(data), planName: planName)
        } catch {
            return .unexpectedResponse
        }
    }

    private func usage(using token: ClaudeAccessToken) async -> Result<Data, ClaudeUsageWebError> {
        do throws(ClaudeUsageWebError) {
            return .success(try await webClient.usage(using: token))
        } catch {
            return .failure(error)
        }
    }

    /// CodexPill's own sign-in, refreshed shortly before it expires. A missing or rejected sign-in needs a new one.
    private func ownToken(now: Date, allowingPrompt: Bool) async -> TokenLookup {
        let signIn: ClaudeSignIn
        if let unsavedSignIn {
            signIn = unsavedSignIn
            if signInStore.save(signIn, allowingPrompt: allowingPrompt) { self.unsavedSignIn = nil }
        } else {
            switch signInStore.read(allowingPrompt: allowingPrompt) {
            case .notFound: return .stop(.signInExpired)
            case .needsPermission: return .stop(.keychainAccessNeeded)
            case .failed: return .stop(.signInUnreadable)
            case let .found(data):
                guard let stored = ClaudeSignIn(keychainData: data) else { return .stop(.signInUnreadable) }
                signIn = stored
            }
        }
        guard signIn.needsRefresh(at: now) else { return .token(signIn.accessToken, planName: nil, renewable: signIn) }

        switch await refreshOnce(signIn, now: now, allowingPrompt: allowingPrompt) {
        case let .success(refreshed):
            return .token(refreshed.accessToken, planName: nil, renewable: nil)
        case .failure(.invalidGrant):
            return .stop(.signInExpired)
        case .failure:
            return signIn.isExpired(at: now) ? .stop(.unreachable) : .token(signIn.accessToken, planName: nil, renewable: nil)
        }
    }

    private func claudeCodeToken(now: Date, allowingPrompt: Bool) -> TokenLookup {
        switch claudeCode.lookup(allowingPrompt: allowingPrompt) {
        case .signedOut: .stop(.signedOut)
        case .keychainAccessNeeded: .stop(.keychainAccessNeeded)
        case .unreadable: .stop(.signInUnreadable)
        case let .credentials(credentials):
            credentials.isExpired(at: now)
                ? .stop(.signInExpired)
                : .token(credentials.accessToken, planName: credentials.subscriptionType, renewable: nil)
        }
    }

    /// Concurrent reads share one refresh, so a rotated refresh token is never spent twice.
    private func refreshOnce(_ signIn: ClaudeSignIn, now: Date, allowingPrompt: Bool) async -> Result<ClaudeSignIn, ClaudeTokenError> {
        if let refreshInFlight {
            return await refreshInFlight.value
        }
        let task = Task { [tokenEndpoint] () -> Result<ClaudeSignIn, ClaudeTokenError> in
            do throws(ClaudeTokenError) {
                return .success(try await tokenEndpoint.refresh(signIn.refreshToken, now: now))
            } catch {
                return .failure(error)
            }
        }
        refreshInFlight = task
        let outcome = await task.value
        refreshInFlight = nil

        switch outcome {
        case let .success(refreshed):
            unsavedSignIn = signInStore.save(refreshed, allowingPrompt: allowingPrompt) ? nil : refreshed
        case .failure(.invalidGrant):
            unsavedSignIn = nil
            signInStore.delete()
        case .failure:
            break
        }
        return outcome
    }
}

/// The token for one usage request, or the status a read ends with before any request. `renewable` is CodexPill's own
/// sign-in when a 401 may still try one refresh; it is nil for Claude Code's sign-in and after a refresh in this read.
private enum TokenLookup {
    case token(ClaudeAccessToken, planName: String?, renewable: ClaudeSignIn?)
    case stop(ClaudeUsageStatus)
}
