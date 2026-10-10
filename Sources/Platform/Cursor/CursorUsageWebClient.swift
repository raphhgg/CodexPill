import Foundation

protocol CursorUsageWebClient: Sendable {
    func usageSummary(using token: CursorAccessToken) async throws -> Data
    /// One page of the signed-in user's usage events between two instants, as the Cursor dashboard reads them.
    func usageEvents(using token: CursorAccessToken, from start: Date, to end: Date, page: Int, pageSize: Int) async throws -> Data
}

enum CursorUsageWebError: Error, Equatable {
    case unauthorized
    case forbidden
    /// HTTP 429. `retryAfter` is the wait cursor.com asked for, or nil when it named none.
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int)
    case transport

    /// Nil for 200. `retryAfter` is the parsed `Retry-After` wait, if any.
    static func error(forStatus statusCode: Int, retryAfter: TimeInterval?) -> CursorUsageWebError? {
        switch statusCode {
        case 200: nil
        case 401: .unauthorized
        case 403: .forbidden
        case 429: .rateLimited(retryAfter: retryAfter)
        default: .httpStatus(statusCode)
        }
    }
}
