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
        case offerSignInRetry(outcome: AddAccountSignInFailureOutcome)
        case showError(message: String)
        case showCodexAppNotFound
        case showUnsafeAuthChange
        case showSaveFailure
        case showAccountAlreadySaved(accountID: UUID)
    }

    enum AddAccountConfirmationStep: Equatable {
        case switchLocally(CodexAccount)
        case none
    }

    func resolveAddAccountCompletion(_ result: AddAccountResult) -> AddAccountCompletionStep {
        switch result {
        case .completed(let account):
            return .offerLocalSwitch(account)
        case .failed(let error):
            if error is CancellationError {
                return .none
            }
            return .handleFailure(resolveAddAccountFailure(error))
        case .cancelled:
            return .none
        }
    }

    func resolveAddAccountStartFailure(_ error: Error) -> AddAccountFailureStep {
        resolveAddAccountFailure(error)
    }

    func resolveAddAccountSuccessConfirmation(account: CodexAccount, accepted: Bool) -> AddAccountConfirmationStep {
        accepted ? .switchLocally(account) : .none
    }

    private func resolveAddAccountFailure(_ error: Error) -> AddAccountFailureStep {
        if let loginError = error as? IsolatedCodexLoginError {
            switch loginError {
            case .promptUnavailable(let reason):
                return .showSignInFailure(.promptUnavailable(reason: reason))
            case .authCaptureTimedOut:
                return .offerSignInRetry(outcome: .expiredCode)
            case .authCaptureFailed:
                return .showSignInFailure(.captureFailed)
            case .loginStatusVerificationFailed:
                return .showSignInFailure(.verificationFailed)
            }
        }

        if let workflowError = error as? AddAccountWorkflowError {
            switch workflowError {
            case .liveAuthChanged:
                return .showUnsafeAuthChange
            case .catalogSaveFailed:
                return .showSaveFailure
            case .accountAlreadySaved(let accountID):
                return .showAccountAlreadySaved(accountID: accountID)
            }
        }

        if error is CodexAppNotFoundError {
            return .showCodexAppNotFound
        }

        return .showError(message: error.localizedDescription)
    }
}
