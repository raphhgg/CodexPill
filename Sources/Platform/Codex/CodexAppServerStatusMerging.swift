import Foundation

func appServerStatusNeedsRetry(_ status: CodexAccountStatus?) -> Bool {
    guard let status else { return true }
    guard status.email != nil else { return true }
    return !appServerRateLimitsAreComplete(status.rateLimits)
}

func appServerRateLimitsAreComplete(_ snapshot: CodexRateLimitSnapshot?) -> Bool {
    guard let snapshot else { return false }
    return snapshot.primary != nil && snapshot.secondary != nil
}

func appServerRateLimitsLookSuspiciouslyZeroed(_ snapshot: CodexRateLimitSnapshot?) -> Bool {
    guard let snapshot else { return false }
    return appServerRateLimitWindowLooksSuspiciouslyZeroed(snapshot.primary)
        && appServerRateLimitWindowLooksSuspiciouslyZeroed(snapshot.secondary)
}

func appServerRateLimitWindowLooksSuspiciouslyZeroed(_ window: CodexRateLimitWindow?) -> Bool {
    guard let window, window.usedPercent == 0, let resetsAt = window.resetsAt else { return false }
    return resetsAt > .now
}

func mergeAppServerStatuses(previous: CodexAccountStatus?, current: CodexAccountStatus) -> CodexAccountStatus {
    CodexAccountStatus(
        email: current.email ?? previous?.email,
        planType: current.planType ?? previous?.planType,
        rateLimits: mergeAppServerRateLimits(previous: previous?.rateLimits, current: current.rateLimits),
        stableAccountID: current.stableAccountID ?? previous?.stableAccountID,
        authPrincipalIdentity: current.authPrincipalIdentity ?? previous?.authPrincipalIdentity,
        workspaceIdentity: current.workspaceIdentity ?? previous?.workspaceIdentity,
        snapshotFingerprint: current.snapshotFingerprint ?? previous?.snapshotFingerprint
    )
}

func mergeAppServerRateLimits(
    previous: CodexRateLimitSnapshot?,
    current: CodexRateLimitSnapshot?
) -> CodexRateLimitSnapshot? {
    guard previous != nil || current != nil else { return nil }
    guard let current else { return previous }
    guard let previous else { return current }

    return CodexRateLimitSnapshot(
        limitID: current.limitID ?? previous.limitID,
        limitName: current.limitName ?? previous.limitName,
        planType: current.planType ?? previous.planType,
        primary: mergeAppServerRateLimitWindow(previous: previous.primary, current: current.primary),
        secondary: mergeAppServerRateLimitWindow(previous: previous.secondary, current: current.secondary),
        fetchedAt: max(previous.fetchedAt, current.fetchedAt)
    )
}

func mergeAppServerRateLimitWindow(
    previous: CodexRateLimitWindow?,
    current: CodexRateLimitWindow?
) -> CodexRateLimitWindow? {
    guard previous != nil || current != nil else { return nil }
    guard let current else { return previous }
    guard let previous else { return current }

    return CodexRateLimitWindow(
        usedPercent: current.usedPercent,
        resetsAt: current.resetsAt ?? previous.resetsAt,
        windowDurationMinutes: current.windowDurationMinutes ?? previous.windowDurationMinutes
    )
}
