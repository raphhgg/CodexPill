import AppKit

struct MenuBarAlertFactory {
    func makeSaveCurrentAccountRequest(activeAccountEmail: String?) -> MenuBarTextInputAlertRequest {
        MenuBarTextInputAlertRequest(
            messageText: "Save current account",
            informativeText: "Choose a label for this saved account. Use distinct names if multiple accounts share the same email.",
            fieldTitle: "Account Name",
            placeholder: activeAccountEmail ?? "Personal 1",
            confirmTitle: "Save",
            cancelTitle: "Cancel"
        )
    }

    func makeSignInAnotherRequest(runningCLISessions: Int) -> MenuBarTextInputAlertRequest {
        MenuBarTextInputAlertRequest(
            messageText: "Sign in another account?",
            informativeText: signInAnotherInformativeText(runningCLISessions: runningCLISessions),
            fieldTitle: "Saved Account Name",
            placeholder: "Business 2",
            confirmTitle: "Continue",
            cancelTitle: "Cancel"
        )
    }

    func makeSwitchAccountRequest(accountName: String, runningCLISessions: Int) -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Switch account?",
            informativeText: switchInformativeText(for: accountName, runningCLISessions: runningCLISessions),
            confirmTitle: "Switch",
            cancelTitle: "Cancel"
        )
    }

    func makeRemoveAccountRequest(accountName: String, isCurrent: Bool) -> MenuBarConfirmationAlertRequest {
        let suffix = isCurrent ? " The live Codex session will remain logged in, but it will no longer match a saved account." : ""
        return MenuBarConfirmationAlertRequest(
            messageText: "Remove saved account?",
            informativeText: "This will remove the saved snapshot for \(accountName).\n\nThis action cannot be undone.\(suffix)",
            confirmTitle: "Remove",
            cancelTitle: "Cancel"
        )
    }

    func makeRenameAccountRequest(accountName: String) -> MenuBarTextInputAlertRequest {
        MenuBarTextInputAlertRequest(
            messageText: "Rename saved account",
            informativeText: "Update the label used in CodexPill for this saved account. This does not change the underlying Codex identity.",
            fieldTitle: "Account Name",
            placeholder: accountName,
            confirmTitle: "Rename",
            cancelTitle: "Cancel"
        )
    }

    func makeAboutRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "About CodexPill",
            informativeText: """
            CodexPill
            Version 0.1

            A macOS menubar utility to switch Codex accounts and monitor active account limits.

            Developed by Raphael Grau.
            """,
            style: .informational,
            buttonTitle: "OK"
        )
    }

    func makeErrorRequest(message: String) -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "CodexPill Error",
            informativeText: message,
            style: .warning,
            buttonTitle: "OK"
        )
    }

    private func switchInformativeText(for accountName: String, runningCLISessions: Int) -> String {
        var lines = [
            "This will switch the local Codex account to \(accountName) and restart Codex."
        ]

        if runningCLISessions > 0 {
            let sessionText = runningCLISessions == 1 ? "1 running Codex CLI session was" : "\(runningCLISessions) running Codex CLI sessions were"
            lines.append("\(sessionText) detected. Restart any open Codex CLI terminals to use the new account.")
        }

        return lines.joined(separator: " ")
    }

    private func signInAnotherInformativeText(runningCLISessions: Int) -> String {
        var lines = [
            "This will sign Codex out, restart the app, and let you log into another account. Save the current account first if you want to keep it."
        ]

        if runningCLISessions > 0 {
            let sessionText = runningCLISessions == 1 ? "1 running Codex CLI session was" : "\(runningCLISessions) running Codex CLI sessions were"
            lines.append("\(sessionText) detected. Restart any open Codex CLI terminals after signing in to use the new account.")
        }

        return lines.joined(separator: " ")
    }
}
