import Foundation

extension MenuBarAlertFactory {
    func makeConnectClaudeCodeRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Connect Claude Code?",
            informativeText: "Uses Claude Code's sign-in to read your limits.",
            confirmTitle: "Connect",
            cancelTitle: "Cancel"
        )
    }

}
