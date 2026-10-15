import Foundation

/// Every word the menu shows for one tool, in one table. In-app copy is a title plus at most one short line.
struct ProviderCopy: Sendable {
    let name: String
    /// The short tool name on its menu card and in its side menu, such as "Claude".
    let sectionTitle: String
    /// Who answers usage requests, for "Can't reach …" style messages.
    let serviceName: String
    let connectPrompt: ProviderPrompt?
    /// What the menu asks before Refill's own sign-in, for a tool that offers one.
    var signInPrompt: ProviderPrompt? = nil
    /// How to sign in after signing out. By default, signing in to the tool.
    var signInHint: String? = nil
    /// What renews an expired sign-in. By default, opening the tool.
    var renewHint: String? = nil

    /// What the menu asks before running `action`, or nil to run it right away.
    func prompt(for action: ProviderAction) -> ProviderPrompt? {
        switch action {
        case .connect: connectPrompt
        case .signIn: signInPrompt
        case .allowKeychainAccess, .disconnect, .switchAccount, .addAccount, .removeAccount, .useResetCredit, .signOut: nil
        }
    }

    func unavailableMessage(for reason: UsageUnavailableReason) -> (title: String, detail: String?) {
        let retrying = "Retrying in a few minutes."
        return switch reason {
        case .notInstalled: ("\(name) isn't installed", nil)
        case .signedOut: ("Not signed in to \(name)", signInHint ?? "Sign in to \(name) to see usage.")
        case .signInExpired: ("\(name) sign-in expired", renewHint ?? "Open \(name) to renew it.")
        case .signInRequired: ("Sign in to \(sectionTitle) again", nil)
        case .keychainAccessNeeded: ("Allow Keychain access", nil)
        case .signInUnreadable: ("Can't read the \(name) sign-in", "Sign in to \(name) again.")
        case .signInBusy: ("\(name) is busy", retrying)
        case .accessDenied: ("\(serviceName) won't share usage", "Sign in to \(name) again.")
        case .rateLimited: ("\(serviceName) asked to wait", retrying)
        case .unreachable: ("Can't reach \(serviceName)", retrying)
        case .serviceError: ("\(serviceName) is having trouble", retrying)
        case .unexpectedResponse: ("Unexpected reply from \(serviceName)", retrying)
        }
    }
}

extension UsageProvider {
    var copy: ProviderCopy {
        switch self {
        case .codex:
            ProviderCopy(name: "Codex", sectionTitle: "Codex", serviceName: "Codex", connectPrompt: nil)
        case .claude:
            ProviderCopy(
                name: "Claude Code",
                sectionTitle: "Claude",
                serviceName: "Anthropic",
                connectPrompt: ProviderPrompt(
                    title: "Connect Claude Code?",
                    detail: "Uses Claude Code's sign-in to read your limits.",
                    confirmTitle: "Connect"
                ),
                signInPrompt: ProviderPrompt(
                    title: "Sign in with Claude?",
                    detail: "Opens your browser. Refill keeps this sign-in in its own Keychain item.",
                    confirmTitle: "Sign In"
                ),
                signInHint: "Run claude, then /login.",
                renewHint: "Run claude, or sign in with Claude."
            )
        case .cursor:
            ProviderCopy(
                name: "Cursor",
                sectionTitle: "Cursor",
                serviceName: "Cursor",
                connectPrompt: ProviderPrompt(
                    title: "Connect Cursor?",
                    detail: "Uses Cursor's sign-in to read your usage.",
                    confirmTitle: "Connect"
                )
            )
        }
    }
}

extension ClaudeSignInError {
    var notice: ProviderNotice {
        let (title, detail) = switch self {
        case .denied: ("Claude sign-in declined", "Sign in again to see your limits.")
        case .timedOut: ("Claude sign-in timed out", "Start it again from the menu.")
        case .stateMismatch, .token(.invalidGrant): ("Claude sign-in didn't finish", "Start it again from the menu.")
        case .listenerFailed: ("Couldn't start Claude sign-in", "Try again in a moment.")
        case .token(.transport): ("Can't reach Claude", "Check your connection and retry.")
        case .token(.rejected), .token(.malformedResponse): ("Claude sign-in failed", "Try again in a moment.")
        }
        return ProviderNotice(title: title, detail: detail)
    }
}
