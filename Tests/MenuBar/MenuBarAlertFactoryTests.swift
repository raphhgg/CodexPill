import AppKit
import Foundation
import Testing

@testable import CodexPill

struct MenuBarAlertFactoryTests {
    private let factory = MenuBarAlertFactory()

    @Test
    func aboutRequestShowsCurrentAppVersion() {
        let factory = MenuBarAlertFactory(appVersionText: "0.1.0-beta.1")

        let request = factory.makeAboutRequest()

        #expect(request.messageText == "About CodexPill")
        #expect(request.informativeText.contains("Version 0.1.0-beta.1"))
        #expect(!request.informativeText.contains("Version 0.1\n"))
    }

    @Test
    func debugAppVersionTextShowsDev() {
        #expect(MenuBarAppVersionText.current() == "Dev")
    }

    @Test
    func releaseAppVersionPrefersInjectedReleaseVersion() {
        let version = MenuBarAppVersionText.release(
            releaseVersion: "v0.1.0-beta.1",
            marketingVersion: "0.1.0",
            buildNumber: "1"
        )

        #expect(version == "0.1.0-beta.1")
    }

    @Test
    func releaseAppVersionFallsBackToMarketingVersionAndBuildNumber() {
        let version = MenuBarAppVersionText.release(
            releaseVersion: nil,
            marketingVersion: "0.1.0",
            buildNumber: "1"
        )

        #expect(version == "0.1.0 (1)")
    }

    @Test
    func switchAccountWarningMentionsRunningCliSessions() {
        let request = factory.makeSwitchAccountRequest(accountName: "Work", runningCLISessions: 2)

        #expect(request.informativeText.contains("switches This Mac to Work"))
        #expect(request.informativeText.contains("2 Codex terminals are running"))
        #expect(request.informativeText.contains("Restart to use the new account."))
    }

    @Test
    func addAccountNamePromptExplainsDisplayName() {
        let request = factory.makeAddAccountRequest(runningCLISessions: 0)

        #expect(request.messageText == "Add account")
        #expect(request.fieldTitle == "Account Name")
        #expect(request.placeholder == "Work")
        #expect(request.confirmTitle == "Continue")
        #expect(request.requiresNonEmptyValue)
        #expect(request.informativeText == "Choose a name for this saved account. You can change it later.")
        #expect(!request.informativeText.contains("browser"))
        #expect(!request.informativeText.contains("Codex terminal is running"))
    }

    @Test
    func addAccountNamePromptStaysFocusedOnNamingWhenCliSessionsExist() {
        let request = factory.makeAddAccountRequest(runningCLISessions: 1)

        #expect(request.informativeText == "Choose a name for this saved account. You can change it later.")
        #expect(!request.informativeText.contains("Codex terminal is running"))
    }

    @Test
    func addAccountSignInRequestShowsDeviceCodeCopy() {
        let prompt = IsolatedCodexLoginPrompt(
            url: URL(string: "https://auth.openai.com/codex/device")!,
            userCode: "ABCD-EFGH"
        )

        let request = factory.makeAddAccountSignInRequest(prompt: prompt)

        #expect(request.messageText == "Sign in to Codex")
        #expect(request.informativeText.contains("Copy this code"))
        #expect(request.userCode == "ABCD-EFGH")
        #expect(request.promptURL == prompt.url)
        #expect(request.copyTitle == "Copy Code")
        #expect(request.openBrowserTitle == "Open Browser")
        #expect(request.browserOpenedStatusText.contains("Browser opened"))
        #expect(request.cancelTitle == "Cancel")
    }

    @Test
    func addAccountSuccessRequestOffersOptionalLocalSwitch() {
        let request = factory.makeAddAccountSuccessRequest(accountName: "Business 2", runningCLISessions: 0)

        #expect(request.messageText == "Account Added")
        #expect(request.informativeText.contains("Business 2 was saved"))
        #expect(request.informativeText.contains("This Mac was not changed"))
        #expect(!request.informativeText.contains("Codex terminal is running"))
        #expect(request.confirmTitle == "Use on This Mac")
        #expect(request.cancelTitle == "Done")
    }

