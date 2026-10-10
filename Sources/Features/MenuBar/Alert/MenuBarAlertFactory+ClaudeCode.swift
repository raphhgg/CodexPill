import Foundation

extension MenuBarAlertFactory {
    func makeConnectClaudeCodeRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Connect Claude Code?",
            informativeText: "Uses Claude Code's sign-in, or your browser if it has none.",
            confirmTitle: "Connect",
            cancelTitle: "Cancel"
        )
    }

    func makeClaudeSignInErrorRequest(_ error: ClaudeSignInError) -> MenuBarInfoAlertRequest {
        let (title, detail) = switch error {
        case .denied: ("Claude sign-in declined", "Sign in again to see your limits.")
        case .timedOut: ("Claude sign-in timed out", "Start it again from the menu.")
        case .stateMismatch, .token(.invalidGrant): ("Claude sign-in didn't finish", "Start it again from the menu.")
        case .listenerFailed: ("Couldn't start Claude sign-in", "Try again in a moment.")
        case .token(.transport): ("Can't reach Claude", "Check your connection and retry.")
        case .token(.rejected), .token(.malformedResponse): ("Claude sign-in failed", "Try again in a moment.")
        }
        return MenuBarInfoAlertRequest(messageText: title, informativeText: detail, style: .warning, buttonTitle: "OK")
    }

    func makeClaudeSignInNotSavedRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Claude sign-in not saved yet",
            informativeText: "CodexPill keeps trying while it runs.",
            style: .warning,
            buttonTitle: "OK"
        )
    }

    func makeClaudeSignInNotRemovedRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Claude sign-in not removed",
            informativeText: "Remove it in Keychain Access.",
            style: .warning,
            buttonTitle: "OK"
        )
    }

    func makeClaudeCodeAccountErrorRequest(_ error: ClaudeCodeAccountError) -> MenuBarInfoAlertRequest {
        let (title, detail) = switch error {
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
        return MenuBarInfoAlertRequest(messageText: title, informativeText: detail, style: .warning, buttonTitle: "OK")
    }
}
