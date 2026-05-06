import AppKit

struct MenuBarAlertFactory {
    func makeAddAccountRequest(runningCLISessions: Int) -> MenuBarTextInputAlertRequest {
        MenuBarTextInputAlertRequest(
            messageText: "Add account",
            informativeText: addAccountInformativeText(runningCLISessions: runningCLISessions),
            fieldTitle: "Account Name",
            placeholder: "Business 2",
            confirmTitle: "Continue",
            cancelTitle: "Cancel"
        )
    }

    func makeAddAccountSignInRequest(prompt: IsolatedCodexLoginPrompt) -> MenuBarAddAccountSignInPanelRequest {
        MenuBarAddAccountSignInPanelRequest(
            messageText: "Sign in to Codex",
            informativeText: "Copy this code, then open the Codex sign-in page in your browser.",
            userCode: prompt.userCode,
            promptURL: prompt.url,
            waitingStatusText: "Waiting for browser sign-in...",
            copiedStatusText: "Code copied. Waiting for browser sign-in...",
            browserOpenedStatusText: "Browser opened. Waiting for sign-in...",
            copyTitle: "Copy Code",
            openBrowserTitle: "Open Browser",
            cancelTitle: "Cancel"
        )
    }

    func makeAddAccountSuccessRequest(accountName: String, runningCLISessions: Int) -> MenuBarConfirmationAlertRequest {
        let cliNotice: String
        if runningCLISessions == 1 {
            cliNotice = "\n\n1 Codex terminal is running. Restart it to use the new account."
        } else if runningCLISessions > 1 {
            cliNotice = "\n\n\(runningCLISessions) Codex terminals are running. Restart them to use the new account."
        } else {
            cliNotice = ""
        }

        return MenuBarConfirmationAlertRequest(
            messageText: "Account Added",
            informativeText: "\(accountName) was saved. This Mac was not changed.\(cliNotice)",
            confirmTitle: "Use on This Mac",
            cancelTitle: "Done"
        )
    }

    func makeAddAccountDuplicateNameRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Name Already Used",
            informativeText: "Choose a different name for this saved account.",
            confirmTitle: "Try Again",
            cancelTitle: "Cancel"
        )
    }

    func makeAddAccountSignInRetryRequest(
        outcome: AccountActionFlow.AddAccountSignInFailureOutcome
    ) -> MenuBarConfirmationAlertRequest {
        switch outcome {
        case .expiredCode:
            MenuBarConfirmationAlertRequest(
                messageText: "Sign-In Expired",
                informativeText: """
                The Codex sign-in code expired before the account was added.

                If ChatGPT asked you to enable device-code authorization, enable it in ChatGPT Security Settings, then try again.
                """,
                confirmTitle: "Try Again",
                cancelTitle: "Cancel"
            )
        case .promptUnavailable, .captureFailed, .verificationFailed:
            MenuBarConfirmationAlertRequest(
                messageText: "Couldn't Add Account",
                informativeText: makeAddAccountSignInFailureRequest(outcome: outcome).informativeText,
                confirmTitle: "Try Again",
                cancelTitle: "Cancel"
            )
        }
    }

    func makeAccountAlreadySavedRequest(accountName: String) -> MenuBarInfoAlertRequest {
        return MenuBarInfoAlertRequest(
            messageText: "Account Already Saved",
            informativeText: "This Codex account is already saved as \(accountName).",
            style: .informational,
            buttonTitle: "OK"
        )
    }

    func makeAddAccountSignInFailureRequest(
        outcome: AccountActionFlow.AddAccountSignInFailureOutcome
    ) -> MenuBarInfoAlertRequest {
        switch outcome {
        case .promptUnavailable(let reason):
            return makeAddAccountStartFailureRequest(reason: reason)
        case .expiredCode:
            return MenuBarInfoAlertRequest(
                messageText: "Sign-In Expired",
                informativeText: """
                The Codex sign-in code expired before the account was added.

                If ChatGPT asked you to enable device-code authorization, enable it in ChatGPT Security Settings, then try again.
                """,
                style: .warning,
                buttonTitle: "OK"
            )
        case .captureFailed:
            return MenuBarInfoAlertRequest(
                messageText: "Couldn't Add Account",
                informativeText: "The Codex sign-in did not complete.",
                style: .warning,
                buttonTitle: "OK"
            )
        case .verificationFailed:
            return MenuBarInfoAlertRequest(
                messageText: "Couldn't Add Account",
                informativeText: "CodexPill could not verify the signed-in account.",
                style: .warning,
                buttonTitle: "OK"
            )
        }
    }

    private func makeAddAccountStartFailureRequest(reason: String? = nil) -> MenuBarInfoAlertRequest {
        let detail: String
        if let reason, !reason.isEmpty {
            detail = "\n\nCodex reported: \(reason)"
        } else {
            detail = ""
        }

        return MenuBarInfoAlertRequest(
            messageText: "Couldn't Start Sign-In",
            informativeText: """
            Codex could not start a sign-in session. Check your network connection, then try again.

            If ChatGPT asked you to enable device-code authorization, enable it in ChatGPT Security Settings, then try again.\(detail)
            """,
            style: .warning,
            buttonTitle: "OK"
        )
    }

    func makeAddAccountUnsafeAuthChangeRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Couldn't Add Account",
            informativeText: "CodexPill could not verify that This Mac stayed unchanged. No account was added.",
            style: .warning,
            buttonTitle: "OK"
        )
    }

    func makeAddAccountSaveFailureRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Couldn't Save Account",
            informativeText: "The sign-in completed, but CodexPill could not save the account. This Mac was not changed.",
            style: .warning,
            buttonTitle: "OK"
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

    func makeRemoveAccountRequest(accountName: String, activeTargets: [String] = []) -> MenuBarConfirmationAlertRequest {
        guard !activeTargets.isEmpty else {
            return MenuBarConfirmationAlertRequest(
                messageText: "Remove saved account?",
                informativeText: "This removes \(accountName) from CodexPill.\n\nThis action cannot be undone.",
                confirmTitle: "Remove",
                cancelTitle: "Cancel"
            )
        }

        return MenuBarConfirmationAlertRequest(
            messageText: "\(accountName) is in use",
            informativeText: "Sign out on \(formattedTargetList(activeTargets)) before removing it?",
            confirmTitle: "Sign Out and Remove",
            cancelTitle: "Cancel"
        )
    }

    func makeRenameAccountRequest(accountName: String) -> MenuBarTextInputAlertRequest {
        MenuBarTextInputAlertRequest(
            messageText: "Rename saved account",
            informativeText: "This only changes the name shown in CodexPill.",
            fieldTitle: "Account Name",
            placeholder: accountName,
            confirmTitle: "Rename",
            cancelTitle: "Cancel"
        )
    }

    func makeAddHostRequest() -> MenuBarHostSetupPanelRequest {
        MenuBarHostSetupPanelRequest(
            messageText: "Add remote host",
            informativeText: "Enter the SSH destination CodexPill should use, for example user@host.",
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
            informativeText: "Install \(accountName) on \(hostName) and switch the host to it now? If you cancel, the host will not be added yet.",
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
            informativeText: userFacingErrorMessage(for: message),
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

        lines.append("Switch \(targetDescription) to \(accountName).")

        if let runningCLISessions, runningCLISessions > 0 {
            let sessionText = runningCLISessions == 1
                ? "1 Codex terminal is"
                : "\(runningCLISessions) Codex terminals are"
            lines.append("")
            lines.append("\(sessionText) running. Restart to use the new account.")
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
            "This switches This Mac to \(accountName) and restarts Codex."
        ]

        if runningCLISessions > 0 {
            let sessionText = runningCLISessions == 1 ? "1 Codex terminal is" : "\(runningCLISessions) Codex terminals are"
            lines.append("\(sessionText) running. Restart to use the new account.")
        }

        return lines.joined(separator: " ")
    }

    private func addAccountInformativeText(runningCLISessions: Int) -> String {
        var lines = [
            "Use your browser to sign in. CodexPill will save the account without changing This Mac."
        ]

        if runningCLISessions > 0 {
            let sessionText = runningCLISessions == 1 ? "1 Codex terminal is" : "\(runningCLISessions) Codex terminals are"
            let pronoun = runningCLISessions == 1 ? "It" : "They"
            lines.append("\(sessionText) running. \(pronoun) will keep using the current account.")
        }

        return lines.joined(separator: " ")
    }

    private func formattedTargetList(_ targets: [String]) -> String {
        switch targets.count {
        case 0:
            return ""
        case 1:
            return targets[0]
        case 2:
            return "\(targets[0]) and \(targets[1])"
        default:
            let leadingTargets = targets.dropLast().joined(separator: ", ")
            return "\(leadingTargets), and \(targets[targets.count - 1])"
        }
    }
}

private func userFacingErrorMessage(for message: String) -> String {
    let lowercased = message.lowercased()
    if lowercased.contains("token_invalidated") ||
        lowercased.contains("authentication token has been invalidated") ||
        lowercased.contains("refresh token was revoked") {
        return "This saved Codex account needs to be signed in again before it can be used. Remove and add the account again, then retry."
    }
    return message
}
