import Foundation
import Testing

@testable import RUsage

struct AccountActionFlowTests {
    @Test
    func aFinishedSignInAsksBeforeReplacingTheAccount() async throws {
        let authFile = makeCodexAuthFile()
        let workflow = CodexSignInWorkflow(
            authFile: authFile,
            isolatedLoginClient: IsolatedCodexLoginProbe(authData: makeCodexAuthData(email: "sam@example.com")),
            codexAppProcessClient: CodexAppProcessProbe()
        )
        let signedIn = try await workflow.complete(try await workflow.start())

        let step = AccountActionFlow().resolveSignInCompletion(.completed(signedIn))

        guard case .confirmReplace(let resolved) = step else {
            Issue.record("Expected a finished sign-in to ask before replacing the account")
            return
        }
        #expect(resolved.account.email == "sam@example.com")
    }

    @Test
    func cancelledSignInCompletionDoesNotShowGenericError() {
        let step = AccountActionFlow().resolveSignInCompletion(
            .failed(CancellationError())
        )

        guard case .none = step else {
            Issue.record("Expected cancellation to end the Add Account flow silently")
            return
        }
    }

    @Test
    func missingCodexAppGetsItsOwnAlertInsteadOfAGenericError() {
        let step = AccountActionFlow().resolveSignInFailure(CodexAppNotFoundError())

        #expect(step == .showCodexAppNotFound)
    }

    @Test
    func expiredSignInCodeOffersRetry() {
        let step = AccountActionFlow().resolveSignInFailure(
            IsolatedCodexLoginError.authCaptureTimedOut
        )

        #expect(step == .offerSignInRetry(outcome: .expiredCode))
    }

    @Test
    func promptUnavailablePreservesSanitizedFailureReason() {
        let step = AccountActionFlow().resolveSignInFailure(
            IsolatedCodexLoginError.promptUnavailable(reason: "error sending request")
        )

        #expect(step == .showSignInFailure(.promptUnavailable(reason: "error sending request")))
    }

    @Test
    func authCaptureFailureMapsToAccountSignInOutcome() {
        let step = AccountActionFlow().resolveSignInFailure(
            IsolatedCodexLoginError.authCaptureFailed
        )

        #expect(step == .showSignInFailure(.captureFailed))
    }

    @Test
    func loginVerificationFailureMapsToAccountSignInOutcome() {
        let step = AccountActionFlow().resolveSignInFailure(
            IsolatedCodexLoginError.loginStatusVerificationFailed
        )

        #expect(step == .showSignInFailure(.verificationFailed))
    }

    @Test
    func liveAuthMutationRoutesToUnsafeAuthChangeStep() {
        let step = AccountActionFlow().resolveSignInFailure(
            CodexSignInWorkflowError.liveAuthChanged
        )

        #expect(step == .showUnsafeAuthChange)
    }

    @Test
    func signingInToTheAccountInUseRoutesToItsOwnStep() {
        let step = AccountActionFlow().resolveSignInFailure(CodexSignInWorkflowError.accountAlreadyInUse)

        #expect(step == .showAccountAlreadyInUse)
    }
}
