import Foundation

/// Every word the menu shows for one tool, in one table. In-app copy is a title plus at most one short line.
struct ProviderCopy: Sendable {
    let name: String
    /// The short tool name on its menu card and in its side menu, such as "Claude".
    let sectionTitle: String
    /// Who answers usage requests, for "Can't reach …" style messages.
    let serviceName: String
    let connectPrompt: ProviderPrompt?
    /// Nil when switching needs no warning.
    let switchPrompt: ProviderPrompt?
    /// What renews an expired sign-in. By default, opening the tool.
    var renewHint: String? = nil

    /// What the menu asks before running `action`, or nil to run it right away.
    func prompt(for action: ProviderAction) -> ProviderPrompt? {
        switch action {
        case .connect: connectPrompt
        case .switchAccount: switchPrompt
        case .removeAccount:
            ProviderPrompt(title: "Remove this \(name) account?", detail: "CodexPill forgets its saved sign-in.", confirmTitle: "Remove")
        case .allowKeychainAccess, .cancelSignIn, .disconnect, .addAccount, .saveCurrentAccount, .useResetCredit: nil
        }
    }

    func unavailableMessage(for reason: UsageUnavailableReason) -> (title: String, detail: String?) {
        let retrying = "Retrying in a few minutes."
        return switch reason {
        case .notInstalled: ("\(name) isn't installed", nil)
        case .signedOut: ("Not signed in to \(name)", "Sign in to \(name) to see usage.")
        case .signInExpired: ("\(name) sign-in expired", renewHint ?? "Open \(name) to renew it.")
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
            ProviderCopy(name: "Codex", sectionTitle: "Codex", serviceName: "Codex", connectPrompt: nil, switchPrompt: nil)
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
                switchPrompt: nil,
                renewHint: "Run claude to renew it."
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
                ),
                switchPrompt: ProviderPrompt(
                    title: "Switch Cursor account?",
                    detail: "Cursor will quit and reopen.",
                    confirmTitle: "Switch"
                )
            )
        }
    }
}

extension ClaudeCodeAccountError {
    var notice: ProviderNotice {
        let (title, detail) = switch self {
        case .unknownAccount: ("Account not found", "It may have been removed.")
        case .savedSignInMissing: ("Saved sign-in missing", "Save this account again.")
        case .savedAccountsUnreadable: ("Can't read saved accounts", "Try again in a moment.")
        case .claudeCodeSignedOut: ("Claude Code isn't signed in", "Run claude and sign in first.")
        case .claudeCodeAccountUnknown: ("Unknown Claude account", "Open Claude Code once, then retry.")
        case .currentSignInNotSaved: ("Save this account first", "Otherwise its sign-in is lost.")
        case .claudeCodeRunning: ("Quit Claude Code first", "Close every claude session.")
        case .keychainAccessNeeded: ("Allow Keychain access", "CodexPill needs it to switch.")
        case .unreadable: ("Can't read the Claude sign-in", "Sign in to Claude Code again.")
        case .writeFailed: ("Couldn't switch", "Nothing was changed.")
        case .restoreFailed: ("Couldn't undo the switch", "Sign in to Claude Code again.")
        case .switchingUnavailable: ("Switching unavailable", "This build can't switch accounts.")
        }
        return ProviderNotice(title: title, detail: detail)
    }
}

extension ClaudeCodeCommandError {
    var notice: ProviderNotice {
        let (title, detail): (String, String?) = switch self {
        case .notInstalled: ("Install Claude Code first", nil)
        case .launchFailed: ("Couldn't start Claude Code", "Try again in a moment.")
        case .cancelled, .signInFailed: ("Claude sign-in didn't finish", "Nothing was saved.")
        case .timedOut: ("Claude sign-in timed out", "Nothing was saved.")
        case .accountUnknown: ("Unknown Claude account", "Nothing was saved.")
        case .folderUnavailable: ("Couldn't prepare the sign-in", "Nothing was saved.")
        }
        return ProviderNotice(title: title, detail: detail)
    }
}

extension CursorAccountsError {
    var notice: ProviderNotice {
        let (title, detail) = switch self {
        case .cursorNotInstalled: ("Cursor isn't installed", "Install Cursor, then try again.")
        case .signedOut: ("Cursor isn't signed in", "Sign in to Cursor first.")
        case .accountNotFound: ("Account not found", "It may have been removed.")
        case .savedAccountsUnreadable: ("Can't read saved accounts", "Try again in a moment.")
        case .stateUnreadable: ("Can't read Cursor's sign-in", "Open Cursor, then try again.")
        case .cursorDidNotQuit: ("Cursor didn't quit", "Save your work, then try again.")
        case .cursorBusy: ("Cursor is still closing", "Wait a moment, then try again.")
        case .writeFailed: ("Couldn't switch", "Nothing was changed.")
        case .reopenFailed: ("Cursor didn't reopen", "Open Cursor yourself.")
        case .switchingUnavailable: ("Switching unavailable", "This build can't switch accounts.")
        }
        return ProviderNotice(title: title, detail: detail)
    }
}