    @Test
    func addAccountSuccessRequestMentionsRunningCliSessionsBeforeLocalSwitch() {
        let request = factory.makeAddAccountSuccessRequest(accountName: "Business 2", runningCLISessions: 2)

        #expect(request.informativeText.contains("2 Codex terminals are running"))
        #expect(request.informativeText.contains("Restart them to use the new account."))
        #expect(request.confirmTitle == "Use on This Mac")
    }

    @Test
    func addAccountDuplicateNameRequestOffersRetry() {
        let request = factory.makeAddAccountDuplicateNameRequest()

        #expect(request.messageText == "Name Already Used")
        #expect(request.informativeText.contains("Choose a different name"))
        #expect(request.confirmTitle == "Try Again")
        #expect(request.cancelTitle == "Cancel")
    }

    @Test
    func addAccountFailureRequestsUseSpecificRecoveryCopy() {
        let expired = factory.makeAddAccountSignInRetryRequest(outcome: .expiredCode)
        #expect(expired.messageText == "Sign-In Expired")
        #expect(expired.informativeText.contains("enable device-code authorization"))
        #expect(expired.informativeText.contains("ChatGPT Security Settings"))
        #expect(expired.confirmTitle == "Try Again")
        #expect(expired.cancelTitle == "Cancel")

        let duplicate = factory.makeAccountAlreadySavedRequest(accountName: "Business 4")
        #expect(duplicate.messageText == "Account Already Saved")
        #expect(duplicate.informativeText.contains("Business 4"))

        #expect(factory.makeAddAccountSignInFailureRequest(outcome: .promptUnavailable(reason: nil)).messageText == "Couldn't Start Sign-In")
        #expect(factory.makeAddAccountUnsafeAuthChangeRequest().messageText == "Couldn't Add Account")
        #expect(factory.makeAddAccountSaveFailureRequest().messageText == "Couldn't Save Account")
    }

    @Test
    func addAccountStartFailureCanIncludeSanitizedCodexReason() {
        let request = factory.makeAddAccountSignInFailureRequest(
            outcome: .promptUnavailable(reason: "error sending request")
        )

        #expect(request.messageText == "Couldn't Start Sign-In")
        #expect(request.informativeText.contains("Check your network connection"))
        #expect(request.informativeText.contains("enable device-code authorization"))
        #expect(request.informativeText.contains("ChatGPT Security Settings"))
        #expect(request.informativeText.contains("Codex reported: error sending request"))
    }

    @Test
    func addAccountSignInFailureOutcomesRenderWithoutPlatformErrors() {
        let capture = factory.makeAddAccountSignInFailureRequest(outcome: .captureFailed)
        #expect(capture.messageText == "Couldn't Add Account")
        #expect(capture.informativeText == "The Codex sign-in did not complete.")

        let verification = factory.makeAddAccountSignInFailureRequest(outcome: .verificationFailed)
        #expect(verification.messageText == "Couldn't Add Account")
        #expect(verification.informativeText == "CodexPill could not verify the signed-in account.")
    }

    @Test
    func removeAccountRequestUsesPlainRemoveWhenAccountIsInactive() {
        let request = factory.makeRemoveAccountRequest(accountName: "Work")

        #expect(request.informativeText.contains("removes Work from CodexPill"))
        #expect(request.confirmTitle == "Remove")
    }

    @Test
    func removeAccountRequestRequiresSignOutWhenAccountIsActiveOnTargets() {
        let request = factory.makeRemoveAccountRequest(
            accountName: "Business 4",
            activeTargets: ["This Mac", "debian-vm"]
        )

        #expect(request.messageText == "Business 4 is in use")
        #expect(request.informativeText == "Sign out on This Mac and debian-vm before removing it?")
        #expect(request.confirmTitle == "Sign Out and Remove")
    }

    @Test
    func renameAccountRequestUsesCurrentNameAsPlaceholder() {
        let request = factory.makeRenameAccountRequest(accountName: "Business 1")

        #expect(request.messageText == "Rename saved account")
        #expect(request.placeholder == "Business 1")
        #expect(request.confirmTitle == "Rename")
    }

