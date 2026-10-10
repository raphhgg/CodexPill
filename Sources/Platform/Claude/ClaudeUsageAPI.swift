import Foundation

/// Claude's 5-hour and 7-day subscription windows as Anthropic reports them.
struct ClaudeUsageReport: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let usedPercent: Double
        let resetsAt: Date?
    }

    let fiveHour: Window?
    let sevenDay: Window?
}

protocol ClaudeUsageWebClient: Sendable {
    func usage(using token: ClaudeAccessToken) async throws -> Data
}

enum ClaudeUsageWebError: Error, Equatable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int)
    case transport
}

/// The one Anthropic endpoint CodexPill calls, and the pure rules around it.
enum ClaudeUsageAPI {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func request(using token: ClaudeAccessToken) -> URLRequest {
        var request = URLRequest(url: usageURL, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        return request
    }

    /// The token may follow a redirect only to the same host over HTTPS.
    static func allowsRedirect(from original: URL?, to target: URL?) -> Bool {
        guard let original, let target, let host = original.host?.lowercased() else { return false }
        return target.scheme?.lowercased() == "https" && target.host?.lowercased() == host
    }

    static func error(forStatus statusCode: Int, retryAfter: String?) -> ClaudeUsageWebError? {
        switch statusCode {
        case 200: nil
        case 401: .unauthorized
        case 429: .rateLimited(retryAfter: retryAfter.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) })
        default: .httpStatus(statusCode)
        }
    }

    /// Reads `five_hour` and `seven_day`. Other windows, such as `seven_day_opus`, are ignored.
    static func parseUsage(_ data: Data) throws -> ClaudeUsageReport {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(UsageResponseDTO.self, from: data)
        return ClaudeUsageReport(fiveHour: window(response.fiveHour), sevenDay: window(response.sevenDay))
    }

    private static func window(_ dto: WindowDTO?) -> ClaudeUsageReport.Window? {
        guard let dto, let utilization = dto.utilization else { return nil }
        return ClaudeUsageReport.Window(
            usedPercent: min(max(utilization, 0), 100),
            resetsAt: dto.resetsAt.flatMap(date(from:))
        )
    }

    private static func date(from value: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }
}

private struct UsageResponseDTO: Decodable {
    let fiveHour: WindowDTO?
    let sevenDay: WindowDTO?
}

private struct WindowDTO: Decodable {
    let utilization: Double?
    let resetsAt: String?
}

final class URLSessionClaudeUsageWebClient: ClaudeUsageWebClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: SameHostRedirectDelegate(), delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    func usage(using token: ClaudeAccessToken) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: ClaudeUsageAPI.request(using: token))
        } catch {
            throw ClaudeUsageWebError.transport
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeUsageWebError.transport
        }
        if let error = ClaudeUsageAPI.error(
            forStatus: httpResponse.statusCode,
            retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After")
        ) {
            throw error
        }
        return data
    }
}

private final class SameHostRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        ClaudeUsageAPI.allowsRedirect(from: task.originalRequest?.url, to: request.url) ? request : nil
    }
}
