import Foundation
import Testing

@testable import Refill

struct CursorTokenUsageClientTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var interval: DateInterval {
        DateInterval(start: day(2026, 10, 9), end: day(2026, 10, 11))
    }

    @Test
    func parsesStringAndNumberFieldsAndSumsAllTokenKinds() throws {
        let page = try #require(CursorUsageEventsParser.parse(Data(#"""
        {"totalUsageEventsCount":"2","usageEventsDisplay":[
          {"timestamp":"1791547200000","model":"claude-4.5-sonnet","kind":"USAGE_EVENT_KIND_INCLUDED_IN_PRO",
           "tokenUsage":{"inputTokens":"10","outputTokens":5,"cacheWriteTokens":100.0,"cacheReadTokens":"1000","totalCents":12.5}},
          {"timestamp":1791547300000,"kind":"USAGE_EVENT_KIND_ERRORED_NOT_CHARGED"}
        ]}
        """#.utf8)))

        #expect(page.totalCount == 2)
        #expect(page.pageEventCount == 2)
        #expect(page.events == [
            CursorUsageEvent(timestamp: Date(timeIntervalSince1970: 1_791_547_200), model: "claude-4.5-sonnet", tokens: 1115),
            CursorUsageEvent(timestamp: Date(timeIntervalSince1970: 1_791_547_300), model: "unknown", tokens: 0)
        ])
        #expect(CursorUsageEventsParser.parse(Data("{}".utf8))?.events == [])
        #expect(CursorUsageEventsParser.parse(Data("<html>".utf8)) == nil)
    }

    @Test
    func bucketsEventsByDayAndModelAcrossPages() async throws {
        let firstPage = (0..<CursorTokenUsageClient.pageSize).map { _ in event(at: "2026-10-09T12:00:00Z", model: "gpt-5", tokens: 2) }
        let web = CursorEventsWebClient(pages: [
            page(firstPage, total: CursorTokenUsageClient.pageSize + 1),
            page([event(at: "2026-10-10T12:00:00Z", model: "claude-4.5-sonnet", tokens: 7)], total: CursorTokenUsageClient.pageSize + 1)
        ])
        let client = makeClient(web: web)

        let days = try await client.dailyUsage(in: interval)

        #expect(days.map(\.day) == [day(2026, 10, 9), day(2026, 10, 10)])
        #expect(days[0].tokensByModel == ["gpt-5": 2 * CursorTokenUsageClient.pageSize])
        #expect(days[1].tokensByModel == ["claude-4.5-sonnet": 7])
        #expect(web.requestedPages == [1, 2])
    }

    @Test
    func reportsRejectedSessionAndUnexpectedResponses() async {
        let rejected = makeClient(web: CursorEventsWebClient(pages: [.failure(.unauthorized)]))
        let garbled = makeClient(web: CursorEventsWebClient(pages: [.success(Data("<html>".utf8))]))
        let signedOut = CursorTokenUsageClient(
            tokenSource: StaticCursorTokenSource(lookup: .signedOut),
            webClient: CursorEventsWebClient(pages: []),
            calendar: calendar
        )

        await #expect(throws: CursorTokenUsageError.unauthorized) { try await rejected.dailyUsage(in: interval) }
        await #expect(throws: CursorTokenUsageError.unexpectedResponse) { try await garbled.dailyUsage(in: interval) }
        await #expect(throws: CursorTokenUsageError.notSignedIn) { try await signedOut.dailyUsage(in: interval) }
    }

    private func makeClient(web: CursorEventsWebClient) -> CursorTokenUsageClient {
        CursorTokenUsageClient(
            tokenSource: StaticCursorTokenSource(lookup: .token(CursorAccessTokenFixtures.token(expiresAt: day(2026, 10, 12)))),
            webClient: web,
            calendar: calendar,
            now: { [day = day(2026, 10, 10)] in day }
        )
    }

    private func event(at time: String, model: String, tokens: Int) -> [String: Any] {
        let milliseconds = Int(ISO8601DateFormatter().date(from: time)!.timeIntervalSince1970 * 1000)
        return ["timestamp": String(milliseconds), "model": model, "tokenUsage": ["inputTokens": tokens]]
    }

    private func page(_ events: [[String: Any]], total: Int) -> Result<Data, CursorUsageWebError> {
        .success(try! JSONSerialization.data(withJSONObject: ["totalUsageEventsCount": total, "usageEventsDisplay": events]))
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private struct StaticCursorTokenSource: CursorAccessTokenSource {
    let result: CursorAccessTokenLookup

    init(lookup: CursorAccessTokenLookup) {
        result = lookup
    }

    func lookup() throws -> CursorAccessTokenLookup {
        result
    }
}

private final class CursorEventsWebClient: CursorUsageWebClient, @unchecked Sendable {
    private let lock = NSLock()
    private var pages: [Result<Data, CursorUsageWebError>]
    private var pagesRequested: [Int] = []

    init(pages: [Result<Data, CursorUsageWebError>]) {
        self.pages = pages
    }

    var requestedPages: [Int] {
        lock.withLock { pagesRequested }
    }

    func usageSummary(using _: CursorAccessToken) async throws -> Data {
        throw CursorUsageWebError.transport
    }

    func usageEvents(using _: CursorAccessToken, from _: Date, to _: Date, page: Int, pageSize _: Int) async throws -> Data {
        let response = lock.withLock {
            pagesRequested.append(page)
            return pages.isEmpty ? .success(Data("{}".utf8)) : pages.removeFirst()
        }
        return try response.get()
    }
}
