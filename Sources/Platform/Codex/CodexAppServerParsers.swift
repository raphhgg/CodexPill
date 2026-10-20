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
        UsageResetCredits(
            availableCount: max(summary.availableCount, 0),
            credits: summary.credits.map { credits in
                credits
                    .filter { $0.status == "available" }
                    .map { UsageResetCredit(expiresAt: $0.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }) }
            }
        )
    }

    private func parseSnapshot(_ snapshot: RateLimitSnapshot, fetchedAt: Date) -> CodexAppServerRateLimits {
        CodexAppServerRateLimits(
            limitID: snapshot.limitId,
            limitName: snapshot.limitName,
            planType: snapshot.planType,
            primary: snapshot.primary.flatMap(parseWindow),
            secondary: snapshot.secondary.flatMap(parseWindow),
            credits: snapshot.credits.flatMap(parseCredits),
            fetchedAt: fetchedAt
        )
    }

    private func parseCredits(_ credits: CreditsSnapshot) -> UsageCredits? {
        if credits.unlimited == true { return .unlimited }
        guard credits.hasCredits == true,
              let balance = credits.balance.flatMap({ Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) })
        else { return nil }
        return .balance(balance)
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
    var credits: CreditsSnapshot? = nil
}

extension RateLimitSnapshot {
    private enum CodingKeys: String, CodingKey {
        case limitId, limitName, planType, primary, secondary, credits
    }

    /// A credits object rusage cannot read leaves the limits readable.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitId = try container.decodeIfPresent(String.self, forKey: .limitId)
        limitName = try container.decodeIfPresent(String.self, forKey: .limitName)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        primary = try container.decodeIfPresent(RateLimitWindow.self, forKey: .primary)
        secondary = try container.decodeIfPresent(RateLimitWindow.self, forKey: .secondary)
        credits = try? container.decodeIfPresent(CreditsSnapshot.self, forKey: .credits)
    }
}

/// The balance is a decimal string, such as "62498.0761312500".
struct CreditsSnapshot: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?
}

struct RateLimitWindow: Decodable {
    let usedPercent: Int?
    let resetsAt: Int?
    let windowDurationMins: Int?
}
