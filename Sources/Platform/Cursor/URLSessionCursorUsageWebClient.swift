import Foundation

final class URLSessionCursorUsageWebClient: CursorUsageWebClient {
    private static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!

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
            retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After"),
            now: Date()
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
