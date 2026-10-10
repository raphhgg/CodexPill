import Foundation

extension MenuBarAlertFactory {
    func makeConnectClaudeCodeRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Connect Claude Code?",
            informativeText: "CodexPill will read Claude Code's sign-in from your Keychain to show your 5-hour and weekly limits. It never stores or shares it.",
            confirmTitle: "Connect",
            cancelTitle: "Cancel"
        )
    }
}
