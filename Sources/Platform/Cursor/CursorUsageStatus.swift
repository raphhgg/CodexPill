import Foundation

enum CursorUsageStatus: Equatable, Sendable {
    case cursorNotInstalled
    case signedOut
    case tokenExpired
    case unauthorized
    case available(CursorUsageSnapshot)
    case unavailable(CursorUsageFailure)
}

enum CursorUsageFailure: Equatable, Sendable {
    case localStateUnreadable
    case network
    /// cursor.com answered 429, or its `Retry-After` has not passed yet.
    case rateLimited
    case unexpectedResponse
}
