import Foundation

/// Reads Cursor's sign-in and fetches its usage, once per call. `ProviderUsageRuntime` keeps the last good snapshot.
actor CursorUsageClient {
    private let tokenSource: any CursorAccessTokenSource
    private let webClient: any CursorUsageWebClient
    private let now: @Sendable () -> Date

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
        let lookup: CursorAccessTokenLookup
        do {
            lookup = try tokenSource.lookup()
        } catch {
            return .unavailable(.localStateUnreadable)
        }

        let token: CursorAccessToken
        switch lookup {
        case .cursorNotInstalled:
            return .cursorNotInstalled
        case .signedOut:
            return .signedOut
        case .token(let foundToken):
            token = foundToken
        }

        guard token.isUsable(at: now()) else {
            return .tokenExpired
        }

        let data: Data
        do {
            data = try await webClient.usageSummary(using: token)
        } catch CursorUsageWebError.unauthorized {
            return .unauthorized
        } catch {
            return .unavailable(.network)
        }

        do {
            return .available(try CursorUsageSummaryParser.parse(data, fetchedAt: now()))
        } catch {
            return .unavailable(.unexpectedResponse)
        }
    }
}
