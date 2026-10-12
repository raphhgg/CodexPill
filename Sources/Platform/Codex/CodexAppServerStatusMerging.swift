import Foundation

func appServerStatusNeedsRetry(_ status: CodexAccountStatus?) -> Bool {
    guard let status else { return true }
    guard status.email != nil else { return true }
    return !appServerUsageIsComplete(status.usage)
}

func appServerUsageIsComplete(_ usage: UsageSnapshot?) -> Bool {
    guard let usage else { return false }
    return usage.window(.session) != nil && usage.window(.weekly) != nil
}

func appServerUsageHasUsableWindow(_ usage: UsageSnapshot?) -> Bool {
    guard let usage else { return false }
    return !usage.windows.isEmpty
}

func appServerUsageLooksSuspiciouslyZeroed(_ usage: UsageSnapshot?) -> Bool {
    guard let usage else { return false }
    return appServerUsageWindowLooksSuspiciouslyZeroed(usage.window(.session))
        && appServerUsageWindowLooksSuspiciouslyZeroed(usage.window(.weekly))
}

private func appServerUsageWindowLooksSuspiciouslyZeroed(_ window: UsageWindow?) -> Bool {
    guard let window, window.usedPercent == 0, let resetsAt = window.resetsAt else { return false }
    return resetsAt > .now
}

func mergeAppServerStatuses(previous: CodexAccountStatus?, current: CodexAccountStatus) -> CodexAccountStatus {
    CodexAccountStatus(
        email: current.email ?? previous?.email,
        planType: current.planType ?? previous?.planType,
        usage: mergeAppServerUsage(previous: previous?.usage, current: current.usage),
        stableAccountID: current.stableAccountID ?? previous?.stableAccountID,
        authPrincipalIdentity: current.authPrincipalIdentity ?? previous?.authPrincipalIdentity,
        workspaceIdentity: current.workspaceIdentity ?? previous?.workspaceIdentity,
        snapshotFingerprint: current.snapshotFingerprint ?? previous?.snapshotFingerprint
    )
}

func mergeAppServerUsage(
    previous: UsageSnapshot?,
    current: UsageSnapshot?
) -> UsageSnapshot? {
    guard let current else { return previous }
    guard let previous else { return current }

    return UsageSnapshot(
        provider: current.provider,
        planName: current.planName ?? previous.planName,
        windows: [UsageWindowKind.session, .weekly].compactMap { kind in
            mergeAppServerUsageWindow(previous: previous.window(kind), current: current.window(kind))
        },
        fetchedAt: max(previous.fetchedAt, current.fetchedAt),
        resetCredits: current.resetCredits ?? previous.resetCredits
    )
}

private func mergeAppServerUsageWindow(
    previous: UsageWindow?,
    current: UsageWindow?
) -> UsageWindow? {
    guard let current else { return previous }
    guard let previous else { return current }

    return UsageWindow(
        kind: current.kind,
        usedPercent: current.usedPercent,
        resetsAt: current.resetsAt ?? previous.resetsAt,
        durationMinutes: current.durationMinutes ?? previous.durationMinutes
    )
}
