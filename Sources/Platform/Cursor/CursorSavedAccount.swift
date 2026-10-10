import Foundation

/// A Cursor sign-in CodexPill saved so it can put it back later.
struct CursorSavedAccount: Sendable, Equatable, Identifiable, Codable {
    let id: UUID
    var name: String
    var signIn: CursorSignIn

    var userID: String { signIn.userID }
    var email: String? { signIn.email }
    var plan: String? { signIn.membershipType }
}
