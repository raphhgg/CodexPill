import Foundation

struct AccountActionFlow {
    enum AddAccountResult {
        case completed(CodexAccount)
        case failed(Error)
        case cancelled
    }

    enum AddAccountCompletionStep {
        case offerLocalSwitch(CodexAccount)
        case handleFailure(AddAccountFailureStep)
        case none
    }

    enum AddAccountSignInFailureOutcome: Equatable {
        case promptUnavailable(reason: String?)
        case expiredCode
        case captureFailed
        case verificationFailed
    }

    enum AddAccountFailureStep: Equatable {
        case showSignInFailure(AddAccountSignInFailureOutcome)
        case offerSignInRetry(outcome: AddAccountSignInFailureOutcome, retryName: String)
        case showError(message: String)
        case offerDuplicateNameRecovery
        case showUnsafeAuthChange
        case showSaveFailure
        case showAccountAlreadySaved(accountName: String)
    }

    enum AddAccountConfirmationStep: Equatable {
        case switchLocally(CodexAccount)
        case none
    }

    func resolveAddAccountCompletion(
        _ result: AddAccountResult,
        retryName: String
    ) -> AddAccountCompletionStep {
        switch result {
        case .completed(let account):
            return .offerLocalSwitch(account)
        case .failed(let error):
            if error is CancellationError {
                return .none
            }
            return .handleFailure(resolveAddAccountFailure(error, retryName: retryName))
        case .cancelled:
            return .none
        }
    }

    func resolveAddAccountStartFailure(_ error: Error, retryName: String) -> AddAccountFailureStep {
        resolveAddAccountFailure(error, retryName: retryName)
    }

    func resolveAddAccountSuccessConfirmation(account: CodexAccount, accepted: Bool) -> AddAccountConfirmationStep {
        accepted ? .switchLocally(account) : .none
    }

    private func resolveAddAccountFailure(_ error: Error, retryName: String) -> AddAccountFailureStep {
        if let loginError = error as? IsolatedCodexLoginError {
            switch loginError {
            case .promptUnavailable(let reason):
                return .showSignInFailure(.promptUnavailable(reason: reason))
            case .authCaptureTimedOut:
                return .offerSignInRetry(outcome: .expiredCode, retryName: retryName)
            case .authCaptureFailed:
                return .showSignInFailure(.captureFailed)
            case .loginStatusVerificationFailed:
                return .showSignInFailure(.verificationFailed)
            }
        }

        if let displayNameError = error as? AccountDisplayNameError {
            switch displayNameError {
            case .duplicateAccountName:
                return .offerDuplicateNameRecovery
            case .emptyAccountName:
                return .showError(message: displayNameError.localizedDescription)
            }
        }

        if let workflowError = error as? AddAccountWorkflowError {
            switch workflowError {
            case .liveAuthChanged:
                return .showUnsafeAuthChange
            case .catalogSaveFailed:
                return .showSaveFailure
            case .accountAlreadySaved(let accountName):
                return .showAccountAlreadySaved(accountName: accountName)
            }
        }

        return .showError(message: error.localizedDescription)
    }
}
