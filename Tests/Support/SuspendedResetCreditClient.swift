import Foundation

@testable import RUsage

/// Holds each reset-credit call until the test answers it.
actor SuspendedResetCreditClient: CodexResetCreditClient {
    private var pendingCall: CheckedContinuation<CodexResetCreditOutcome, Never>?
    private var callStarted: CheckedContinuation<Void, Never>?

    func consumeResetCredit(idempotencyKey: UUID) async throws -> CodexResetCreditOutcome {
        await withCheckedContinuation { continuation in
            pendingCall = continuation
            callStarted?.resume()
            callStarted = nil
        }
    }

    func waitUntilCalled() async {
        guard pendingCall == nil else { return }
        await withCheckedContinuation { callStarted = $0 }
    }

    func answer(_ outcome: CodexResetCreditOutcome) {
        pendingCall?.resume(returning: outcome)
        pendingCall = nil
    }
}
