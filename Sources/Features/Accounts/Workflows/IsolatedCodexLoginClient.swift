import Foundation

struct IsolatedCodexLoginPrompt: Equatable {
    let url: URL
    let userCode: String
}

protocol IsolatedCodexLoginSession: AnyObject, Sendable {
    var prompt: IsolatedCodexLoginPrompt { get }
    var codexHome: URL { get }
    func waitForAuthData() async throws -> Data
    func verifyLoginStatus() async -> Bool
    func cancel()
    func cleanup()
}

protocol IsolatedCodexLoginClient: Sendable {
    func startLogin() async throws -> IsolatedCodexLoginSession
}

enum IsolatedCodexLoginError: LocalizedError {
    case promptUnavailable(reason: String?)
    case authCaptureFailed
    case authCaptureTimedOut
    case loginStatusVerificationFailed

    var errorDescription: String? {
        switch self {
        case .promptUnavailable(let reason):
            if let reason, !reason.isEmpty {
                "Codex could not start a sign-in session. \(reason)"
            } else {
                "Codex could not start a sign-in session."
            }
        case .authCaptureFailed:
            "The Codex sign-in did not complete."
        case .authCaptureTimedOut:
            "The Codex sign-in code expired before the account was added."
        case .loginStatusVerificationFailed:
            "CodexPill could not verify the signed-in account."
        }
    }
}
