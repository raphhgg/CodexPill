import AppKit

struct MenuBarAlertFactory {
    private let appVersionText: String

    init(appVersionText: String = MenuBarAppVersionText.current()) {
        self.appVersionText = appVersionText
    }

    func makeFirstRunAddAccountRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Add a Codex account?",
            informativeText: "Sign in to Codex in your browser.",
            confirmTitle: "Continue",
            cancelTitle: "Not Now"
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

    func makeAddAccountSuccessRequest(accountLabel: String, runningCLISessions: Int) -> MenuBarConfirmationAlertRequest {
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
            informativeText: "\(accountLabel) was saved. This Mac was not changed.\(cliNotice)",
            confirmTitle: "Use on This Mac",
            cancelTitle: "Done"
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

    func makeAccountAlreadySavedRequest(accountLabel: String) -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Account Already Saved",
            informativeText: "This Codex account is already saved as \(accountLabel).",
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
                informativeText: "Refill could not verify the signed-in account.",
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
            informativeText: "Refill could not verify that This Mac stayed unchanged. No account was added.",
            style: .warning,
            buttonTitle: "OK"
        )
    }

    func makeAddAccountSaveFailureRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Couldn't Save Account",
            informativeText: "The sign-in completed, but Refill could not save the account. This Mac was not changed.",
            style: .warning,
            buttonTitle: "OK"
        )
    }

    func makeSwitchAccountRequest(accountLabel: String, runningCLISessions: Int) -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Switch account?",
            informativeText: switchInformativeText(for: accountLabel, runningCLISessions: runningCLISessions),
            confirmTitle: "Switch",
            cancelTitle: "Cancel"
        )
    }

    func makeRemoveAccountRequest(accountLabel: String, activeTargets: [String] = []) -> MenuBarConfirmationAlertRequest {
        guard !activeTargets.isEmpty else {
            return MenuBarConfirmationAlertRequest(
                messageText: "Remove saved account?",
                informativeText: "This removes \(accountLabel) from Refill.\n\nThis action cannot be undone.",
                confirmTitle: "Remove",
                cancelTitle: "Cancel"
            )
        }

        return MenuBarConfirmationAlertRequest(
            messageText: "\(accountLabel) is in use",
            informativeText: "Sign out on \(formattedTargetList(activeTargets)) before removing it?",
            confirmTitle: "Sign Out and Remove",
            cancelTitle: "Cancel"
        )
    }

    func makeAboutRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "About Refill",
            informativeText: """
            Refill
            Version \(appVersionText)

            A macOS menu bar app for your Codex, Claude Code and Cursor usage limits, with one-click account switching.

            Developed by Raphael Grau.
            """,
            style: .informational,
            buttonTitle: "OK"
        )
    }

    func makeDiagnosticsExportRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Export Diagnostics?",
            informativeText: "Refill will create a redacted support file with app version, settings, account aliases, limit freshness, and recent workflow events. It does not include auth tokens, emails, hostnames, local paths, or raw logs.",
            confirmTitle: "Export",
            cancelTitle: "Cancel"
        )
    }

    func makeEnableLaunchAtLoginRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Launch Refill at Login?",
            informativeText: "Refill will ask macOS to open it automatically when you log in. You can turn this off here or in System Settings.",
            confirmTitle: "Enable",
            cancelTitle: "Cancel"
        )
    }

    func makeResetInProgressRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Reset in progress",
            informativeText: "Switch accounts when it finishes.",
            style: .informational,
            buttonTitle: "OK"
        )
    }

    func makeCodexAppNotFoundForAddRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Codex app not found",
            informativeText: "Install the Codex app, then add the account again.",
            style: .warning,
            buttonTitle: "OK"
        )
    }

    func makeCodexAppNotFoundAfterSwitchRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Codex app not found",
            informativeText: "Switched. Codex uses the account when it opens.",
            style: .informational,
            buttonTitle: "OK"
        )
    }

    func makeErrorRequest(message: String) -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Refill Error",
            informativeText: userFacingErrorMessage(for: message),
            style: .warning,
            buttonTitle: "OK"
        )
    }

    private func switchInformativeText(for accountLabel: String, runningCLISessions: Int) -> String {
        var lines = [
            "This switches This Mac to \(accountLabel) and restarts Codex."
        ]

        if runningCLISessions > 0 {
            let sessionText = runningCLISessions == 1 ? "1 Codex terminal is" : "\(runningCLISessions) Codex terminals are"
            lines.append("\(sessionText) running. Restart to use the new account.")
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

enum MenuBarAppVersionText {
    static func current(bundle: Bundle = .main) -> String {
        #if DEBUG
        "Dev"
        #else
        release(bundle: bundle)
        #endif
    }

    static func release(bundle: Bundle) -> String {
        let releaseVersion = bundle.object(forInfoDictionaryKey: "RefillReleaseVersion") as? String
        let marketingVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        return release(releaseVersion: releaseVersion, marketingVersion: marketingVersion, buildNumber: buildNumber)
    }

    static func release(
        releaseVersion: String?,
        marketingVersion: String?,
        buildNumber: String?
    ) -> String {
        if let normalizedReleaseVersion = normalized(releaseVersion) {
            return normalizedReleaseVersion
        }

        guard let normalizedMarketingVersion = normalized(marketingVersion) else {
            return "Unknown"
        }

        guard let normalizedBuildNumber = normalized(buildNumber) else {
            return normalizedMarketingVersion
        }

        return "\(normalizedMarketingVersion) (\(normalizedBuildNumber))"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
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
