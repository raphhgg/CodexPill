import Foundation

/// Reads Cursor's sign-in and fetches its usage, once per call. `ProviderUsageRuntime` keeps the last good snapshot.
actor CursorUsageClient {
    static let defaultRetryAfter: TimeInterval = 5 * 60

    private let tokenSource: any CursorAccessTokenSource
    private let webClient: any CursorUsageWebClient
    private let now: @Sendable () -> Date
    private var rateLimitedUntil: Date?

    init(
        tokenSource: any CursorAccessTokenSource,
        webClient: any CursorUsageWebClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.tokenSource = tokenSource
        self.webClient = webClient
        self.now = now
    }

    func refresh() async -> CursorUsageStatus {
        if let rateLimitedUntil, now() < rateLimitedUntil {
            return .unavailable(.rateLimited)
        }

        let lookup: CursorAccessTokenLookup
        do {
            lookup = try tokenSource.lookup()
        } catch CursorStateDatabaseError.busy {
            return .unavailable(.localStateBusy)
        } catch {
            return .unavailable(.localStateUnreadable)
        }

        let token: CursorAccessToken
        let email: String?
        switch lookup {
        case .cursorNotInstalled:
            return .cursorNotInstalled
        case .signedOut:
            return .signedOut
        case let .token(foundToken, foundEmail):
            token = foundToken
            email = foundEmail
        }

        guard token.isUsable(at: now()) else {
            return .tokenExpired
        }

        let data: Data
        do {
            data = try await webClient.usageSummary(using: token)
        } catch CursorUsageWebError.unauthorized {
            return .unauthorized
        } catch CursorUsageWebError.forbidden {
            return .unavailable(.forbidden)
        } catch let CursorUsageWebError.rateLimited(retryAfter) {
            rateLimitedUntil = now().addingTimeInterval(retryAfter ?? Self.defaultRetryAfter)
            return .unavailable(.rateLimited)
        } catch CursorUsageWebError.httpStatus {
            return .unavailable(.serviceError)
        } catch {
            return .unavailable(.network)
        }

        do {
            var snapshot = try CursorUsageSummaryParser.parse(data, fetchedAt: now())
            snapshot.accountEmail = email
            return .available(snapshot)
        } catch {
            return .unavailable(.unexpectedResponse)
        }
    }
}
