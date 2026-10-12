import Foundation

enum CursorTokenUsageError: Error, Equatable {
    case notSignedIn
    case unauthorized
    case network
    case unexpectedResponse
    /// More events than the page limit allows. The partial result is not shown, so totals never undercount silently.
    case tooManyEvents
}

/// Daily per-model token totals from the signed-in Cursor account's usage events.
///
/// The events come from the endpoint Cursor's own dashboard uses, which is not a documented public API.
/// Only the timestamp, model, and token counts of each event are read.
actor CursorTokenUsageClient {
    static let pageSize = 1000
    static let maximumPageCount = 20

    private let tokenSource: any CursorAccessTokenSource
    private let webClient: any CursorUsageWebClient
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        tokenSource: any CursorAccessTokenSource,
        webClient: any CursorUsageWebClient,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.tokenSource = tokenSource
        self.webClient = webClient
        self.calendar = calendar
        self.now = now
    }

    func dailyUsage(in interval: DateInterval) async throws(CursorTokenUsageError) -> [ToolDailyTokenUsage] {
        guard case .token(let token, _)? = try? tokenSource.lookup(), token.isUsable(at: now()) else {
            throw .notSignedIn
        }

        var events: [CursorUsageEvent] = []
        var expectedCount: Int?
        for page in 1...Self.maximumPageCount {
            let data: Data
            do {
                data = try await webClient.usageEvents(
                    using: token,
                    from: interval.start,
                    to: interval.end,
                    page: page,
                    pageSize: Self.pageSize
                )
            } catch CursorUsageWebError.unauthorized {
                throw .unauthorized
            } catch {
                throw .network
            }
            guard let parsed = CursorUsageEventsParser.parse(data) else {
                throw .unexpectedResponse
            }
            expectedCount = expectedCount ?? parsed.totalCount
            events += parsed.events
            if parsed.pageEventCount < Self.pageSize || events.count >= (expectedCount ?? .max) {
                let usage = events
                    .filter { interval.contains($0.timestamp) && $0.tokens > 0 }
                    .map { ToolDailyTokenUsage(day: $0.timestamp, tokensByModel: [$0.model: $0.tokens]) }
                return ToolTokenUsageDays.filled(usage, in: interval, calendar: calendar)
            }
        }
        throw .tooManyEvents
    }
}

struct CursorUsageEvent: Equatable, Sendable {
    var timestamp: Date
    var model: String
    var tokens: Int
}

struct CursorUsageEventsPage: Equatable, Sendable {
    var events: [CursorUsageEvent]
    /// Every event on the page, including ones without token counts, for pagination.
    var pageEventCount: Int
    var totalCount: Int?
}

/// Parses `get-filtered-usage-events`. Observed in Cursor 3.21 and CodexBar:
/// `{totalUsageEventsCount, usageEventsDisplay: [{timestamp, model, tokenUsage: {inputTokens, outputTokens,
/// cacheWriteTokens, cacheReadTokens}}]}`. Numbers may be strings, and `timestamp` is Unix milliseconds.
/// An empty object means no events.
enum CursorUsageEventsParser {
    static func parse(_ data: Data) -> CursorUsageEventsPage? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let rawEvents = object["usageEventsDisplay"] as? [[String: Any]] ?? []
        let events = rawEvents.compactMap { raw -> CursorUsageEvent? in
            guard let milliseconds = number(raw["timestamp"]) else { return nil }
            let usage = raw["tokenUsage"] as? [String: Any] ?? [:]
            let tokens = ["inputTokens", "outputTokens", "cacheWriteTokens", "cacheReadTokens"]
                .compactMap { number(usage[$0]) }
                .reduce(0, +)
            let model = (raw["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
            return CursorUsageEvent(
                timestamp: Date(timeIntervalSince1970: Double(milliseconds) / 1000),
                model: model,
                tokens: tokens
            )
        }
        return CursorUsageEventsPage(
            events: events,
            pageEventCount: rawEvents.count,
            totalCount: number(object["totalUsageEventsCount"])
        )
    }

    private static func number(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string) ?? Double(string).map { Int($0) }
        default:
            return nil
        }
    }
}
