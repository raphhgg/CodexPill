import Foundation

/// A Cursor sign-in CodexPill saved so it can put it back later. Items from earlier builds also hold a `name`, which
/// decoding ignores.
struct CursorSavedAccount: Sendable, Equatable, Identifiable, Codable {
    let id: UUID
    var signIn: CursorSignIn
    /// The last limits read with this account's own sign-in while Cursor used another account.
    var usage: CursorUsageSnapshot? = nil

    var userID: String { signIn.userID }
    var email: String? { signIn.email }
    var plan: String? { signIn.membershipType }
}
