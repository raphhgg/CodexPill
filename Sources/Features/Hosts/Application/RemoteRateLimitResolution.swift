import Foundation

struct RemoteRateLimitResolution {
    func preferredRateLimits(
        remote: UsageSnapshot?,
        fallback: UsageSnapshot?,
        candidateAccounts: [CodexAccount],
        baseAccount: CodexAccount,
        remoteEmail: String?
    ) -> UsageSnapshot? {
        let resolvedFallback = bestFallback(
            fallback: fallback,
            candidateAccounts: candidateAccounts,
            baseAccount: baseAccount,
            remoteEmail: remoteEmail
        )

        guard let remote else { return resolvedFallback }
        guard let resolvedFallback else { return remote }

        return UsageSnapshot(
            provider: remote.provider,
            planName: preferredMetadataValue(remote.planName, fallback: resolvedFallback.planName),
            windows: [UsageWindowKind.session, .weekly].compactMap { kind in
                preferredWindow(remote.window(kind), fallback: resolvedFallback.window(kind))
            },
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
        fallback: UsageSnapshot?,
        candidateAccounts: [CodexAccount],
        baseAccount: CodexAccount,
        remoteEmail: String?
    ) -> UsageSnapshot? {
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
           containsMeaningfulData(matchedAccount.usage) {
            return matchedAccount.usage
        }

        return fallback
    }

    private func containsMeaningfulData(_ snapshot: UsageSnapshot?) -> Bool {
        guard let snapshot else { return false }
        return snapshot.windows.contains(where: windowContainsMeaningfulData)
    }

    private func windowContainsMeaningfulData(_ window: UsageWindow) -> Bool {
        if let resetsAt = window.resetsAt {
            guard resetsAt > .now else { return false }
            return true
        }
        return window.usedPercent > 0
    }

    private func preferredWindow(
        _ remote: UsageWindow?,
        fallback: UsageWindow?
    ) -> UsageWindow? {
        guard let remote else { return fallback }
        guard let fallback else { return remote }

        if windowContainsMeaningfulData(remote) {
            return UsageWindow(
                kind: remote.kind,
                usedPercent: remote.usedPercent,
                resetsAt: remote.resetsAt ?? fallback.resetsAt,
                durationMinutes: remote.durationMinutes ?? fallback.durationMinutes
            )
        }
        return fallback
    }
}
