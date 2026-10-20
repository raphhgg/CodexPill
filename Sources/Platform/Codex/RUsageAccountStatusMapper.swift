import Foundation

struct RUsageAccountStatusMapper {
    func status(from appServerStatus: CodexAppServerStatus) -> CodexAccountStatus {
        CodexAccountStatus(
            email: appServerStatus.account.email,
            planType: appServerStatus.account.planType,
            usage: appServerStatus.rateLimits.map(usage),
            stableAccountID: appServerStatus.account.stableAccountID,
            authPrincipalIdentity: appServerStatus.account.authPrincipalIdentity,
            workspaceIdentity: appServerStatus.account.workspaceIdentity,
            snapshotFingerprint: appServerStatus.account.snapshotFingerprint
        )
    }

    func usage(from appServerRateLimits: CodexAppServerRateLimits) -> UsageSnapshot {
        var usage = UsageSnapshot.codex(
            planName: appServerRateLimits.planType,
            primary: appServerRateLimits.primary.map(reportedWindow),
            secondary: appServerRateLimits.secondary.map(reportedWindow),
            fetchedAt: appServerRateLimits.fetchedAt
        )
        usage.resetCredits = appServerRateLimits.resetCredits
        usage.credits = appServerRateLimits.credits
        return usage
    }

    private func reportedWindow(from window: CodexAppServerRateLimitWindow) -> UsageSnapshot.CodexReportedWindow {
        (window.usedPercent, window.resetsAt, window.windowDurationMinutes)
    }
}
