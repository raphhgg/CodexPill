import Foundation

/// The result of using one Codex reset credit, as the menu reports it.
enum ResetCreditResult: Equatable {
    case reset
    case nothingToReset
    case noCredit
    /// Codex answered with an outcome this version does not know.
    case unconfirmed
    /// Codex could not be reached. Trying again reuses the same attempt.
    case failed

    init(_ outcome: CodexResetCreditOutcome) {
        switch outcome {
        case .reset, .alreadyRedeemed:
            self = .reset
        case .nothingToReset:
            self = .nothingToReset
        case .noCredit:
            self = .noCredit
        case .unrecognized:
            self = .unconfirmed
        }
    }

    var message: String {
        switch self {
        case .reset:
            "Your Codex limits are reset."
        case .nothingToReset:
            "Nothing to reset right now. Your reset is still available."
        case .noCredit:
            "No resets left on this account."
        case .unconfirmed:
            "Codex didn't confirm the reset. Check your limits before trying again."
        case .failed:
            "Couldn't use a reset. Try again."
        }
    }
}
