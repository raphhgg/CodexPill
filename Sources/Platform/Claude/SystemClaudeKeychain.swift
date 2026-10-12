import Foundation
import LocalAuthentication
import Security

/// Reads the `Claude Code-credentials` generic password. It never writes, updates, or deletes the item.
struct SystemClaudeKeychain: ClaudeKeychainReading {
    static let service = "Claude Code-credentials"

    let account: String

    init(account: String = NSUserName()) {
        self.account = account
    }

    func credentialsData(allowingPrompt: Bool) -> ClaudeKeychainRead {
        if !allowingPrompt {
            // Attributes need no decryption, so this probe tells "no item" apart from "not allowed" without UI.
            switch copyMatching(returning: kSecReturnAttributes, allowingPrompt: false).status {
            case errSecSuccess: break
            case errSecItemNotFound: return .notFound
            case errSecInteractionNotAllowed: return .needsPermission
            default: return .failed
            }
        }

        let (status, result) = copyMatching(returning: kSecReturnData, allowingPrompt: allowingPrompt)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return .failed }
            return .found(data)
        case errSecItemNotFound:
            // With UI skipped, an item that needs approval reads as missing even though the probe found it.
            return allowingPrompt ? .notFound : .needsPermission
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return .needsPermission
        default:
            return .failed
        }
    }

    private func copyMatching(returning key: CFString, allowingPrompt: Bool) -> (status: OSStatus, result: AnyObject?) {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            key: true,
        ]
        if !allowingPrompt {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = context
            query[kSecUseAuthenticationUI] = kSecUseAuthenticationUISkip
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }
}
