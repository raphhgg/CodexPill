import Foundation
import Security

/// CodexPill's saved Claude Code accounts: one `CodexPill Claude Code account` generic password per account in the
/// login Keychain, with the account's id as the Keychain account. CodexPill creates these items, so reading them
/// needs no prompt.
struct SystemClaudeCodeAccountItems: ClaudeCodeAccountItemStoring {
    static let service = "CodexPill Claude Code account"

    func read(_ id: UUID) -> Data? {
        var query = Self.itemQuery(for: id)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
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

    func delete(_ id: UUID) {
        SecItemDelete(Self.itemQuery(for: id) as CFDictionary)
    }

    private static func itemQuery(for id: UUID) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id.uuidString,
        ]
    }
}
