import Foundation
import Testing

@testable import CodexPill

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
    func transportErrorAfterSuccessKeepsLastGood() async throws {
        let client = makeClient(
            tokenSource: CursorAccessTokenSourceFixture(result: .token(usableToken())),
            webClient: CursorUsageWebClientHarness([
                .success(CursorUsageSummaryFixtures.proPlan),
                .failure(.transport),
            ])
        )

        _ = await client.refresh()

        #expect(await client.refresh() == .unavailable(.network, lastGood: try proSnapshot))
    }

    @Test
    func unauthorizedClearsLastGood() async throws {
        let client = makeClient(
            tokenSource: CursorAccessTokenSourceFixture(result: .token(usableToken())),
            webClient: CursorUsageWebClientHarness([
                .success(CursorUsageSummaryFixtures.proPlan),
                .failure(.unauthorized),
                .failure(.transport),
            ])
        )

        _ = await client.refresh()

        #expect(await client.refresh() == .unauthorized)
        #expect(await client.refresh() == .unavailable(.network, lastGood: nil))
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
    func signedOutClearsLastGood() async throws {
        let tokenSource = CursorAccessTokenSourceHarness([
            .token(usableToken()),
            .signedOut,
            .token(usableToken()),
        ])
        let client = makeClient(
            tokenSource: tokenSource,
            webClient: CursorUsageWebClientHarness([
                .success(CursorUsageSummaryFixtures.proPlan),
                .failure(.transport),
            ])
        )

        _ = await client.refresh()

        #expect(await client.refresh() == .signedOut)
        #expect(await client.refresh() == .unavailable(.network, lastGood: nil))
    }

    @Test
    func unreadableLocalStateIsUnavailable() async {
        let client = makeClient(
            tokenSource: CursorAccessTokenSourceErrorCase(),
            webClient: CursorUsageWebClientHarness([])
        )

        #expect(await client.refresh() == .unavailable(.localStateUnreadable, lastGood: nil))
    }

    @Test
    func garbageBodyIsUnexpectedResponse() async {
        let client = makeClient(
            tokenSource: CursorAccessTokenSourceFixture(result: .token(usableToken())),
            webClient: CursorUsageWebClientHarness([.success(Data("<html>".utf8))])
        )

        #expect(await client.refresh() == .unavailable(.unexpectedResponse, lastGood: nil))
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

private struct CursorAccessTokenSourceErrorCase: CursorAccessTokenSource {
    func lookup() throws -> CursorAccessTokenLookup {
        throw CursorStateDatabaseError.sqlite(code: 14)
    }
}

private final class CursorAccessTokenSourceHarness: CursorAccessTokenSource, @unchecked Sendable {
    private let lock = NSLock()
    private var lookups: [CursorAccessTokenLookup]

    init(_ lookups: [CursorAccessTokenLookup]) {
        self.lookups = lookups
    }

    func lookup() throws -> CursorAccessTokenLookup {
        lock.withLock { lookups.removeFirst() }
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

    func usageEvents(using _: CursorAccessToken, from _: Date, to _: Date, page _: Int, pageSize _: Int) async throws -> Data {
        Data("{}".utf8)
    }
}
