import Foundation

enum ClaudeUsageStatus: Equatable, Sendable {
    case signedOut
    case keychainAccessNeeded
    /// The credentials file or Keychain item exists but could not be read or parsed.
    case signInUnreadable
    /// Claude Code's token has expired or Anthropic rejected it (401). Claude Code renews it when it next runs.
    case signInExpired
    /// rusage's own sign-in is gone or Anthropic rejected it. Only a new browser sign-in helps.
    case signInRequired
    /// Anthropic knows the token but refuses the usage read (403), for example a token without the profile scope.
    case forbidden
    /// Anthropic answered 429, or its `Retry-After` has not passed yet.
    case rateLimited
    case unreachable
    case serviceError
    case unexpectedResponse
    case available(ClaudeUsageReport, planName: String?, email: String?)
}

/// Which sign-in a read uses. A read never falls back from one to the other, because they may be different accounts.
enum ClaudeSignInSource: Sendable {
    /// Claude Code's sign-in, read only.
    case claudeCode
    /// rusage's own "Sign in with Claude".
    case rusage
}

/// Fetches Claude usage once per call, with Claude Code's sign-in or rusage's own. It holds no Claude Code token
/// between calls and renews only rusage's own sign-in.
actor ClaudeUsageClient {
    static let defaultRetryAfter: TimeInterval = 5 * 60

    private let credentials: ClaudeCredentialsSource
    private let ownSignIn: ClaudeOwnSignIn
    private let webClient: any ClaudeUsageWebClient
    private var promptAllowedOnNextRead = false
    private var rateLimitedUntil: Date?

    init(credentials: ClaudeCredentialsSource, ownSignIn: ClaudeOwnSignIn, webClient: any ClaudeUsageWebClient) {
        self.credentials = credentials
        self.ownSignIn = ownSignIn
        self.webClient = webClient
    }

    /// Lets the next read show the Keychain prompt. Call it only from a user action.
    func allowKeychainPromptOnNextRead() {
        promptAllowedOnNextRead = true
    }

    /// Saves a new browser sign-in with its plan and email from Anthropic's profile, when that answers. Returns false
    /// when the Keychain refused it: it then lasts until rusage quits.
    func store(_ signIn: ClaudeSignIn) async -> Bool {
        rateLimitedUntil = nil
        var signIn = signIn
        let profile = await webClient.profile(using: signIn.accessToken)
        signIn.planName = profile?.planName
        signIn.email = signIn.email ?? profile?.email
        return await ownSignIn.store(signIn)
    }

    /// Deletes and revokes rusage's own sign-in. Claude Code's sign-in is untouched.
    func signOut() async -> Bool {
        rateLimitedUntil = nil
        return await ownSignIn.signOut()
    }

    func refresh(now: Date, using source: ClaudeSignInSource) async -> ClaudeUsageStatus {
        let allowingPrompt = promptAllowedOnNextRead
        promptAllowedOnNextRead = false
        if let rateLimitedUntil, now < rateLimitedUntil {
            return .rateLimited
        }
        return switch source {
        case .claudeCode: await claudeCodeUsage(now: now, allowingPrompt: allowingPrompt)
        case .rusage: await ownUsage(now: now, allowingPrompt: allowingPrompt)
        }
    }

    private func claudeCodeUsage(now: Date, allowingPrompt: Bool) async -> ClaudeUsageStatus {
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

        let response = await usage(using: signIn.accessToken)
        return status(of: response, now: now, unauthorized: .signInExpired, planName: signIn.planName, email: signIn.email)
    }

    /// A 401 gets exactly one renewal and one retry. A second 401 needs a new sign-in.
    private func ownUsage(now: Date, allowingPrompt: Bool) async -> ClaudeUsageStatus {
        do throws(ReadEnded) {
            var signIn = try Self.signIn(from: await ownSignIn.token(now: now, allowingPrompt: allowingPrompt))
            var response = await usage(using: signIn.accessToken)
            if case .failure(.unauthorized) = response {
                signIn = try Self.signIn(from: await ownSignIn.refreshAfterRejection(of: signIn.accessToken, now: now))
                response = await usage(using: signIn.accessToken)
            }
            return status(of: response, now: now, unauthorized: .signInRequired, planName: signIn.planName, email: signIn.email)
        } catch {
            return error.status
        }
    }

    private func usage(using token: ClaudeAccessToken) async -> Result<Data, ClaudeUsageWebError> {
        do throws(ClaudeUsageWebError) {
            return .success(try await webClient.usage(using: token))
        } catch {
            return .failure(error)
        }
    }

    private func status(
        of response: Result<Data, ClaudeUsageWebError>,
        now: Date,
        unauthorized: ClaudeUsageStatus,
        planName: String?,
        email: String?
    ) -> ClaudeUsageStatus {
        let data: Data
        switch response {
        case let .success(body):
            data = body
        case let .failure(error):
            UsageReadFailure(error).log(for: .claude)
            switch error {
            case .unauthorized: return unauthorized
            case .forbidden: return .forbidden
            case let .rateLimited(retryAfter):
                rateLimitedUntil = now.addingTimeInterval(retryAfter ?? Self.defaultRetryAfter)
                return .rateLimited
            case .httpStatus: return .serviceError
            case .transport: return .unreachable
            }
        }

        do {
            return .available(try ClaudeUsageAPI.parseUsage(data), planName: planName, email: email)
        } catch {
            UsageReadFailure.parse.log(for: .claude)
            return .unexpectedResponse
        }
    }

    /// The sign-in to read with. A renewal that failed for a reason other than `invalid_grant` is retried on a later
    /// read.
    private static func signIn(from ownToken: ClaudeOwnToken) throws(ReadEnded) -> ClaudeSignIn {
        switch ownToken {
        case let .token(signIn):
            return signIn
        case .signInRequired:
            throw ReadEnded(status: .signInRequired)
        case .keychainAccessNeeded:
            UsageReadFailure.keychainAccess.log(for: .claude)
            throw ReadEnded(status: .keychainAccessNeeded)
        case .unreadable:
            UsageReadFailure.parse.log(for: .claude)
            throw ReadEnded(status: .signInUnreadable)
        case .unavailable(.network), .unavailable(.busy), .unavailable(.saveFailed):
            throw ReadEnded(status: .unreachable)
        case .unavailable(.rejected):
            throw ReadEnded(status: .serviceError)
        case .unavailable(.malformed):
            throw ReadEnded(status: .unexpectedResponse)
        }
    }
}

/// Ends a read when rusage's own sign-in gives no token, with the status the read ends with.
private struct ReadEnded: Error {
    let status: ClaudeUsageStatus
}
