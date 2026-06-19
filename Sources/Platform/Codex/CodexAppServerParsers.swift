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
        let usageResetsAvailableCount = normalizedUsageResetsAvailableCount(
            response.rateLimitResetCredits?.availableCount
        )
        if let codex = response.rateLimitsByLimitId?["codex"].flatMap({
            parseSnapshot($0, usageResetsAvailableCount: usageResetsAvailableCount, fetchedAt: fetchedAt)
        }),
           codex.isComplete {
            return codex
        }
        return response.rateLimits.flatMap {
            parseSnapshot($0, usageResetsAvailableCount: usageResetsAvailableCount, fetchedAt: fetchedAt)
        }
    }

    private func parseSnapshot(
        _ snapshot: RateLimitSnapshot,
        usageResetsAvailableCount: Int?,
        fetchedAt: Date
    ) -> CodexAppServerRateLimits {
        CodexAppServerRateLimits(
            limitID: snapshot.limitId,
            limitName: snapshot.limitName,
            planType: snapshot.planType,
            primary: snapshot.primary.flatMap(parseWindow),
            secondary: snapshot.secondary.flatMap(parseWindow),
            usageResetsAvailableCount: usageResetsAvailableCount,
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

    private func normalizedUsageResetsAvailableCount(_ count: Int?) -> Int? {
        guard let count, count > 0 else { return nil }
        return count
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
    let rateLimitResetCredits: RateLimitResetCredits?

    init(
        rateLimits: RateLimitSnapshot?,
        rateLimitsByLimitId: [String: RateLimitSnapshot]? = nil,
        rateLimitResetCredits: RateLimitResetCredits? = nil
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
        self.rateLimitResetCredits = rateLimitResetCredits
    }
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

struct RateLimitResetCredits: Decodable {
    let availableCount: Int?
}
