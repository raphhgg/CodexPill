import Foundation

protocol CursorUsageWebClient: Sendable {
    func usageSummary(using token: CursorAccessToken) async throws -> Data
}

enum CursorUsageWebError: Error, Equatable {
    case unauthorized
    case httpStatus(Int)
    case transport
}
