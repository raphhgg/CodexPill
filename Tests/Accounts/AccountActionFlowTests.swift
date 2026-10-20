import Foundation
import Testing

@testable import rusage

struct AccountActionFlowTests {
    @Test
    func completedAddAccountOffersOptionalLocalSwitch() throws {
        let account = makeAccount(name: "Business 2")

        let step = AccountActionFlow().resolveAddAccountCompletion(
            .completed(account)
        )

        guard case .offerLocalSwitch(let resolvedAccount) = step else {
            Issue.record("Expected completed Add Account to offer a local switch")
            return
        }
        #expect(resolvedAccount == account)
    }

    @Test
    func acceptedAddAccountSuccessBypassesSwitchConfirmationAndSwitchesLocally() {
        let account = makeAccount(name: "Business 2")

        let step = AccountActionFlow().resolveAddAccountSuccessConfirmation(
            account: account,
            accepted: true
        )

        #expect(step == .switchLocally(account))
    }

    @Test
    func declinedAddAccountSuccessDoesNotSwitchLocally() {
        let account = makeAccount(name: "Business 2")

        let step = AccountActionFlow().resolveAddAccountSuccessConfirmation(
            account: account,
            accepted: false
        )

        #expect(step == .none)
    }

    @Test
    func cancelledSignInCompletionDoesNotShowGenericError() {
        let step = AccountActionFlow().resolveAddAccountCompletion(
            .failed(CancellationError())
        )

        guard case .none = step else {
            Issue.record("Expected cancellation to end the Add Account flow silently")
            return
        }
    }

    @Test
    func missingCodexAppGetsItsOwnAlertInsteadOfAGenericError() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(CodexAppNotFoundError())

        #expect(step == .showCodexAppNotFound)
    }

    @Test
    func expiredSignInCodeOffersRetry() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            IsolatedCodexLoginError.authCaptureTimedOut
        )

        #expect(step == .offerSignInRetry(outcome: .expiredCode))
    }

    @Test
    func promptUnavailablePreservesSanitizedFailureReason() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            IsolatedCodexLoginError.promptUnavailable(reason: "error sending request")
        )

        #expect(step == .showSignInFailure(.promptUnavailable(reason: "error sending request")))
    }

    @Test
    func authCaptureFailureMapsToAccountSignInOutcome() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            IsolatedCodexLoginError.authCaptureFailed
        )

        #expect(step == .showSignInFailure(.captureFailed))
    }

    @Test
    func loginVerificationFailureMapsToAccountSignInOutcome() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            IsolatedCodexLoginError.loginStatusVerificationFailed
        )

        #expect(step == .showSignInFailure(.verificationFailed))
    }

    @Test
    func liveAuthMutationRoutesToUnsafeAuthChangeStep() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            AddAccountWorkflowError.liveAuthChanged
        )

        #expect(step == .showUnsafeAuthChange)
    }

    @Test
    func catalogSaveFailureRoutesToSaveFailureStep() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            AddAccountWorkflowError.catalogSaveFailed
        )

        #expect(step == .showSaveFailure)
    }

    @Test
    func duplicateCapturedIdentityRoutesToAlreadySavedStep() {
        let savedID = UUID()
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            AddAccountWorkflowError.accountAlreadySaved(savedID)
        )

        #expect(step == .showAccountAlreadySaved(accountID: savedID))
    }
}
