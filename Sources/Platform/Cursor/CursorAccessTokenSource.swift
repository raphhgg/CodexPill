import Foundation

protocol CursorAccessTokenSource: Sendable {
    func lookup() throws -> CursorAccessTokenLookup
}

enum CursorAccessTokenLookup: Sendable {
    case cursorNotInstalled
    case signedOut
    case token(CursorAccessToken)
}
