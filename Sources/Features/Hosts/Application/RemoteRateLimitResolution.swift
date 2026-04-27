import Foundation

struct RemoteRateLimitResolution {
    func preferredRateLimits(
        remote: CodexRateLimitSnapshot?,
        fallback: CodexRateLimitSnapshot?,
        candidateAccounts: [CodexAccount],
        baseAccount: CodexAccount,
        remoteEmail: String?
    ) -> CodexRateLimitSnapshot? {
        let resolvedFallback = bestFallback(
            fallback: fallback,
            candidateAccounts: candidateAccounts,
            baseAccount: baseAccount,
            remoteEmail: remoteEmail
        )

        guard let remote else { return resolvedFallback }
        guard let resolvedFallback else { return remote }

        return CodexRateLimitSnapshot(
            limitID: preferredMetadataValue(remote.limitID, fallback: resolvedFallback.limitID),
            limitName: preferredMetadataValue(remote.limitName, fallback: resolvedFallback.limitName),
            planType: preferredMetadataValue(remote.planType, fallback: resolvedFallback.planType),
            primary: preferredWindow(remote.primary, fallback: resolvedFallback.primary),
            secondary: preferredWindow(remote.secondary, fallback: resolvedFallback.secondary),
            fetchedAt: max(remote.fetchedAt, resolvedFallback.fetchedAt)
        )
    }

    private func preferredMetadataValue(
        _ remote: String?,
        fallback: String?
    ) -> String? {
        let trimmedRemote = remote?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedRemote, !trimmedRemote.isEmpty {
            return trimmedRemote
        }
        return fallback
    }

    private func bestFallback(
        fallback: CodexRateLimitSnapshot?,
        candidateAccounts: [CodexAccount],
        baseAccount: CodexAccount,
        remoteEmail: String?
    ) -> CodexRateLimitSnapshot? {
        let matchOutcome = CodexAccountMatcher().match(
            liveStableAccountID: baseAccount.identity.stableAccountID,
            liveAuthPrincipalIdentity: baseAccount.identity.authPrincipalIdentity,
            liveWorkspaceIdentity: baseAccount.identity.workspaceIdentity,
            liveAuthFingerprint: baseAccount.identity.snapshotFingerprint,
            liveRemoteIdentity: CodexRemoteAccountIdentity(emailAddress: remoteEmail) ?? baseAccount.resolvedRemoteIdentity,
            accounts: candidateAccounts
        )

        if let matchedID = matchOutcome.matchedAccountID,
           let matchedAccount = candidateAccounts.first(where: { $0.id == matchedID }),
           containsMeaningfulData(matchedAccount.rateLimits) {
            return matchedAccount.rateLimits
        }

        return fallback
    }

    private func containsMeaningfulData(_ snapshot: CodexRateLimitSnapshot?) -> Bool {
        guard let snapshot else { return false }
        return windowContainsMeaningfulData(snapshot.primary)
            || windowContainsMeaningfulData(snapshot.secondary)
    }

    private func windowContainsMeaningfulData(_ window: CodexRateLimitWindow?) -> Bool {
        guard let window else { return false }
        if let resetsAt = window.resetsAt {
            guard resetsAt > .now else { return false }
            return true
        }
        return window.usedPercent > 0
    }

    private func preferredWindow(
        _ remote: CodexRateLimitWindow?,
        fallback: CodexRateLimitWindow?
    ) -> CodexRateLimitWindow? {
        guard let remote else { return fallback }
        guard let fallback else { return remote }

        if windowContainsMeaningfulData(remote) {
            return CodexRateLimitWindow(
                usedPercent: remote.usedPercent,
                resetsAt: remote.resetsAt ?? fallback.resetsAt,
                windowDurationMinutes: remote.windowDurationMinutes ?? fallback.windowDurationMinutes
            )
        }
        return fallback
    }
}
