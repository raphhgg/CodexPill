import Foundation

final class URLSessionCursorUsageWebClient: CursorUsageWebClient {
    private static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    private static let usageEventsURL = URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(
            configuration: configuration,
            delegate: RedirectRefusingDelegate(),
            delegateQueue: nil
        )
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    func usageSummary(using token: CursorAccessToken) async throws -> Data {
        var request = URLRequest(url: Self.usageSummaryURL, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token.cookieHeaderValue, forHTTPHeaderField: "Cookie")
        return try await send(request)
    }

    func usageEvents(using token: CursorAccessToken, from start: Date, to end: Date, page: Int, pageSize: Int) async throws -> Data {
        var request = URLRequest(url: Self.usageEventsURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The dashboard API rejects POSTs without its own origin.
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue(token.cookieHeaderValue, forHTTPHeaderField: "Cookie")
        // Cursor expects Unix milliseconds as strings.
        let body: [String: Any] = [
            "startDate": String(Int64(max(start.timeIntervalSince1970, 0) * 1000)),
            "endDate": String(Int64(end.timeIntervalSince1970 * 1000)),
            "page": page,
            "pageSize": pageSize
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CursorUsageWebError.transport
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorUsageWebError.transport
        }

        if let error = CursorUsageWebError.error(
            forStatus: httpResponse.statusCode,
            retryAfter: RetryAfter.delay(httpResponse.value(forHTTPHeaderField: "Retry-After"), now: Date())
        ) {
            throw error
        }
        return data
    }
}

// The session cookie must never follow a redirect to another host, so 3xx responses surface as-is.
private final class RedirectRefusingDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
