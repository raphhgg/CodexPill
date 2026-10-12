import Foundation

/// Reads Claude Code's `Claude Code-credentials` item through `security`, as Claude Code does. It never writes,
/// updates, or deletes the item.
struct SystemClaudeKeychain: ClaudeKeychainReading {
    static let service = "Claude Code-credentials"

    var keychain = ClaudeCodeSecurityKeychain()

    func credentialsData(allowingPrompt: Bool) -> ClaudeKeychainRead {
        keychain.read(service: Self.service, allowingPrompt: allowingPrompt)
    }
}
