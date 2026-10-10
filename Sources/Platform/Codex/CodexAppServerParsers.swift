import Foundation

struct CodexAppServerAccountParser {
    func parse(_ response: AppServerAccountResponse) -> CodexAppServerAccount? {
        guard let account = response.account else { return nil }
        return CodexAppServerAccount(
            email: account.email,
            planType: account.planType,
            stableAccountID: account.stableAccountID,
            authPrincipalIdentity: account.authPrincipalIdentity,
            workspaceIdentity: account.workspaceIdentity,
            snapshotFingerprint: account.snapshotFingerprint
        )
    }
}

struct CodexAppServerRateLimitParser {
    func parse(_ response: AppServerRateLimitsResponse, fetchedAt: Date = Date()) -> CodexAppServerRateLimits? {
        var rateLimits: CodexAppServerRateLimits?
        if let codex = response.rateLimitsByLimitId?["codex"].flatMap({ parseSnapshot($0, fetchedAt: fetchedAt) }),
           codex.isComplete {
            rateLimits = codex
        } else {
            rateLimits = response.rateLimits.flatMap { parseSnapshot($0, fetchedAt: fetchedAt) }
        }
        rateLimits?.resetCredits = response.rateLimitResetCredits.map(parseResetCredits)
        return rateLimits
    }

    /// Codex may list fewer credits than `availableCount`, or none at all when it only knows the count.
    private func parseResetCredits(_ summary: RateLimitResetCreditsSummary) -> UsageResetCredits {
        let nextExpiry = (summary.credits ?? [])
            .filter { $0.status == "available" }
            .compactMap(\.expiresAt)
            .min()
        return UsageResetCredits(
            availableCount: max(summary.availableCount, 0),
            nextExpiry: nextExpiry.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private func parseSnapshot(_ snapshot: RateLimitSnapshot, fetchedAt: Date) -> CodexAppServerRateLimits {
        CodexAppServerRateLimits(
            limitID: snapshot.limitId,
            limitName: snapshot.limitName,
            planType: snapshot.planType,
            primary: snapshot.primary.flatMap(parseWindow),
            secondary: snapshot.secondary.flatMap(parseWindow),
            fetchedAt: fetchedAt
        )
    }

    private func parseWindow(_ window: RateLimitWindow) -> CodexAppServerRateLimitWindow? {
        guard let usedPercent = window.usedPercent else { return nil }
        return CodexAppServerRateLimitWindow(
            usedPercent: usedPercent,
            resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            windowDurationMinutes: window.windowDurationMins
        )
    }
}

extension CodexAppServerRateLimits {
    var isComplete: Bool {
        primary != nil && secondary != nil
    }
}

struct AppServerAccountResponse: Decodable {
    let account: Account?

    struct Account: Decodable {
        let email: String?
        let planType: String?
        let stableAccountID: String?
        let authPrincipalIdentity: CodexAuthPrincipalIdentity?
        let workspaceIdentity: CodexWorkspaceIdentity?
        let snapshotFingerprint: String?
    }
}

struct AppServerRateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    /// Absent before Codex added reset credits.
    let rateLimitResetCredits: RateLimitResetCreditsSummary?

    init(
        rateLimits: RateLimitSnapshot?,
        rateLimitsByLimitId: [String: RateLimitSnapshot]? = nil,
        rateLimitResetCredits: RateLimitResetCreditsSummary? = nil
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
        self.rateLimitResetCredits = rateLimitResetCredits
    }
}

struct RateLimitResetCreditsSummary: Decodable {
    let availableCount: Int
    let credits: [RateLimitResetCredit]?
}

/// Status stays a string so a status added by a later Codex does not fail the whole rate-limit read.
struct RateLimitResetCredit: Decodable {
    let status: String?
    let expiresAt: Int?
}

struct RateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

struct RateLimitWindow: Decodable {
    let usedPercent: Int?
    let resetsAt: Int?
    let windowDurationMins: Int?
}
