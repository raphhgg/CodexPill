import Foundation
import Security

/// Claude Code's `Claude Code-credentials` item, read and written through `security` as Claude Code does.
/// Refill writes it only when the user switches Claude accounts.
struct SystemClaudeKeychain: ClaudeCodeKeychainItem {
    static let service = "Claude Code-credentials"

    var keychain = ClaudeCodeSecurityKeychain()

    func credentialsData(allowingPrompt: Bool) -> ClaudeKeychainRead {
        keychain.read(service: Self.service, allowingPrompt: allowingPrompt)
    }

    /// Data too long for `security`'s stdin is written directly instead, which may show the Keychain prompt.
    /// Only a user's switch calls this.
    func updateCredentialsData(_ data: Data) -> Bool {
        if let written = keychain.write(data, service: Self.service) {
            return written
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: keychain.account,
        ]
        return SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecSuccess
    }
}
