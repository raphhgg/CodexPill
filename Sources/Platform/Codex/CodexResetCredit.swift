import Foundation

/// What Codex answered to `account/rateLimitResetCredit/consume`.
enum CodexResetCreditOutcome: String, Equatable, Sendable {
    /// One credit was spent and the current limits were reset.
    case reset
    /// No current limit can be reset, so no credit was spent.
    case nothingToReset
    /// The account has no reset credit left.
    case noCredit
    /// An earlier try with the same idempotency key already reset the limits.
    case alreadyRedeemed
    /// An outcome added by a later Codex version.
    case unrecognized
}

/// Spends reset credits for the live account the local Codex app-server runs as.
protocol CodexResetCreditClient: Sendable {
    /// Reuse the same `idempotencyKey` when retrying one attempt, so a lost response cannot spend two credits.
    func consumeResetCredit(idempotencyKey: UUID) async throws -> CodexResetCreditOutcome
}

struct CodexResetCreditConsumeCommand {
    let executableURL: URL?
    let arguments: [String]
    let environment: [String: String]?
    let timeout: Duration
    let clientInfo: CodexAppServerClientInfo
    let idempotencyKey: UUID
    let failure: @Sendable (_ stderr: String?, _ terminationStatus: Int?, _ timedOut: Bool) -> Error
}

struct AppServerResetCreditConsumeResponse: Decodable {
    let outcome: String
}

struct UnavailableResetCreditClient: CodexResetCreditClient {
    func consumeResetCredit(idempotencyKey: UUID) async throws -> CodexResetCreditOutcome {
        throw CodexAppServerError.server("Reset credits are unavailable.")
    }
}
