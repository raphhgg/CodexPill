import Foundation

protocol CursorUsageWebClient: Sendable {
    func usageSummary(using token: CursorAccessToken) async throws -> Data
    /// One page of the signed-in user's usage events between two instants, as the Cursor dashboard reads them.
    func usageEvents(using token: CursorAccessToken, from start: Date, to end: Date, page: Int, pageSize: Int) async throws -> Data
}

enum CursorUsageWebError: Error, Equatable {
    case unauthorized
    case httpStatus(Int)
    case transport
}