    @Test
    func addHostRequestUsesTestThenAddCopy() {
        let request = factory.makeAddHostRequest()

        #expect(request.messageText == "Add remote host")
        #expect(request.placeholder == "user@host")
        #expect(request.nameFieldTitle == "Host Name (Optional)")
        #expect(request.namePlaceholder == "buildbox")
        #expect(request.confirmTitle == "Add Host")
        #expect(request.cancelTitle == "Cancel")
        #expect(request.idleStatusText == "CodexPill checks the connection automatically.")
        #expect(request.successStatusText == "Connection successful.")
    }

    @Test
    func errorRequestUsesWarningStyle() {
        let request = factory.makeErrorRequest(message: "Boom")

        #expect(request.messageText == "CodexPill Error")
        #expect(request.informativeText == "Boom")
        #expect(request.style == .warning)
    }

    @Test
    func errorRequestMapsInvalidatedTokenBackendErrorsToActionableCopy() {
        let request = factory.makeErrorRequest(message: """
        Codex app-server error: failed to fetch codex rate limits: GET https://chatgpt.com/backend-api/wham/usage failed: 401 Unauthorized; body={"error":{"message":"Your authentication token has been invalidated. Please try signing in again.","code":"token_invalidated","status":401}}
        """)

        #expect(request.messageText == "CodexPill Error")
        #expect(request.informativeText == "This saved Codex account needs to be signed in again before it can be used. Remove and add the account again, then retry.")
        #expect(!request.informativeText.contains("backend-api"))
        #expect(!request.informativeText.contains("token_invalidated"))
    }

    @Test
    func installCurrentAccountOnHostRequestExplainsCancelAbortsSetup() {
        let request = factory.makeInstallCurrentAccountOnHostRequest(accountName: "Business 1", hostName: "buildbox")

        #expect(request.messageText == "Install current account on buildbox?")
        #expect(request.informativeText.contains("Install Business 1 on buildbox"))
        #expect(request.informativeText.contains("the host will not be added yet"))
        #expect(request.confirmTitle == "Install and Switch")
        #expect(request.cancelTitle == "Cancel")
    }

    @Test
    func diagnosticsExportRequestExplainsRedactedSupportFile() {
        let request = factory.makeDiagnosticsExportRequest()

        #expect(request.messageText == "Export Diagnostics?")
        #expect(request.informativeText.contains("redacted support file"))
        #expect(request.informativeText.contains("account aliases"))
        #expect(request.informativeText.contains("host aliases"))
        #expect(request.informativeText.contains("auth tokens"))
        #expect(request.informativeText.contains("emails"))
        #expect(request.informativeText.contains("hostnames"))
        #expect(request.informativeText.contains("raw logs"))
        #expect(request.confirmTitle == "Export")
        #expect(request.cancelTitle == "Cancel")
    }

    @Test
    func launchAtLoginRequestExplainsSystemLoginItemChange() {
        let request = factory.makeEnableLaunchAtLoginRequest()

        #expect(request.messageText == "Launch CodexPill at Login?")
        #expect(request.informativeText.contains("open it automatically when you log in"))
        #expect(request.informativeText.contains("turn this off here or in System Settings"))
        #expect(request.confirmTitle == "Enable")
        #expect(request.cancelTitle == "Cancel")
    }

    @Test
    func notificationActionRequestExplainsSubstitutionWhenPresent() {
        let request = factory.makeNotificationActionRequest(
            accountName: "Business 2",
            targetDescription: "debian-vm",
            substitutionMessage: "Business 4 is no longer the best option. Switching to Business 2 instead.",
            runningCLISessions: nil
        )

        #expect(request.messageText == "Use Business 2 now?")
        #expect(request.informativeText.contains("Business 4 is no longer the best option. Switching to Business 2 instead."))
        #expect(request.informativeText.contains("Switch debian-vm to Business 2."))
        #expect(request.confirmTitle == "Switch")
    }
}
