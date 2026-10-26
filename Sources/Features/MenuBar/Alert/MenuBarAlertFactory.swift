import AppKit

struct MenuBarAlertFactory {
    private let appVersionText: String

    init(appVersionText: String = MenuBarAppVersionText.current()) {
        self.appVersionText = appVersionText
    }

    func makeFirstRunAddAccountRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Sign in to Codex?",
            informativeText: "Sign in to Codex in your browser.",
            confirmTitle: "Continue",
            cancelTitle: "Not Now"
        )
    }

    func makeSignInRequest(prompt: IsolatedCodexLoginPrompt) -> MenuBarAddAccountSignInPanelRequest {
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

    /// Asked before a new sign-in replaces the Codex account on this Mac.
    func makeReplaceCodexAccountRequest(newLabel: String, currentLabel: String?, runningCLISessions: Int) -> MenuBarConfirmationAlertRequest {
        var lines = [currentLabel.map { "\(newLabel) replaces \($0) on this Mac, and Codex restarts." } ?? "\(newLabel) becomes the Codex account on this Mac, and Codex restarts."]
        if runningCLISessions > 0 {
            let sessionText = runningCLISessions == 1 ? "1 Codex terminal is" : "\(runningCLISessions) Codex terminals are"
            lines.append("\(sessionText) running. Restart to use the new account.")
        }
        return MenuBarConfirmationAlertRequest(
            messageText: "Use \(newLabel) for Codex?",
            informativeText: lines.joined(separator: " "),
            confirmTitle: "Use on This Mac",
            cancelTitle: "Cancel"
        )
    }

    func makeSignInRetryRequest(
        outcome: AccountActionFlow.SignInFailureOutcome
    ) -> MenuBarConfirmationAlertRequest {
        switch outcome {
        case .expiredCode:
            MenuBarConfirmationAlertRequest(
                messageText: "Sign-In Expired",
                informativeText: """
                The Codex sign-in code expired before you finished signing in.

                If ChatGPT asked you to enable device-code authorization, enable it in ChatGPT Security Settings, then try again.
                """,
                confirmTitle: "Try Again",
                cancelTitle: "Cancel"
            )
        case .promptUnavailable, .captureFailed, .verificationFailed:
            MenuBarConfirmationAlertRequest(
                messageText: "Couldn't Sign In",
                informativeText: makeSignInFailureRequest(outcome: outcome).informativeText,
                confirmTitle: "Try Again",
                cancelTitle: "Cancel"
            )
        }
    }

    func makeCodexSignOutRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Sign Out of Codex?",
            informativeText: "This signs Codex out on this Mac, including the Codex app and CLI.",
            confirmTitle: "Sign Out",
            cancelTitle: "Cancel"
        )
    }

    func makeAccountAlreadyInUseRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Already Signed In",
            informativeText: "This Codex account is already the one on this Mac.",
            style: .informational,
            buttonTitle: "OK"
        )
    }

    func makeSignInFailureRequest(
        outcome: AccountActionFlow.SignInFailureOutcome
    ) -> MenuBarInfoAlertRequest {
        switch outcome {
        case .promptUnavailable(let reason):
            return makeSignInStartFailureRequest(reason: reason)
        case .expiredCode:
            return MenuBarInfoAlertRequest(
                messageText: "Sign-In Expired",
                informativeText: """
                The Codex sign-in code expired before you finished signing in.

                If ChatGPT asked you to enable device-code authorization, enable it in ChatGPT Security Settings, then try again.
                """,
                style: .warning,
                buttonTitle: "OK"
            )
        case .captureFailed:
            return MenuBarInfoAlertRequest(
                messageText: "Couldn't Sign In",
                informativeText: "The Codex sign-in did not complete.",
                style: .warning,
                buttonTitle: "OK"
            )
        case .verificationFailed:
            return MenuBarInfoAlertRequest(
                messageText: "Couldn't Sign In",
                informativeText: "rusage could not verify the signed-in account.",
                style: .warning,
                buttonTitle: "OK"
            )
        }
    }

    private func makeSignInStartFailureRequest(reason: String? = nil) -> MenuBarInfoAlertRequest {
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

    func makeSignInUnsafeAuthChangeRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Couldn't Sign In",
            informativeText: "The Codex sign-in on this Mac changed meanwhile. Nothing was replaced.",
            style: .warning,
            buttonTitle: "OK"
        )
    }

    /// Shown once at launch when the move from CodexPill to rusage could not copy everything.
    func makeCodexPillDataNotCopiedRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Some CodexPill data not copied",
            informativeText: "The originals are still on this Mac.",
            style: .warning,
            buttonTitle: "OK"
        )
    }

    func makeAboutRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "About rusage",
            informativeText: """
            rusage
            Version \(appVersionText)

            A macOS menu bar app for your Codex, Claude Code and Cursor usage limits.

            Developed by Raphael Grau.
            """,
            style: .informational,
            buttonTitle: "OK"
        )
    }

    func makeDiagnosticsExportRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Export Diagnostics?",
            informativeText: "rusage will create a redacted support file with app version, settings, account aliases, limit freshness, and recent workflow events. It does not include auth tokens, emails, hostnames, local paths, or raw logs.",
            confirmTitle: "Export",
            cancelTitle: "Cancel"
        )
    }

    func makeEnableLaunchAtLoginRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Launch rusage at Login?",
            informativeText: "rusage will ask macOS to open it automatically when you log in. You can turn this off here or in System Settings.",
            confirmTitle: "Enable",
            cancelTitle: "Cancel"
        )
    }

    func makeResetInProgressRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Reset in progress",
            informativeText: "Try again when it finishes.",
            style: .informational,
            buttonTitle: "OK"
        )
    }

    func makeCodexAppNotFoundForSignInRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Codex app not found",
            informativeText: "Install the Codex app, then sign in again.",
            style: .warning,
            buttonTitle: "OK"
        )
    }

    func makeCodexAppNotFoundAfterSignInRequest() -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "Codex app not found",
            informativeText: "Signed in. Codex uses the account when it opens.",
            style: .informational,
            buttonTitle: "OK"
        )
    }

    func makeErrorRequest(message: String) -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: "rusage Error",
            informativeText: userFacingErrorMessage(for: message),
            style: .warning,
            buttonTitle: "OK"
        )
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
        let releaseVersion = bundle.object(forInfoDictionaryKey: "RUsageReleaseVersion") as? String
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
        return "Codex needs you to sign in again. Sign in from Settings › Accounts, then retry."
    }
    return message
}
