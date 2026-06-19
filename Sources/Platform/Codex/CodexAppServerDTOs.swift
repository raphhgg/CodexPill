import Foundation

struct CodexAppServerAccount: Equatable {
    var email: String?
    var planType: String?
    var stableAccountID: String?
    var authPrincipalIdentity: CodexAuthPrincipalIdentity?
    var workspaceIdentity: CodexWorkspaceIdentity?
    var snapshotFingerprint: String?
}

struct CodexAppServerRateLimits: Equatable {
    var limitID: String?
    var limitName: String?
    var planType: String?
    var primary: CodexAppServerRateLimitWindow?
    var secondary: CodexAppServerRateLimitWindow?
    var usageResetsAvailableCount: Int?
    var fetchedAt: Date

    init(
        limitID: String?,
        limitName: String?,
        planType: String?,
        primary: CodexAppServerRateLimitWindow?,
        secondary: CodexAppServerRateLimitWindow?,
        usageResetsAvailableCount: Int? = nil,
        fetchedAt: Date
    ) {
        self.limitID = limitID
        self.limitName = limitName
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.usageResetsAvailableCount = Self.normalizedUsageResetsAvailableCount(usageResetsAvailableCount)
        self.fetchedAt = fetchedAt
    }

    private static func normalizedUsageResetsAvailableCount(_ count: Int?) -> Int? {
        guard let count, count > 0 else { return nil }
        return count
    }
}

struct CodexAppServerRateLimitWindow: Equatable {
    var usedPercent: Int
    var resetsAt: Date?
    var windowDurationMinutes: Int?
}

struct CodexAppServerStatus: Equatable {
    var account: CodexAppServerAccount
    var rateLimits: CodexAppServerRateLimits?

    var email: String? { account.email }
    var planType: String? { account.planType }
}
