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

    func makeAddAccountRequest(runningCLISessions: Int) -> MenuBarTextInputAlertRequest {
        MenuBarTextInputAlertRequest(
            messageText: "Add account",
            informativeText: addAccountInformativeText(runningCLISessions: runningCLISessions),
            fieldTitle: "Saved Account Name",
            placeholder: "Business 2",
            confirmTitle: "Continue",
            cancelTitle: "Cancel"
        )
    }

    func makeAddAccountSignInRequest(prompt: IsolatedCodexLoginPrompt) -> MenuBarAddAccountSignInAlertRequest {
        MenuBarAddAccountSignInAlertRequest(
            messageText: "Sign in to Codex",
            informativeText: "CodexPill opened the Codex sign-in page in your browser.\n\nEnter this code when prompted:",
            userCode: prompt.userCode,
            promptURL: prompt.url,
            waitingStatusText: "Waiting for browser sign-in...",
            copiedStatusText: "Code copied. Waiting for browser sign-in...",
            copyTitle: "Copy Code",
            cancelTitle: "Cancel"
        )
    }

    func makeAddAccountSuccessRequest(accountName: String) -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Account Added",
            informativeText: "\(accountName) was saved. Your current local Codex session was not changed.",
            confirmTitle: "Use on This Mac",
            cancelTitle: "OK"
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

    func makeAddHostRequest() -> MenuBarHostSetupAlertRequest {
        MenuBarHostSetupAlertRequest(
            messageText: "Add remote host",
            informativeText: "Enter the SSH destination for the host you want CodexPill to target, for example user@host.",
            fieldTitle: "SSH Destination",
            placeholder: "user@host",
            nameFieldTitle: "Host Name (Optional)",
            namePlaceholder: "buildbox",
            confirmTitle: "Add Host",
            cancelTitle: "Cancel",
            idleStatusText: "CodexPill checks the connection automatically.",
            successStatusText: "Connection successful."
        )
    }

    func makeRemoveHostRequest(hostName: String) -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Remove remote host?",
            informativeText: "This will remove the saved host configuration for \(hostName). Remote snapshots on that machine will not be deleted.",
            confirmTitle: "Remove Host",
            cancelTitle: "Cancel"
        )
    }

    func makeInstallCurrentAccountOnHostRequest(accountName: String, hostName: String) -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Install current account on \(hostName)?",
            informativeText: "CodexPill can install and switch \(accountName) on \(hostName) now, so the host is ready immediately. If you cancel, the host will not be added yet.",
            confirmTitle: "Install and Switch",
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

    func makeNotificationActionRequest(
        accountName: String,
        targetDescription: String,
        substitutionMessage: String?,
        runningCLISessions: Int?
    ) -> MenuBarConfirmationAlertRequest {
        var lines: [String] = []
        if let substitutionMessage {
            lines.append(substitutionMessage)
            lines.append("")
        }

        lines.append("CodexPill will switch \(targetDescription) to \(accountName).")

        if let runningCLISessions, runningCLISessions > 0 {
            let sessionText = runningCLISessions == 1
                ? "1 running Codex CLI session was"
                : "\(runningCLISessions) running Codex CLI sessions were"
            lines.append("")
            lines.append("\(sessionText) detected. Restart any open Codex CLI terminals to use the new account.")
        }

        return MenuBarConfirmationAlertRequest(
            messageText: "Use \(accountName) now?",
            informativeText: lines.joined(separator: "\n"),
            confirmTitle: "Switch",
            cancelTitle: "Cancel"
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

    private func addAccountInformativeText(runningCLISessions: Int) -> String {
        var lines = [
            "CodexPill will open a browser sign-in and save the account without switching your current local Codex session."
        ]

        if runningCLISessions > 0 {
            let sessionText = runningCLISessions == 1 ? "1 running Codex CLI session was" : "\(runningCLISessions) running Codex CLI sessions were"
            lines.append("\(sessionText) detected. They will keep using the current account unless you switch later.")
        }

        return lines.joined(separator: " ")
    }
}
