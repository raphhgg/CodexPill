import Foundation

/// Cursor's sign-in as it sits in `state.vscdb`: the `cursorAuth/*` rows that say who is signed in.
/// It holds tokens, so it prints as `CursorSignIn(redacted)` and lives only in CodexPill's Keychain item.
struct CursorSignIn: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    static let accessTokenKey = "cursorAuth/accessToken"
    static let refreshTokenKey = "cursorAuth/refreshToken"
    static let emailKey = "cursorAuth/cachedEmail"
    static let membershipTypeKey = "cursorAuth/stripeMembershipType"

    /// Every row a switch writes. A row the saved sign-in lacks is deleted, so nothing of the outgoing
    /// account is left behind for the incoming one.
    static let keys = [
        accessTokenKey,
        refreshTokenKey,
        emailKey,
        "cursorAuth/cachedScopedProfile",
        "cursorAuth/cachedSignUpType",
        "cursorAuth/stripeMembershipAuthId",
        membershipTypeKey,
        "cursorAuth/stripeSubscriptionStatus",
    ]

    let values: [String: CursorStateValue]
    /// Cursor's user ID from the access token's `sub` claim. Two sign-ins with the same ID are the same account.
    let userID: String

    /// Nil when the rows hold no valid access token, which means Cursor is signed out.
    init?(values: [String: CursorStateValue]) {
        guard
            let tokenValue = values[Self.accessTokenKey],
            let token = Self.accessToken(from: tokenValue)
        else {
            return nil
        }
        self.values = values.filter { Self.keys.contains($0.key) }
        self.userID = token.userID
    }

    var email: String? { text(Self.emailKey) }

    var accessToken: CursorAccessToken? {
        values[Self.accessTokenKey].flatMap(Self.accessToken(from:))
    }

    /// The plan Cursor cached at sign-in, for example `pro`.
    var membershipType: String? { text(Self.membershipTypeKey) }

    static func accessToken(from value: CursorStateValue) -> CursorAccessToken? {
        let jwt: String? = switch value {
        case .text(let text): text
        case .blob(let data): CursorStateDatabaseTokenSource.decodeTokenValue(data)
        }
        return jwt.flatMap(CursorAccessToken.init(jwt:))
    }

    private func text(_ key: String) -> String? {
        let raw: String? = switch values[key] {
        case .text(let text): text
        case .blob(let data): CursorStateDatabaseTokenSource.decodeTokenValue(data)
        case nil: nil
        }
        // Cursor stores some values JSON-encoded, with quotes.
        let trimmed = raw?.trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    var description: String { "CursorSignIn(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: EmptyCollection<Mirror.Child>()) }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let values = try container.decode([String: CursorStateValue].self)
        guard let signIn = Self(values: values) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Saved Cursor sign-in has no access token")
        }
        self = signIn
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}
