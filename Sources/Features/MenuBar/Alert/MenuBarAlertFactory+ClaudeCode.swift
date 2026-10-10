import AppKit

extension MenuBarAlertFactory {
    func makeConnectClaudeCodeRequest(change: ClaudeStatusLineChange) -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Connect Claude Code?",
            informativeText: "CodexPill will add a small script to Claude Code's status line to read your usage limits. You can disconnect in Preferences.",
            confirmTitle: "Connect",
            cancelTitle: "Cancel",
            detail: statusLineChangeText(change)
        )
    }

    func makeDisconnectClaudeCodeRequest(change: ClaudeStatusLineChange) -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Disconnect Claude Code?",
            informativeText: "CodexPill will restore your previous Claude Code status line.",
            confirmTitle: "Disconnect",
            cancelTitle: "Cancel",
            detail: statusLineChangeText(change)
        )
    }

    func makeClaudeCodeSettingsFailureRequest(_ error: ClaudeStatusLineInstallError) -> MenuBarInfoAlertRequest {
        let message = switch error {
        case .relayCopyFailed:
            "CodexPill could not copy its status line script, so nothing changed."
        case .settingsUnreadable:
            "CodexPill could not read Claude Code's settings, so nothing changed."
        case .invalidSettings:
            "CodexPill cannot safely edit Claude Code's settings, so nothing changed."
        case .backupFailed:
            "CodexPill could not back up Claude Code's settings, so nothing changed."
        case .settingsWriteFailed:
            "CodexPill could not save Claude Code's settings, so check its status line."
        case .settingsChanged:
            "Claude Code's settings changed while this window was open, so nothing was saved."
        }
        return MenuBarInfoAlertRequest(
            messageText: "Could Not Update Claude Code",
            informativeText: message,
            style: .warning,
            buttonTitle: "OK"
        )
    }

    private func statusLineChangeText(_ change: ClaudeStatusLineChange) -> String {
        """
        \((change.settingsPath as NSString).abbreviatingWithTildeInPath)

        Before:
        \(change.before ?? "No status line")

        After:
        \(change.after ?? "No status line")
        """
    }
}
