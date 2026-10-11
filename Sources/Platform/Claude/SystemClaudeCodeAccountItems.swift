import Foundation
import Security

/// CodexPill's saved Claude Code accounts: one `CodexPill Claude Code account` generic password per account in the
/// login Keychain, with the account's id as the Keychain account. CodexPill creates these items, so reading them
/// needs no prompt.
struct SystemClaudeCodeAccountItems: ClaudeCodeAccountItemStoring {
    static let service = "CodexPill Claude Code account"

    func read(_ id: UUID) throws(ClaudeCodeAccountError) -> Data? {
        var query = Self.itemQuery(for: id)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data else { throw .savedAccountsUnreadable }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw .savedAccountsUnreadable
        }
    }

    func save(_ data: Data, for id: UUID) -> Bool {
        let query = Self.itemQuery(for: id)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }

        var item = query
        item[kSecValueData] = data
        item[kSecAttrLabel] = Self.service
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete(_ id: UUID) -> Bool {
        let status = SecItemDelete(Self.itemQuery(for: id) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func itemQuery(for id: UUID) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id.uuidString,
        ]
    }
}

/// Saved-account items as private files in an isolated run's folder, so an isolated run never writes the Keychain.
struct IsolatedClaudeCodeAccountItems: ClaudeCodeAccountItemStoring {
    let directory: URL

    func read(_ id: UUID) throws(ClaudeCodeAccountError) -> Data? {
        do {
            return try ClaudeCredentialsSource.contentsIfPresent(of: file(for: id))
        } catch {
            throw .savedAccountsUnreadable
        }
    }

    func save(_ data: Data, for id: UUID) -> Bool {
        do {
            try FilePermissionHardening.createPrivateDirectory(at: directory)
            try data.write(to: file(for: id), options: .atomic)
            try FilePermissionHardening.repairPrivateFile(at: file(for: id))
            return true
        } catch {
            return false
        }
    }

    func delete(_ id: UUID) -> Bool {
        do {
            try FileManager.default.removeItem(at: file(for: id))
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            return false
        }
    }

    private func file(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
