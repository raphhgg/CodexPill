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
    var fetchedAt: Date
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
