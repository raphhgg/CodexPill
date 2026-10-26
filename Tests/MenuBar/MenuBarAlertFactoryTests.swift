import AppKit
import Foundation
import Testing

@testable import RUsage

struct MenuBarAlertFactoryTests {
    private let factory = MenuBarAlertFactory()

    @Test
    func aboutRequestShowsCurrentAppVersion() {
        let factory = MenuBarAlertFactory(appVersionText: "0.1.0-beta.1")

        let request = factory.makeAboutRequest()

        #expect(request.messageText == "About rusage")
        #expect(request.informativeText.contains("Version 0.1.0-beta.1"))
        #expect(!request.informativeText.contains("Version 0.1\n"))
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
    func signInRequestCarriesDeviceCodeAndURL() {
        let prompt = IsolatedCodexLoginPrompt(
            url: URL(string: "https://auth.openai.com/codex/device")!,
            userCode: "ABCD-EFGH"
        )

        let request = factory.makeSignInRequest(prompt: prompt)

        #expect(request.userCode == "ABCD-EFGH")
        #expect(request.promptURL == URL(string: "https://auth.openai.com/codex/device")!)
    }

    @Test
    func replacingTheCodexAccountNamesBothAccountsAndRunningTerminals() {
        let request = factory.makeReplaceCodexAccountRequest(newLabel: "sam@example.com", currentLabel: "alex@example.com", runningCLISessions: 2)

        #expect(request.messageText == "Use sam@example.com for Codex?")
        #expect(request.informativeText.contains("sam@example.com replaces alex@example.com on this Mac"))
        #expect(request.informativeText.contains("2 Codex terminals are running"))
        #expect(request.confirmTitle == "Use on This Mac")
        #expect(request.cancelTitle == "Cancel")
    }

    @Test
    func replacingASignedOutCodexSaysTheAccountBecomesTheOne() {
        let request = factory.makeReplaceCodexAccountRequest(newLabel: "sam@example.com", currentLabel: nil, runningCLISessions: 0)

        #expect(request.informativeText == "sam@example.com becomes the Codex account on this Mac, and Codex restarts.")
    }

    @Test
    func signInFailureRequestsUseSpecificRecoveryCopy() {
        let expired = factory.makeSignInRetryRequest(outcome: .expiredCode)
        #expect(expired.messageText == "Sign-In Expired")
        #expect(expired.informativeText.contains("enable device-code authorization"))
        #expect(expired.informativeText.contains("ChatGPT Security Settings"))
        #expect(expired.confirmTitle == "Try Again")
        #expect(expired.cancelTitle == "Cancel")

        #expect(factory.makeAccountAlreadyInUseRequest().messageText == "Already Signed In")
        #expect(factory.makeSignInFailureRequest(outcome: .promptUnavailable(reason: nil)).messageText == "Couldn't Start Sign-In")
        #expect(factory.makeSignInUnsafeAuthChangeRequest().messageText == "Couldn't Sign In")
    }

    @Test
    func signInStartFailureCanIncludeSanitizedCodexReason() {
        let request = factory.makeSignInFailureRequest(
            outcome: .promptUnavailable(reason: "error sending request")
        )

        #expect(request.messageText == "Couldn't Start Sign-In")
        #expect(request.informativeText.contains("Check your network connection"))
        #expect(request.informativeText.contains("Codex reported: error sending request"))
    }

    @Test
    func signInFailureOutcomesRenderWithoutPlatformErrors() {
        let capture = factory.makeSignInFailureRequest(outcome: .captureFailed)
        #expect(capture.messageText == "Couldn't Sign In")
        #expect(capture.informativeText == "The Codex sign-in did not complete.")

        let verification = factory.makeSignInFailureRequest(outcome: .verificationFailed)
        #expect(verification.informativeText == "rusage could not verify the signed-in account.")
    }

    @Test
    func errorRequestUsesWarningStyle() {
        let request = factory.makeErrorRequest(message: "Boom")

        #expect(request.messageText == "rusage Error")
        #expect(request.informativeText == "Boom")
        #expect(request.style == .warning)
    }

    @Test
    func errorRequestMapsInvalidatedTokenBackendErrorsToActionableCopy() {
        let request = factory.makeErrorRequest(message: """
        Codex app-server error: failed to fetch codex rate limits: GET https://chatgpt.com/backend-api/wham/usage failed: 401 Unauthorized; body={"error":{"message":"Your authentication token has been invalidated. Please try signing in again.","code":"token_invalidated","status":401}}
        """)

        #expect(request.messageText == "rusage Error")
        #expect(request.informativeText == "Codex needs you to sign in again. Sign in from Settings › Accounts, then retry.")
        #expect(!request.informativeText.contains("backend-api"))
        #expect(!request.informativeText.contains("token_invalidated"))
    }

    @Test
    func diagnosticsExportRequestExplainsRedactedSupportFile() {
        let request = factory.makeDiagnosticsExportRequest()

        #expect(request.messageText == "Export Diagnostics?")
        #expect(request.informativeText.contains("redacted support file"))
        #expect(request.informativeText.contains("account aliases"))
        #expect(request.informativeText.contains("auth tokens"))
        #expect(request.informativeText.contains("emails"))
        #expect(request.informativeText.contains("hostnames"))
        #expect(request.informativeText.contains("raw logs"))
        #expect(request.confirmTitle == "Export")
        #expect(request.cancelTitle == "Cancel")
    }

}
