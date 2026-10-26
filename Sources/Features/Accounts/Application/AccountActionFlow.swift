import Foundation

/// Turns a Codex sign-in's outcome into the next step the menu presents, without AppKit.
struct AccountActionFlow {
    enum SignInResult {
        case completed(CodexSignedInAccount)
        case failed(Error)
        case cancelled
    }

    enum SignInCompletionStep {
        case confirmReplace(CodexSignedInAccount)
        case handleFailure(SignInFailureStep)
        case none
    }

    enum SignInFailureOutcome: Equatable {
        case promptUnavailable(reason: String?)
        case expiredCode
        case captureFailed
        case verificationFailed
    }

    enum SignInFailureStep: Equatable {
        case showSignInFailure(SignInFailureOutcome)
        case offerSignInRetry(outcome: SignInFailureOutcome)
        case showError(message: String)
        case showCodexAppNotFound
        case showUnsafeAuthChange
        case showAccountAlreadyInUse
    }

    func resolveSignInCompletion(_ result: SignInResult) -> SignInCompletionStep {
        switch result {
        case .completed(let signedIn):
            return .confirmReplace(signedIn)
        case .failed(let error):
            if error is CancellationError {
                return .none
            }
            return .handleFailure(resolveSignInFailure(error))
        case .cancelled:
            return .none
        }
    }

    func resolveSignInFailure(_ error: Error) -> SignInFailureStep {
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

        if let workflowError = error as? CodexSignInWorkflowError {
            switch workflowError {
            case .liveAuthChanged:
                return .showUnsafeAuthChange
            case .accountAlreadyInUse:
                return .showAccountAlreadyInUse
            }
        }

        if error is CodexAppNotFoundError {
            return .showCodexAppNotFound
        }

        return .showError(message: error.localizedDescription)
    }
}
