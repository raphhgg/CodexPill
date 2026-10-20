import Foundation
import LocalAuthentication
import Security

/// rusage's own Claude sign-in, from "Sign in with Claude". It is kept in rusage's own Keychain item, never in Claude
/// Code's.
struct ClaudeSignIn: Sendable, Equatable {
    /// Refresh this long before the access token expires, so a read never sends an expired token.
    static let refreshMargin: TimeInterval = 5 * 60

    let accessToken: ClaudeAccessToken
    let refreshToken: ClaudeRefreshToken
    let expiresAt: Date
    var email: String? = nil
    /// The plan with its usage multiplier, such as `max_20x`, in the format `ClaudeCredentials.planName` uses.
    var planName: String? = nil

    func needsRefresh(at now: Date) -> Bool {
        now >= expiresAt.addingTimeInterval(-Self.refreshMargin)
    }

    func isExpired(at now: Date) -> Bool {
        now >= expiresAt
    }
}

enum ClaudeSignInRead: Sendable, Equatable {
    case notFound
    /// The item exists but macOS needs the user to allow rusage to read it.
    case needsPermission
    case failed
    /// `refreshPending` means a refresh started with this refresh token and its result was never saved, so the token
    /// is presumed spent and must never be sent again.
    case found(ClaudeSignIn, refreshPending: Bool)
}

/// Where rusage keeps its own sign-in. Claude Code's item is never written.
protocol ClaudeSignInStoring: Sendable {
    /// `allowingPrompt` is true only right after a user action, so background reads never show a Keychain prompt.
    func read(allowingPrompt: Bool) -> ClaudeSignInRead
    /// One write holds both tokens and the marker, so a rotation and its marker change together.
    func save(_ signIn: ClaudeSignIn, refreshPending: Bool, allowingPrompt: Bool) -> Bool
    /// True when no item is left.
    func delete() -> Bool
}

/// The stored item's JSON, shared by the Keychain item and the file store.
enum ClaudeSignInRecord {
    static func data(for signIn: ClaudeSignIn, refreshPending: Bool) -> Data? {
        try? JSONEncoder().encode(Stored(
            accessToken: signIn.accessToken.exposedValue,
            refreshToken: signIn.refreshToken.exposedValue,
            expiresAt: signIn.expiresAt.timeIntervalSince1970,
            email: signIn.email,
            planName: signIn.planName,
            refreshPending: refreshPending
        ))
    }

    static func read(_ data: Data) -> ClaudeSignInRead {
        guard
            let item = try? JSONDecoder().decode(Stored.self, from: data),
            let accessToken = ClaudeAccessToken(item.accessToken),
            let refreshToken = ClaudeRefreshToken(item.refreshToken)
        else {
            return .failed
        }
        let signIn = ClaudeSignIn(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: item.expiresAt),
            email: item.email,
            planName: item.planName
        )
        return .found(signIn, refreshPending: item.refreshPending)
    }

    private struct Stored: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: TimeInterval
        let email: String?
        let planName: String?
        let refreshPending: Bool
    }
}

/// The `rusage Claude sign-in` generic password in the login Keychain. rusage creates it, so rusage is on its access
/// list and reads it without a prompt.
struct SystemClaudeSignInKeychain: ClaudeSignInStoring {
    static let service = "rusage Claude sign-in"
    static let account = "Claude"

    func read(allowingPrompt: Bool) -> ClaudeSignInRead {
        var query = Self.itemQuery(allowingPrompt: allowingPrompt)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            return (result as? Data).map(ClaudeSignInRecord.read) ?? .failed
        case errSecItemNotFound:
            return .notFound
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return .needsPermission
        default:
            return .failed
        }
    }

    func save(_ signIn: ClaudeSignIn, refreshPending: Bool, allowingPrompt: Bool) -> Bool {
        guard let data = ClaudeSignInRecord.data(for: signIn, refreshPending: refreshPending) else { return false }
        let status = SecItemUpdate(Self.itemQuery(allowingPrompt: allowingPrompt) as CFDictionary, [kSecValueData: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }

        var item = Self.itemQuery(allowingPrompt: true)
        item[kSecValueData] = data
        item[kSecAttrLabel] = Self.service
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete() -> Bool {
        let status = SecItemDelete(Self.itemQuery(allowingPrompt: true) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func itemQuery(allowingPrompt: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if !allowingPrompt {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = context
        }
        return query
    }
}

/// rusage's own sign-in as a 0600 JSON file. Isolated runs use it in place of the Keychain, and tests share one file
/// between clients the way two rusage processes share the Keychain item.
struct FileClaudeSignInStore: ClaudeSignInStoring {
    let fileURL: URL

    func read(allowingPrompt _: Bool) -> ClaudeSignInRead {
        do {
            return ClaudeSignInRecord.read(try Data(contentsOf: fileURL))
        } catch CocoaError.fileReadNoSuchFile {
            return .notFound
        } catch {
            return .failed
        }
    }

    /// Writes a 0600 temp file, then renames it over the item, so a reader sees the old item or the new one.
    func save(_ signIn: ClaudeSignIn, refreshPending: Bool, allowingPrompt _: Bool) -> Bool {
        guard let data = ClaudeSignInRecord.data(for: signIn, refreshPending: refreshPending) else { return false }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryURL = fileURL.deletingLastPathComponent().appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString)")
        guard fileManager.createFile(atPath: temporaryURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
        guard rename(temporaryURL.path, fileURL.path) == 0 else {
            try? fileManager.removeItem(at: temporaryURL)
            return false
        }
        return true
    }

    func delete() -> Bool {
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            return false
        }
    }
}
