import Foundation
import Testing

@testable import Refill

struct CursorUsageClientTests {
    private let now = CursorAccessTokenFixtures.referenceDate

    private var proSnapshot: CursorUsageSnapshot {
        get throws {
            CursorUsageSnapshot(
                planName: "pro",
                includedUsagePercent: 82.29,
                onDemand: nil,
                billingCycle: DateInterval(
                    start: try Date("2026-09-30T15:23:08Z", strategy: .iso8601),
                    end: try Date("2026-10-30T15:23:08Z", strategy: .iso8601)
                ),
                fetchedAt: now
            )
        }
    }

    @Test
    func successfulFetchIsAvailable() async throws {
        let client = makeClient(
            tokenSource: CursorAccessTokenSourceFixture(result: .token(usableToken())),
            webClient: CursorUsageWebClientHarness([.success(CursorUsageSummaryFixtures.proPlan)])
        )

        #expect(await client.refresh() == .available(try proSnapshot))
    }

    @Test
    func transportErrorIsANetworkFailure() async {
        let client = makeClient(
            tokenSource: CursorAccessTokenSourceFixture(result: .token(usableToken())),
            webClient: CursorUsageWebClientHarness([.failure(.transport)])
        )

        #expect(await client.refresh() == .unavailable(.network))
    }

    @Test
    func rateLimitedReadsWaitForRetryAfterBeforeTouchingTheDatabaseOrTheNetwork() async {
        let clock = TestClock(now)
        let tokenSource = CountingTokenSource(result: .token(usableToken()))
        let webClient = CursorUsageWebClientHarness([
            .failure(.rateLimited(retryAfter: 120)),
            .success(CursorUsageSummaryFixtures.proPlan),
        ])
        let client = CursorUsageClient(tokenSource: tokenSource, webClient: webClient, now: { clock.now })

        #expect(await client.refresh() == .unavailable(.rateLimited))

        clock.now = now.addingTimeInterval(119)
        #expect(await client.refresh() == .unavailable(.rateLimited))
        #expect(tokenSource.lookupCount == 1)
        #expect(webClient.requestCount == 1)

        clock.now = now.addingTimeInterval(120)
        guard case .available = await client.refresh() else {
            Issue.record("Expected a read once Retry-After passed")
            return
        }
        #expect(webClient.requestCount == 2)
    }

    @Test
    func rateLimitWithoutRetryAfterWaitsFiveMinutes() async {
        let clock = TestClock(now)
        let webClient = CursorUsageWebClientHarness([.failure(.rateLimited(retryAfter: nil))])
        let client = CursorUsageClient(
            tokenSource: CursorAccessTokenSourceFixture(result: .token(usableToken())),
            webClient: webClient,
            now: { clock.now }
        )

        _ = await client.refresh()
        clock.now = now.addingTimeInterval(299)

        #expect(await client.refresh() == .unavailable(.rateLimited))
        #expect(webClient.requestCount == 1)
    }

    @Test
    func eachHTTPStatusHasItsOwnError() {
        #expect(CursorUsageWebError.error(forStatus: 200, retryAfter: nil) == nil)
        #expect(CursorUsageWebError.error(forStatus: 401, retryAfter: nil) == .unauthorized)
        #expect(CursorUsageWebError.error(forStatus: 403, retryAfter: nil) == .forbidden)
        #expect(CursorUsageWebError.error(forStatus: 429, retryAfter: 120) == .rateLimited(retryAfter: 120))
        #expect(CursorUsageWebError.error(forStatus: 500, retryAfter: nil) == .httpStatus(500))
    }

    @Test
    func expiredTokenIsNotFetched() async {
        let webClient = CursorUsageWebClientHarness([.success(CursorUsageSummaryFixtures.proPlan)])
        let client = makeClient(
            tokenSource: CursorAccessTokenSourceFixture(
                result: .token(CursorAccessTokenFixtures.token(expiresAt: now.addingTimeInterval(30)))
            ),
            webClient: webClient
        )

        #expect(await client.refresh() == .tokenExpired)
        #expect(webClient.requestCount == 0)
    }

    @Test
    func unreadableLocalStateIsUnavailable() async {
        let client = makeClient(
            tokenSource: CursorAccessTokenSourceErrorCase(),
            webClient: CursorUsageWebClientHarness([])
        )

        #expect(await client.refresh() == .unavailable(.localStateUnreadable))
    }

    @Test
    func garbageBodyIsUnexpectedResponse() async {
        let client = makeClient(
            tokenSource: CursorAccessTokenSourceFixture(result: .token(usableToken())),
            webClient: CursorUsageWebClientHarness([.success(Data("<html>".utf8))])
        )

        #expect(await client.refresh() == .unavailable(.unexpectedResponse))
    }

    private func makeClient(
        tokenSource: any CursorAccessTokenSource,
        webClient: any CursorUsageWebClient
    ) -> CursorUsageClient {
        let now = now
        return CursorUsageClient(tokenSource: tokenSource, webClient: webClient, now: { now })
    }

    private func usableToken() -> CursorAccessToken {
        CursorAccessTokenFixtures.token(expiresAt: now.addingTimeInterval(3600))
    }
}

private struct CursorAccessTokenSourceFixture: CursorAccessTokenSource {
    let result: CursorAccessTokenLookup

    func lookup() throws -> CursorAccessTokenLookup {
        result
    }
}

private final class CountingTokenSource: CursorAccessTokenSource, @unchecked Sendable {
    private let lock = NSLock()
    private let result: CursorAccessTokenLookup
    private var lookups = 0

    init(result: CursorAccessTokenLookup) {
        self.result = result
    }

    var lookupCount: Int {
        lock.withLock { lookups }
    }

    func lookup() throws -> CursorAccessTokenLookup {
        lock.withLock { lookups += 1 }
        return result
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

private struct CursorAccessTokenSourceErrorCase: CursorAccessTokenSource {
    func lookup() throws -> CursorAccessTokenLookup {
        throw CursorStateDatabaseError.sqlite(code: 14)
    }
}

private final class CursorUsageWebClientHarness: CursorUsageWebClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Result<Data, CursorUsageWebError>]
    private var requests = 0

    init(_ responses: [Result<Data, CursorUsageWebError>]) {
        self.responses = responses
    }

    var requestCount: Int {
        lock.withLock { requests }
    }

    func usageSummary(using token: CursorAccessToken) async throws -> Data {
        let response = lock.withLock {
            requests += 1
            return responses.removeFirst()
        }
        return try response.get()
    }
}
