import Foundation

extension MenuBarAlertFactory {
    func makeConnectClaudeCodeRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Sign in with Claude?",
            informativeText: "CodexPill will open your browser to sign in to Claude and show your 5-hour and weekly limits. Your sign-in stays in your Keychain.",
            confirmTitle: "Sign In",
            cancelTitle: "Cancel"
        )
    }
}
