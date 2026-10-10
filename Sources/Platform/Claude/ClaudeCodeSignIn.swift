import Foundation

/// Claude Code's credentials item, writable. Only a user's account switch writes it, and only by updating an item
/// that already exists, so Claude Code keeps the item's access rules.
protocol ClaudeCodeKeychainItem: ClaudeKeychainReading {
    /// Replaces the data of the existing item. Returns false when there is no item or macOS refuses the change.
    func updateCredentialsData(_ data: Data) -> Bool
}

/// One Claude Code sign-in as Claude Code stores it: the `claudeAiOauth` object of its credentials item and the
/// `oauthAccount` object of its global config. Both stay opaque JSON, so fields CodexPill does not know survive a switch.
struct ClaudeCodeSignInSnapshot: RedactedClaudeSecret {
    /// `{"claudeAiOauth": …, "oauthAccount": …}`, the data of CodexPill's saved-account item.
    let itemData: Data

    init?(itemData: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: itemData) as? [String: Any],
            let oauth = object[Self.oauthKey] as? [String: Any],
            (oauth["accessToken"] as? String)?.isEmpty == false
        else {
            return nil
        }
        self.itemData = itemData
    }

    fileprivate init?(oauth: [String: Any], account: [String: Any]?) {
        var object: [String: Any] = [Self.oauthKey: oauth]
        object[Self.accountKey] = account
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        self.init(itemData: data)
    }

    fileprivate static let oauthKey = "claudeAiOauth"
    fileprivate static let accountKey = "oauthAccount"

    fileprivate var oauth: [String: Any] {
        object[Self.oauthKey] as? [String: Any] ?? [:]
    }

    fileprivate var account: [String: Any]? {
        object[Self.accountKey] as? [String: Any]
    }

    private var object: [String: Any] {
        (try? JSONSerialization.jsonObject(with: itemData) as? [String: Any]) ?? [:]
    }

    /// Claude's user and organization, from `oauthAccount`. Nil when Claude Code recorded no account.
    var identity: ClaudeCodeAccountIdentity? {
        account.flatMap(Self.identity(in:))
    }

    fileprivate static func identity(in account: [String: Any]) -> ClaudeCodeAccountIdentity? {
        guard let accountUUID = account["accountUuid"] as? String, !accountUUID.isEmpty else { return nil }
        return ClaudeCodeAccountIdentity(accountUUID: accountUUID, organizationUUID: account["organizationUuid"] as? String)
    }

    var subscriptionType: String? {
        (oauth["subscriptionType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    var email: String? {
        (account?["emailAddress"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    var organizationName: String? {
        (account?["organizationName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The same sign-in: the same Claude account and organization, or, when Claude Code recorded no account,
    /// the same refresh token.
    func isSameAccount(as other: Self) -> Bool {
        if let identity, let otherIdentity = other.identity {
            return identity == otherIdentity
        }
        guard let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty else { return false }
        return refreshToken == other.oauth["refreshToken"] as? String
    }
}

/// The Claude user and organization of a sign-in, from Claude Code's `oauthAccount`. One person can sign in to
/// a personal and a team organization, so both parts identify a saved account.
struct ClaudeCodeAccountIdentity: Codable, Equatable, Sendable {
    let accountUUID: String
    let organizationUUID: String?
}

enum ClaudeCodeSignInRead: Sendable {
    case signedOut
    case keychainAccessNeeded
    case unreadable
    case signedIn(ClaudeCodeSignInSnapshot, ClaudeCodeCredentialsItem)
}

/// Claude Code's whole credentials item as one read found it, so a switch writes back to the same place without
/// reading it, and maybe prompting, a second time.
struct ClaudeCodeCredentialsItem: RedactedClaudeSecret {
    fileprivate let data: Data
    fileprivate let isFile: Bool
}

/// Reads and replaces Claude Code's current sign-in. The credentials live in `.credentials.json` in Claude Code's
/// config folder or in its Keychain item, the same order `ClaudeCredentialsSource` reads them; the account record
/// lives in `oauthAccount` of Claude Code's global config. A replace writes where the sign-in was found and keeps
/// every other key, such as `mcpOAuth` and per-project settings.
struct ClaudeCodeSignInStore: Sendable {
    let configDirectory: URL
    let globalConfigFile: URL
    let keychain: any ClaudeCodeKeychainItem

    var credentialsFileURL: URL {
        configDirectory.appendingPathComponent(".credentials.json")
    }

    func current(allowingPrompt: Bool) -> ClaudeCodeSignInRead {
        let item: ClaudeCodeCredentialsItem
        if let data = try? Data(contentsOf: credentialsFileURL), Self.jsonObject(data)?[ClaudeCodeSignInSnapshot.oauthKey] != nil {
            item = ClaudeCodeCredentialsItem(data: data, isFile: true)
        } else {
            switch keychain.credentialsData(allowingPrompt: allowingPrompt) {
            case .notFound: return .signedOut
            case .needsPermission: return .keychainAccessNeeded
            case .failed: return .unreadable
            case let .found(data): item = ClaudeCodeCredentialsItem(data: data, isFile: false)
            }
        }
        guard
            let oauth = Self.jsonObject(item.data)?[ClaudeCodeSignInSnapshot.oauthKey] as? [String: Any],
            let snapshot = ClaudeCodeSignInSnapshot(oauth: oauth, account: currentAccount())
        else {
            return .signedOut
        }
        return .signedIn(snapshot, item)
    }

    /// Puts `snapshot` in place of the sign-in in `item`, keeping the item's other keys. When the global config
    /// cannot be written, the credentials go back to what they were.
    func replace(_ item: ClaudeCodeCredentialsItem, with snapshot: ClaudeCodeSignInSnapshot) throws(ClaudeCodeAccountError) {
        guard var credentials = Self.jsonObject(item.data) else { throw .writeFailed }
        credentials[ClaudeCodeSignInSnapshot.oauthKey] = snapshot.oauth
        guard let updated = try? JSONSerialization.data(withJSONObject: credentials) else { throw .writeFailed }

        try writeCredentials(updated, toFile: item.isFile)
        do {
            try writeAccount(snapshot.account)
        } catch {
            try? writeCredentials(item.data, toFile: item.isFile)
            throw error
        }
    }

    /// The account Claude Code's global config records, read without touching the Keychain.
    func currentIdentity() -> ClaudeCodeAccountIdentity? {
        currentAccount().flatMap(ClaudeCodeSignInSnapshot.identity(in:))
    }

    /// `<CLAUDE_CONFIG_DIR>/.claude.json` when set, otherwise `~/.claude.json`, matching Claude Code.
    static func globalConfigFile(environment: [String: String], homeDirectory: URL) -> URL {
        if let path = environment["CLAUDE_CONFIG_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent(".claude.json")
        }
        return homeDirectory.appendingPathComponent(".claude.json")
    }

    private func writeCredentials(_ data: Data, toFile: Bool) throws(ClaudeCodeAccountError) {
        if toFile {
            do {
                try data.write(to: credentialsFileURL, options: .atomic)
                try FilePermissionHardening.repairPrivateFile(at: credentialsFileURL)
            } catch {
                throw .writeFailed
            }
        } else if !keychain.updateCredentialsData(data) {
            throw .writeFailed
        }
    }

    private func currentAccount() -> [String: Any]? {
        guard let data = try? Data(contentsOf: globalConfigFile) else { return nil }
        return Self.jsonObject(data)?[ClaudeCodeSignInSnapshot.accountKey] as? [String: Any]
    }

    private func writeAccount(_ account: [String: Any]?) throws(ClaudeCodeAccountError) {
        var config: [String: Any] = [:]
        if let data = try? Data(contentsOf: globalConfigFile) {
            guard let object = Self.jsonObject(data) else { throw .writeFailed }
            config = object
        }
        config[ClaudeCodeSignInSnapshot.accountKey] = account
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .withoutEscapingSlashes])
            try data.write(to: globalConfigFile, options: .atomic)
            try FilePermissionHardening.repairPrivateFile(at: globalConfigFile)
        } catch {
            throw .writeFailed
        }
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
