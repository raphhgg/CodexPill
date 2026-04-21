import Foundation

struct SavedAccountRelinker {
    private let matcher = CodexAccountMatcher()

    func resolveCanonicalAccount(
        for account: CodexAccount,
        among candidates: [CodexAccount]
    ) -> CodexAccount? {
        if let exactIDMatch = candidates.first(where: { $0.id == account.id }) {
            return exactIDMatch
        }

        let matchOutcome = matcher.match(
            liveStableAccountID: account.identity.stableAccountID,
            liveAuthPrincipalIdentity: account.identity.authPrincipalIdentity,
            liveWorkspaceIdentity: account.identity.workspaceIdentity,
            liveAuthFingerprint: account.identity.snapshotFingerprint,
            liveRemoteIdentity: account.resolvedRemoteIdentity,
            accounts: candidates
        )

        if let matchedAccountID = matchOutcome.matchedAccountID,
           let matchedAccount = candidates.first(where: { $0.id == matchedAccountID }) {
            return matchedAccount
        }

        return uniqueDisplayMatch(for: account, among: candidates)
    }

    func resolveCanonicalAccount(
        for hostState: PersistedRemoteHostState,
        among candidates: [CodexAccount]
    ) -> CodexAccount? {
        if let desiredAccountID = hostState.desiredAccountID,
           let desiredAccount = candidates.first(where: { $0.id == desiredAccountID }) {
            return desiredAccount
        }

        if let verifiedAccount = hostState.verifiedAccount,
           let canonicalVerifiedAccount = resolveCanonicalAccount(for: verifiedAccount, among: candidates) {
            return canonicalVerifiedAccount
        }

        return nil
    }

    private func uniqueDisplayMatch(
        for account: CodexAccount,
        among candidates: [CodexAccount]
    ) -> CodexAccount? {
        let normalizedName = normalize(account.name)
        guard !normalizedName.isEmpty,
              let normalizedEmail = normalizeOptional(account.email) else {
            return nil
        }

        let normalizedPlanType = normalizeOptional(account.planType)
        let matches = candidates.filter { candidate in
            normalize(candidate.name) == normalizedName &&
                normalizeOptional(candidate.email) == normalizedEmail &&
                normalizeOptional(candidate.planType) == normalizedPlanType
        }

        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalize(value)
        return normalized.isEmpty ? nil : normalized
    }
}
