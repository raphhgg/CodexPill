import Foundation

final class PendingSignInLifecycle {
    enum CompletionDecision: Equatable {
        case skip
        case clearPending
        case complete(pendingAccountName: String)
    }

    private(set) var pendingAccountName: String?
    private(set) var isCompleting = false

    var hasPendingSignIn: Bool {
        pendingAccountName != nil
    }

    func recordPreparedSignIn(named pendingAccountName: String?) {
        self.pendingAccountName = pendingAccountName
    }

    func beginCompletion(activeAccountID: UUID?) -> CompletionDecision {
        guard let pendingAccountName else { return .skip }
        guard !isCompleting else { return .skip }
        guard activeAccountID == nil else {
            self.pendingAccountName = nil
            return .clearPending
        }

        isCompleting = true
        return .complete(pendingAccountName: pendingAccountName)
    }

    func finishCompletion(consumedPendingSignIn: Bool) {
        if consumedPendingSignIn {
            pendingAccountName = nil
        }
        isCompleting = false
    }

    func canHydrateSavedAccountsMetadata(isBusy: Bool, isHydratingSavedAccountsMetadata: Bool) -> Bool {
        !isBusy && !isHydratingSavedAccountsMetadata && !hasPendingSignIn
    }
}
