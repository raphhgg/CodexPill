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
            messageText: "Add another account?",
            informativeText: signInAnotherInformativeText(runningCLISessions: runningCLISessions),
            fieldTitle: "Saved Account Name",
            placeholder: "Business 2",
            confirmTitle: "Add Account",
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
            informativeText: "CodexPill can install and switch \(accountName) on \(hostName) now, so the host is ready immediately.",
            confirmTitle: "Install and Switch",
            cancelTitle: "Later"
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

    func makeAddAccountDeviceAuthRequest(prompt: CodexDeviceAuthPrompt) -> MenuBarInfoAlertRequest {
        let codeText: String
        if let userCode = prompt.userCode {
            codeText = "Enter this code in the browser if prompted:\n\(userCode)\n\n"
        } else {
            codeText = ""
        }

        return MenuBarInfoAlertRequest(
            messageText: "Finish adding account",
            informativeText: """
            CodexPill opened the Codex device-auth page in your browser.

            \(codeText)When the browser sign-in completes, CodexPill will save the account to your collection without switching your current local session.
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
            "This signs into another Codex account in an isolated capture session so CodexPill can save it in your account collection without switching your current local session."
        ]

        if runningCLISessions > 0 {
            let sessionText = runningCLISessions == 1 ? "1 running Codex CLI session was" : "\(runningCLISessions) running Codex CLI sessions were"
            lines.append("\(sessionText) detected. Existing Codex CLI terminals stay on their current auth unless you switch them explicitly.")
        }

        return lines.joined(separator: " ")
    }
}
