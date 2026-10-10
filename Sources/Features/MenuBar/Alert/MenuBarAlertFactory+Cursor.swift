import Foundation

extension MenuBarAlertFactory {
    func makeConnectCursorRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Connect Cursor?",
            informativeText: "Uses Cursor's sign-in to read your usage.",
            confirmTitle: "Connect",
            cancelTitle: "Cancel"
        )
    }

    func makeSwitchCursorAccountRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Switch Cursor account?",
            informativeText: "Cursor will quit and reopen.",
            confirmTitle: "Switch",
            cancelTitle: "Cancel"
        )
    }

    func makeCursorAccountErrorRequest(_ error: CursorAccountsError) -> MenuBarInfoAlertRequest {
        let (title, detail) = switch error {
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
        return MenuBarInfoAlertRequest(messageText: title, informativeText: detail, style: .warning, buttonTitle: "OK")
    }
}
