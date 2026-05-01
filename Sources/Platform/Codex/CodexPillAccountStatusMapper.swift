import Foundation

struct CodexPillAccountStatusMapper {
    func status(from appServerStatus: CodexAppServerStatus) -> CodexAccountStatus {
        CodexAccountStatus(
            email: appServerStatus.account.email,
            planType: appServerStatus.account.planType,
            rateLimits: appServerStatus.rateLimits.map(rateLimitSnapshot),
            stableAccountID: appServerStatus.account.stableAccountID,
            authPrincipalIdentity: appServerStatus.account.authPrincipalIdentity,
            workspaceIdentity: appServerStatus.account.workspaceIdentity,
            snapshotFingerprint: appServerStatus.account.snapshotFingerprint
        )
    }

    func rateLimitSnapshot(from appServerRateLimits: CodexAppServerRateLimits) -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            limitID: appServerRateLimits.limitID,
            limitName: appServerRateLimits.limitName,
            planType: appServerRateLimits.planType,
            primary: appServerRateLimits.primary.map(rateLimitWindow),
            secondary: appServerRateLimits.secondary.map(rateLimitWindow),
            fetchedAt: appServerRateLimits.fetchedAt
        )
    }

    private func rateLimitWindow(from window: CodexAppServerRateLimitWindow) -> CodexRateLimitWindow {
        CodexRateLimitWindow(
            usedPercent: window.usedPercent,
            resetsAt: window.resetsAt,
            windowDurationMinutes: window.windowDurationMinutes
        )
    }
}
