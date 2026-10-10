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
    /// Cursor is writing its database right now, so the sign-in can't be read until it finishes.
    case localStateBusy
    case network
    /// cursor.com knows the session but refuses to share usage with it (403).
    case forbidden
    /// cursor.com answered with a server error or another unexpected status.
    case serviceError
    /// cursor.com answered 429, or its `Retry-After` has not passed yet.
    case rateLimited
    case unexpectedResponse
}
