import AppKit

extension MenuBarAlertFactory {
    func makeConnectClaudeCodeRequest(change: ClaudeStatusLineChange) -> MenuBarConfirmationAlertRequest {
        var paragraphs = [
            "CodexPill will change the status line in Claude Code's settings so it can show your Claude 5-hour and weekly limits.",
            "Claude Code will run a small CodexPill script each time it updates its status line. The script saves only your two usage percentages, their reset times, and when it saved them. Then it runs your current status line unchanged. CodexPill does not read Claude credentials or contact Anthropic.",
            statusLineChangeText(change)
        ]
        if change.before == nil {
            paragraphs.append("You have no status line today, so Claude Code will show an empty one. Claude Code hides some footer hints while any status line is set.")
        }
        paragraphs.append("If the file exists, CodexPill first saves a backup named settings.json.codexpill-backup. Usage appears after your next Claude Code message. Disconnect Claude Code restores your status line.")

        return MenuBarConfirmationAlertRequest(
            messageText: "Connect Claude Code?",
            informativeText: paragraphs.joined(separator: "\n\n"),
            confirmTitle: "Connect",
            cancelTitle: "Cancel"
        )
    }

    func makeDisconnectClaudeCodeRequest(change: ClaudeStatusLineChange) -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Disconnect Claude Code?",
            informativeText: [
                "CodexPill will restore your previous Claude Code status line and delete the Claude usage it saved.",
                statusLineChangeText(change)
            ].joined(separator: "\n\n"),
            confirmTitle: "Disconnect",
            cancelTitle: "Cancel"
        )
    }

    func makeClaudeCodeSettingsFailureRequest(_ error: ClaudeStatusLineInstallError) -> MenuBarInfoAlertRequest {
        let message = switch error {
        case .relayCopyFailed:
            "CodexPill could not copy its status line script. Claude Code's settings were not changed."
        case .settingsUnreadable:
            "CodexPill could not read Claude Code's settings.json. Nothing was changed."
        case .invalidSettings:
            "Claude Code's settings.json is not in a shape CodexPill can edit safely. Nothing was changed."
        case .backupFailed:
            "CodexPill could not back up Claude Code's settings.json. Nothing was changed."
        case .settingsWriteFailed:
            "CodexPill could not finish writing Claude Code's settings.json. Check its status line before you try again."
        case .settingsChanged:
            "Claude Code's settings.json changed while this window was open. Nothing was changed. Try again to review the new change."
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
