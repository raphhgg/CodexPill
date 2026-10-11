import Foundation

@testable import Refill

/// Builds a saved account whose email is derived from its name, for example "Business 2" → "business 2@example.com".
func makeAccount(
    id: UUID = UUID(),
    name: String = "Account",
    fingerprint: String = UUID().uuidString,
    stableAccountID: String? = nil,
    authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil,
    workspaceIdentity: CodexWorkspaceIdentity? = nil,
    planType: String? = nil,
    usage: UsageSnapshot? = nil,
    updatedAt: Date = .distantPast
) -> CodexAccount {
    makeAccount(
        id: id,
        name: name,
        email: "\(name.lowercased())@example.com",
        fingerprint: fingerprint,
        stableAccountID: stableAccountID,
        authPrincipalIdentity: authPrincipalIdentity,
        workspaceIdentity: workspaceIdentity,
        planType: planType,
        usage: usage,
        updatedAt: updatedAt
    )
}

/// Builds a saved account with an explicit email; pass `nil` for an account Codex has not reported an email for.
func makeAccount(
    id: UUID = UUID(),
    name: String = "Account",
    email: String?,
    fingerprint: String = UUID().uuidString,
    stableAccountID: String? = nil,
    authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil,
    workspaceIdentity: CodexWorkspaceIdentity? = nil,
    planType: String? = nil,
    usage: UsageSnapshot? = nil,
    updatedAt: Date = .distantPast
) -> CodexAccount {
    CodexAccount(
        id: id,
        name: name,
        snapshotFileName: "\(id.uuidString).json",
        createdAt: updatedAt,
        updatedAt: updatedAt,
        email: email,
        planType: planType,
        usage: usage,
        identity: CodexAccountIdentity(
            stableAccountID: stableAccountID,
            authPrincipalIdentity: authPrincipalIdentity,
            workspaceIdentity: workspaceIdentity,
            snapshotFingerprint: fingerprint,
            remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
        )
    )
}

/// Builds Codex usage with a five-hour session window and a weekly window.
func makeUsage(
    planType: String? = nil,
    sessionUsedPercent: Int = 42,
    sessionResetsAt: Date? = nil,
    weeklyUsedPercent: Int = 68,
    weeklyResetsAt: Date? = nil,
    fetchedAt: Date = .now
) -> UsageSnapshot {
    UsageSnapshot(
        provider: .codex,
        planName: planType,
        windows: [
            UsageWindow(kind: .session, usedPercent: sessionUsedPercent, resetsAt: sessionResetsAt, durationMinutes: 300),
            UsageWindow(kind: .weekly, usedPercent: weeklyUsedPercent, resetsAt: weeklyResetsAt, durationMinutes: 10_080),
        ],
        fetchedAt: fetchedAt
    )
}

/// Builds Codex usage fetched at `now` whose session window resets an hour later and weekly window a day later.
func makeUsage(
    resettingAfter now: Date,
    planType: String? = nil,
    sessionUsedPercent: Int = 42,
    weeklyUsedPercent: Int = 68
) -> UsageSnapshot {
    makeUsage(
        planType: planType,
        sessionUsedPercent: sessionUsedPercent,
        sessionResetsAt: now.addingTimeInterval(3_600),
        weeklyUsedPercent: weeklyUsedPercent,
        weeklyResetsAt: now.addingTimeInterval(86_400),
        fetchedAt: now
    )
}
