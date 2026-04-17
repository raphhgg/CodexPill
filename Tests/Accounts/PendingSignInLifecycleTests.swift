import Foundation
import Testing

@testable import CodexPill

@MainActor
struct PendingSignInLifecycleTests {
    @Test
    func beginCompletionSkipsWhenNoPendingSignInExists() {
        let lifecycle = PendingSignInLifecycle()

        #expect(lifecycle.beginCompletion(activeAccountID: nil) == .skip)
        #expect(!lifecycle.hasPendingSignIn)
        #expect(!lifecycle.isCompleting)
    }

    @Test
    func beginCompletionClearsPendingSignInWhenActiveAccountAlreadyExists() {
        let lifecycle = PendingSignInLifecycle()
        lifecycle.recordPreparedSignIn(named: "Business 4")

        let decision = lifecycle.beginCompletion(activeAccountID: UUID())

        #expect(decision == .clearPending)
        #expect(!lifecycle.hasPendingSignIn)
        #expect(!lifecycle.isCompleting)
    }

    @Test
    func beginCompletionReturnsPendingNameAndMarksCompletionInFlight() {
        let lifecycle = PendingSignInLifecycle()
        lifecycle.recordPreparedSignIn(named: "Business 4")

        let decision = lifecycle.beginCompletion(activeAccountID: nil)

        #expect(decision == .complete(pendingAccountName: "Business 4"))
        #expect(lifecycle.hasPendingSignIn)
        #expect(lifecycle.isCompleting)
    }

    @Test
    func finishCompletionEitherKeepsOrConsumesPendingSignIn() {
        let lifecycle = PendingSignInLifecycle()
        lifecycle.recordPreparedSignIn(named: "Business 4")

        _ = lifecycle.beginCompletion(activeAccountID: nil)
        lifecycle.finishCompletion(consumedPendingSignIn: false)
        #expect(lifecycle.hasPendingSignIn)
        #expect(!lifecycle.isCompleting)

        _ = lifecycle.beginCompletion(activeAccountID: nil)
        lifecycle.finishCompletion(consumedPendingSignIn: true)
        #expect(!lifecycle.hasPendingSignIn)
        #expect(!lifecycle.isCompleting)
    }

    @Test
    func metadataHydrationStaysBlockedWhilePendingSignInExists() {
        let lifecycle = PendingSignInLifecycle()

        #expect(lifecycle.canHydrateSavedAccountsMetadata(isBusy: false, isHydratingSavedAccountsMetadata: false))

        lifecycle.recordPreparedSignIn(named: "Business 4")

        #expect(!lifecycle.canHydrateSavedAccountsMetadata(isBusy: false, isHydratingSavedAccountsMetadata: false))
        #expect(!lifecycle.canHydrateSavedAccountsMetadata(isBusy: true, isHydratingSavedAccountsMetadata: false))
        #expect(!lifecycle.canHydrateSavedAccountsMetadata(isBusy: false, isHydratingSavedAccountsMetadata: true))
    }
}
