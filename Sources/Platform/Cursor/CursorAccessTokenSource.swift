import Foundation

protocol CursorAccessTokenSource: Sendable {
    func lookup() throws -> CursorAccessTokenLookup
}

enum CursorAccessTokenLookup: Sendable {
    case cursorNotInstalled
    case signedOut
    /// `email` is the account email Cursor cached at sign-in, when it has one.
    case token(CursorAccessToken, email: String?)
}
