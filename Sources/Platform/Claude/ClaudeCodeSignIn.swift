import Foundation

/// Claude Code's credentials item, writable. Only a user's account switch writes it, and only by updating an item
/// that already exists, so Claude Code keeps the item's access rules.
protocol ClaudeCodeKeychainItem: ClaudeKeychainReading {
    /// Replaces the data of the existing item. Returns false when there is no item or macOS refuses the change.
    func updateCredentialsData(_ data: Data) -> Bool
}

/// One Claude Code sign-in as Claude Code stores it: the `claudeAiOauth` object of its credentials item and the
/// `oauthAccount` object of its global config. Both stay opaque JSON, so fields Refill does not know survive a switch.
struct ClaudeCodeSignInSnapshot: RedactedClaudeSecret {
    /// `{"claudeAiOauth": …, "oauthAccount": …}`, the data of Refill's saved-account item.
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

    /// The sign-in Claude Code saved in a config folder: its credentials item or `.credentials.json`, and the
    /// `.claude.json` in that folder. Nil when the credentials hold no Claude sign-in.
    init?(credentials: Data, globalConfig: Data?) {
        guard
            let credentialsObject = try? JSONSerialization.jsonObject(with: credentials) as? [String: Any],
            let oauth = credentialsObject[Self.oauthKey] as? [String: Any]
        else {
            return nil
        }
        let config = globalConfig.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        self.init(oauth: oauth, account: config?[Self.accountKey] as? [String: Any])
    }

    /// `.credentials.json` holding only this sign-in, for a throwaway Claude Code config folder.
    var credentialsFileData: Data {
        (try? JSONSerialization.data(withJSONObject: [Self.oauthKey: oauth], options: [.sortedKeys])) ?? Data()
    }

    /// `.claude.json` holding only this sign-in's account record, for a throwaway Claude Code config folder.
    var globalConfigData: Data {
        var config: [String: Any] = ["hasCompletedOnboarding": true]
        config[Self.accountKey] = account
        return (try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])) ?? Data()
    }

    /// True when both hold the same Claude Code credentials. A renewal changes them.
    func hasSameCredentials(as other: Self) -> Bool {
        NSDictionary(dictionary: oauth).isEqual(to: other.oauth)
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
    /// Nil in isolated runs, so they never touch the real Keychain item.
    let keychain: (any ClaudeCodeKeychainItem)?

    var credentialsFileURL: URL {
        configDirectory.appendingPathComponent(".credentials.json")
    }

    func current(allowingPrompt: Bool) -> ClaudeCodeSignInRead {
        do {
            let item: ClaudeCodeCredentialsItem
            if let data = try ClaudeCredentialsSource.contentsIfPresent(of: credentialsFileURL),
               try Self.jsonObject(data)[ClaudeCodeSignInSnapshot.oauthKey] != nil {
                item = ClaudeCodeCredentialsItem(data: data, isFile: true)
            } else {
                guard let keychain else { return .signedOut }
                switch keychain.credentialsData(allowingPrompt: allowingPrompt) {
                case .notFound: return .signedOut
                case .needsPermission: return .keychainAccessNeeded
                case .failed: return .unreadable
                case let .found(data): item = ClaudeCodeCredentialsItem(data: data, isFile: false)
                }
            }
            guard
                let oauth = try Self.jsonObject(item.data)[ClaudeCodeSignInSnapshot.oauthKey] as? [String: Any],
                let snapshot = ClaudeCodeSignInSnapshot(oauth: oauth, account: try currentAccount())
            else {
                return .signedOut
            }
            return .signedIn(snapshot, item)
        } catch {
            return .unreadable
        }
    }

    /// Puts `snapshot` in place of the sign-in in `item`, keeping the item's other keys. Both new contents are built
    /// before anything is written. When the global config can't be written, the credentials go back to `item`.
    func replace(_ item: ClaudeCodeCredentialsItem, with snapshot: ClaudeCodeSignInSnapshot) throws(ClaudeCodeAccountError) {
        let updatedCredentials: Data
        let updatedConfig: Data
        do {
            var credentials = try Self.jsonObject(item.data)
            credentials[ClaudeCodeSignInSnapshot.oauthKey] = snapshot.oauth
            updatedCredentials = try JSONSerialization.data(withJSONObject: credentials)

            var config = try ClaudeCredentialsSource.contentsIfPresent(of: globalConfigFile).map(Self.jsonObject) ?? [:]
            config[ClaudeCodeSignInSnapshot.accountKey] = snapshot.account
            updatedConfig = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .withoutEscapingSlashes])
        } catch {
            throw .unreadable
        }

        try writeCredentials(updatedCredentials, toFile: item.isFile)
        do {
            try updatedConfig.write(to: globalConfigFile, options: .atomic)
            try FilePermissionHardening.repairPrivateFile(at: globalConfigFile)
        } catch {
            do {
                try writeCredentials(item.data, toFile: item.isFile)
            } catch {
                throw .restoreFailed
            }
            throw .writeFailed
        }
    }

    /// The account Claude Code's global config records, read without touching the Keychain.
    func currentIdentity() throws(ClaudeCodeAccountError) -> ClaudeCodeAccountIdentity? {
        do {
            return try currentAccount().flatMap(ClaudeCodeSignInSnapshot.identity(in:))
        } catch {
            throw .unreadable
        }
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
        } else if keychain?.updateCredentialsData(data) != true {
            throw .writeFailed
        }
    }

    private func currentAccount() throws -> [String: Any]? {
        guard let data = try ClaudeCredentialsSource.contentsIfPresent(of: globalConfigFile) else { return nil }
        return try Self.jsonObject(data)[ClaudeCodeSignInSnapshot.accountKey] as? [String: Any]
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return object
    }
}
