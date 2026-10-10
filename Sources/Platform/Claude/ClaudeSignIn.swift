import Foundation
import LocalAuthentication
import Security

/// CodexPill's own Claude sign-in, kept in CodexPill's Keychain item. It is never written to a file.
struct ClaudeSignIn: Sendable, Equatable {
    /// Refresh this long before the access token expires, so a read never sends an expired token.
    static let refreshMargin: TimeInterval = 5 * 60

    let accessToken: ClaudeAccessToken
    let refreshToken: ClaudeRefreshToken
    let expiresAt: Date

    func needsRefresh(at now: Date) -> Bool {
        now >= expiresAt.addingTimeInterval(-Self.refreshMargin)
    }

    func isExpired(at now: Date) -> Bool {
        now >= expiresAt
    }

    /// The Keychain item's data. Access and refresh token are one item, so a rotation is saved in one write.
    var keychainData: Data {
        let item = StoredSignIn(
            accessToken: accessToken.exposedValue,
            refreshToken: refreshToken.exposedValue,
            expiresAt: expiresAt.timeIntervalSince1970
        )
        return (try? JSONEncoder().encode(item)) ?? Data()
    }

    init(accessToken: ClaudeAccessToken, refreshToken: ClaudeRefreshToken, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    init?(keychainData: Data) {
        guard
            let item = try? JSONDecoder().decode(StoredSignIn.self, from: keychainData),
            let accessToken = ClaudeAccessToken(item.accessToken),
            let refreshToken = ClaudeRefreshToken(item.refreshToken)
        else {
            return nil
        }
        self.init(accessToken: accessToken, refreshToken: refreshToken, expiresAt: Date(timeIntervalSince1970: item.expiresAt))
    }
}

private struct StoredSignIn: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
}

/// CodexPill's own sign-in item. Claude Code's item is never written.
protocol ClaudeSignInStoring: Sendable {
    /// `allowingPrompt` is true only right after a user action, so background reads never show a Keychain prompt.
    func read(allowingPrompt: Bool) -> ClaudeKeychainRead
    @discardableResult
    func save(_ signIn: ClaudeSignIn, allowingPrompt: Bool) -> Bool
    func delete()
}

/// The `CodexPill Claude sign-in` generic password in the login Keychain.
struct SystemClaudeSignInKeychain: ClaudeSignInStoring {
    static let service = "CodexPill Claude sign-in"
    static let account = "Claude"

    private let reader = SystemClaudeKeychain(service: Self.service, account: Self.account)

    func read(allowingPrompt: Bool) -> ClaudeKeychainRead {
        reader.credentialsData(allowingPrompt: allowingPrompt)
    }

    func save(_ signIn: ClaudeSignIn, allowingPrompt: Bool) -> Bool {
        var query = Self.itemQuery
        if !allowingPrompt {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = context
        }
        let data = signIn.keychainData
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }

        var item = Self.itemQuery
        item[kSecValueData] = data
        item[kSecAttrLabel] = Self.service
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(Self.itemQuery as CFDictionary)
    }

    private static var itemQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}
