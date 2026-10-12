import Foundation

protocol CursorUsageWebClient: Sendable {
    func usageSummary(using token: CursorAccessToken) async throws -> Data
}

enum CursorUsageWebError: Error, Equatable {
    case unauthorized
    case forbidden
    /// HTTP 429. `retryAfter` is the wait cursor.com asked for, or nil when it named none.
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int)
    case transport

    /// Nil for 200. `retryAfter` is the raw `Retry-After` header: delay seconds or an HTTP date.
    static func error(forStatus statusCode: Int, retryAfter: String?, now: Date) -> CursorUsageWebError? {
        switch statusCode {
        case 200: nil
        case 401: .unauthorized
        case 403: .forbidden
        case 429: .rateLimited(retryAfter: retryAfter.flatMap { delay(fromRetryAfter: $0, now: now) })
        default: .httpStatus(statusCode)
        }
    }

    private static func delay(fromRetryAfter header: String, now: Date) -> TimeInterval? {
        let value = header.trimmingCharacters(in: .whitespaces)
        if let seconds = Int(value), seconds >= 0 {
            return TimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max($0.timeIntervalSince(now), 0) }
    }
}
