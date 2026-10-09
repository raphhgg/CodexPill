import Foundation

actor CursorUsageClient {
    private let tokenSource: any CursorAccessTokenSource
    private let webClient: any CursorUsageWebClient
    private let now: @Sendable () -> Date
    private var lastGood: CursorUsageSnapshot?

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
            return .unavailable(.localStateUnreadable, lastGood: lastGood)
        }

        let token: CursorAccessToken
        switch lookup {
        case .cursorNotInstalled:
            lastGood = nil
            return .cursorNotInstalled
        case .signedOut:
            lastGood = nil
            return .signedOut
        case .token(let foundToken):
            token = foundToken
        }

        // An expired token still belongs to the same account, so lastGood stays.
        guard token.isUsable(at: now()) else {
            return .tokenExpired
        }

        let data: Data
        do {
            data = try await webClient.usageSummary(using: token)
        } catch CursorUsageWebError.unauthorized {
            lastGood = nil
            return .unauthorized
        } catch {
            return .unavailable(.network, lastGood: lastGood)
        }

        do {
            let snapshot = try CursorUsageSummaryParser.parse(data, fetchedAt: now())
            lastGood = snapshot
            return .available(snapshot)
        } catch {
            return .unavailable(.unexpectedResponse, lastGood: lastGood)
        }
    }
}
