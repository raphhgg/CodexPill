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
    case unexpectedResponse
}
