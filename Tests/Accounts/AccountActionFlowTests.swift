import Foundation
import Testing

@testable import CodexPill

struct AccountActionFlowTests {
    @Test
    func completedAddAccountOffersOptionalLocalSwitch() throws {
        let account = makeAccount(name: "Business 2")

        let step = AccountActionFlow().resolveAddAccountCompletion(
            .completed(account),
            retryName: "Business 2"
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
    func expiredSignInCodeOffersRetryWithOriginalName() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            IsolatedCodexLoginError.authCaptureTimedOut,
            retryName: "Business 2"
        )

        #expect(step == .offerExpiredCodeRetry(retryName: "Business 2"))
    }

    @Test
    func duplicateDisplayNameOffersNameRecovery() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            AccountDisplayNameError.duplicateAccountName,
            retryName: "Business 2"
        )

        #expect(step == .offerDuplicateNameRecovery)
    }

    @Test
    func liveAuthMutationRoutesToUnsafeAuthChangeStep() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            AddAccountWorkflowError.liveAuthChanged,
            retryName: "Business 2"
        )

        #expect(step == .showUnsafeAuthChange)
    }

    @Test
    func catalogSaveFailureRoutesToSaveFailureStep() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            AddAccountWorkflowError.catalogSaveFailed,
            retryName: "Business 2"
        )

        #expect(step == .showSaveFailure)
    }

    @Test
    func duplicateCapturedIdentityRoutesToAlreadySavedStep() {
        let step = AccountActionFlow().resolveAddAccountStartFailure(
            AddAccountWorkflowError.accountAlreadySaved("Business 1"),
            retryName: "Business 2"
        )

        #expect(step == .showAccountAlreadySaved(accountName: "Business 1"))
    }

    private func makeAccount(name: String) -> CodexAccount {
        let id = UUID()
        return CodexAccount(
            id: id,
            name: name,
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(snapshotFingerprint: "fingerprint-\(name)")
        )
    }
}
