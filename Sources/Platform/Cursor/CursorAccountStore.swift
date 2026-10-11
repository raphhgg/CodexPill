import Foundation
import Security

/// Where Refill keeps its saved Cursor accounts. Each account holds Cursor tokens, so the store is the
/// Keychain, never a file.
protocol CursorAccountStore: Sendable {
    func load() throws -> [CursorSavedAccount]
    func save(_ accounts: [CursorSavedAccount]) throws
}

enum CursorAccountStoreError: Error, Equatable {
    case keychain(status: OSStatus)
    case unreadable
}

/// The `CodexPill Cursor accounts` generic password in the login Keychain. All saved accounts are one item,
/// so capturing the outgoing account and the account list change together in one write.
struct SystemCursorAccountKeychain: CursorAccountStore {
    // Keeps the CodexPill name so accounts saved before the rename stay readable.
    static let service = "CodexPill Cursor accounts"
    static let account = "Cursor"

    func load() throws -> [CursorSavedAccount] {
        var query = Self.itemQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw CursorAccountStoreError.unreadable }
            return try Self.decode(data)
        case errSecItemNotFound:
            return []
        default:
            throw CursorAccountStoreError.keychain(status: status)
        }
    }

    func save(_ accounts: [CursorSavedAccount]) throws {
        guard !accounts.isEmpty else {
            let status = SecItemDelete(Self.itemQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CursorAccountStoreError.keychain(status: status)
            }
            return
        }

        let data = try Self.encode(accounts)
        let status = SecItemUpdate(Self.itemQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CursorAccountStoreError.keychain(status: status) }

        var item = Self.itemQuery
        item[kSecValueData] = data
        item[kSecAttrLabel] = Self.service
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CursorAccountStoreError.keychain(status: addStatus) }
    }

    static func encode(_ accounts: [CursorSavedAccount]) throws -> Data {
        try JSONEncoder().encode(StoredAccounts(version: 1, accounts: accounts))
    }

    static func decode(_ data: Data) throws -> [CursorSavedAccount] {
        guard let stored = try? JSONDecoder().decode(StoredAccounts.self, from: data) else {
            throw CursorAccountStoreError.unreadable
        }
        return stored.accounts
    }

    private static var itemQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}

/// Saved accounts as a private file inside an isolated run's root, which never uses the Keychain.
struct IsolatedCursorAccountFile: CursorAccountStore {
    let file: URL

    func load() throws -> [CursorSavedAccount] {
        guard let data = try ClaudeCredentialsSource.contentsIfPresent(of: file) else { return [] }
        return try SystemCursorAccountKeychain.decode(data)
    }

    func save(_ accounts: [CursorSavedAccount]) throws {
        try FilePermissionHardening.createPrivateDirectory(at: file.deletingLastPathComponent())
        try SystemCursorAccountKeychain.encode(accounts).write(to: file, options: .atomic)
        try FilePermissionHardening.repairPrivateFile(at: file)
    }
}

private struct StoredAccounts: Codable {
    let version: Int
    let accounts: [CursorSavedAccount]
}
