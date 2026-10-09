import Foundation
import Testing

@testable import CodexPill

struct RemoteRateLimitResolutionTests {
    @Test
    func usesMatchingSavedAccountLimitsWhenRemoteAndPersistedRemoteAreBothZeroed() {
        let baseAccount = makeAccount(
            email: "user@example.com",
            stableAccountID: "acct-team",
            usage: makeUsage(sessionUsedPercent: 0, weeklyUsedPercent: 0)
        )
        let savedMatchingAccount = makeAccount(
            email: "user@example.com",
            stableAccountID: "acct-team",
            usage: makeUsage(
                sessionUsedPercent: 97,
                sessionResetsAt: Date().addingTimeInterval(3600),
                weeklyUsedPercent: 15,
                weeklyResetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60)
            )
        )
        let remote = UsageSnapshot.codex(
            planName: "team",
            primary: (usedPercent: 0, resetsAt: nil, durationMinutes: 300),
            secondary: (usedPercent: 0, resetsAt: nil, durationMinutes: 10_080),
            fetchedAt: .now
        )

        let result = RemoteRateLimitResolution().preferredRateLimits(
            remote: remote,
            fallback: baseAccount.usage,
            candidateAccounts: [savedMatchingAccount],
            baseAccount: baseAccount,
            remoteEmail: "user@example.com"
        )

        #expect(result?.window(.session)?.usedPercent == 97)
        #expect(result?.window(.weekly)?.usedPercent == 15)
        #expect(result?.window(.session)?.resetsAt != nil)
        #expect(result?.window(.weekly)?.resetsAt != nil)
    }

    @Test
    func keepsRemoteRateLimitsWhenRemotePayloadIsMeaningful() {
        let baseAccount = makeAccount(
            email: "user@example.com",
            stableAccountID: "acct-team",
            usage: makeUsage(sessionUsedPercent: 0, weeklyUsedPercent: 0)
        )
        let savedMatchingAccount = makeAccount(
            email: "user@example.com",
            stableAccountID: "acct-team",
            usage: makeUsage(
                sessionUsedPercent: 97,
                sessionResetsAt: Date().addingTimeInterval(3600),
                weeklyUsedPercent: 15,
                weeklyResetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60)
            )
        )
        let remote = UsageSnapshot.codex(
            planName: "team",
            primary: (usedPercent: 12, resetsAt: Date().addingTimeInterval(1800), durationMinutes: 300),
            secondary: nil,
            fetchedAt: .now
        )

        let result = RemoteRateLimitResolution().preferredRateLimits(
            remote: remote,
            fallback: baseAccount.usage,
            candidateAccounts: [savedMatchingAccount],
            baseAccount: baseAccount,
            remoteEmail: "user@example.com"
        )

        #expect(result?.window(.session)?.usedPercent == 12)
        #expect(result?.window(.session)?.resetsAt != nil)
    }

    @Test
    func preservesFallbackResetTimeWhenRemoteWindowOmitsIt() {
        let fallbackReset = Date().addingTimeInterval(37 * 60)
        let baseAccount = makeAccount(
            email: "user@example.com",
            stableAccountID: "acct-team",
            usage: makeUsage(sessionUsedPercent: 0, weeklyUsedPercent: 0)
        )
        let savedMatchingAccount = makeAccount(
            email: "user@example.com",
            stableAccountID: "acct-team",
            usage: makeUsage(
                sessionUsedPercent: 81,
                sessionResetsAt: fallbackReset,
                weeklyUsedPercent: 15,
                weeklyResetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60)
            )
        )
        let remote = UsageSnapshot.codex(
            planName: "team",
            primary: (usedPercent: 92, resetsAt: nil, durationMinutes: 300),
            secondary: nil,
            fetchedAt: .now
        )

        let result = RemoteRateLimitResolution().preferredRateLimits(
            remote: remote,
            fallback: baseAccount.usage,
            candidateAccounts: [savedMatchingAccount],
            baseAccount: baseAccount,
            remoteEmail: "user@example.com"
        )

        #expect(result?.window(.session)?.usedPercent == 92)
        #expect(result?.window(.session)?.resetsAt == fallbackReset)
    }

    @Test
    func usesScopedStableIdentityToChooseMatchingSavedAccountWhenRemoteEmailIsAmbiguous() {
        let baseAccount = makeAccount(
            email: "user@example.com",
            stableAccountID: "team-stable",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-2",
                workspaceLabel: "Personal"
            ),
            usage: makeUsage(sessionUsedPercent: 0, weeklyUsedPercent: 0)
        )
        let businessTwo = makeAccount(
            email: "user@example.com",
            stableAccountID: "team-stable",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-2",
                workspaceLabel: "Personal"
            ),
            usage: makeUsage(
                sessionUsedPercent: 100,
                sessionResetsAt: Date().addingTimeInterval(3600),
                weeklyUsedPercent: 16,
                weeklyResetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60)
            )
        )
        let personal = makeAccount(
            email: "user@example.com",
            stableAccountID: "personal-stable",
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-2",
                workspaceLabel: "Personal"
            ),
            usage: makeUsage(
                sessionUsedPercent: 44,
                sessionResetsAt: Date().addingTimeInterval(7200),
                weeklyUsedPercent: 8,
                weeklyResetsAt: Date().addingTimeInterval(3 * 24 * 60 * 60)
            )
        )
        let remote = UsageSnapshot.codex(
            planName: "team",
            primary: (usedPercent: 0, resetsAt: nil, durationMinutes: 300),
            secondary: (usedPercent: 0, resetsAt: nil, durationMinutes: 10_080),
            fetchedAt: .now
        )

        let result = RemoteRateLimitResolution().preferredRateLimits(
            remote: remote,
            fallback: baseAccount.usage,
            candidateAccounts: [businessTwo, personal],
            baseAccount: baseAccount,
            remoteEmail: "user@example.com"
        )

        #expect(result?.window(.session)?.usedPercent == 100)
        #expect(result?.window(.weekly)?.usedPercent == 16)
    }

    @Test
    func mergesPerWindowWhenRemoteOnlyHasWeeklyData() {
        let baseAccount = makeAccount(
            email: "user@example.com",
            stableAccountID: "acct-team",
            usage: makeUsage(sessionUsedPercent: 0, weeklyUsedPercent: 0)
        )
        let savedMatchingAccount = makeAccount(
            email: "user@example.com",
            stableAccountID: "acct-team",
            usage: makeUsage(
                sessionUsedPercent: 100,
                sessionResetsAt: Date().addingTimeInterval(59 * 60),
                weeklyUsedPercent: 16,
                weeklyResetsAt: Date().addingTimeInterval(5 * 24 * 60 * 60)
            )
        )
        let remote = UsageSnapshot.codex(
            planName: "team",
            primary: nil,
            secondary: (usedPercent: 31, resetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60), durationMinutes: 10_080),
            fetchedAt: .now
        )

        let result = RemoteRateLimitResolution().preferredRateLimits(
            remote: remote,
            fallback: baseAccount.usage,
            candidateAccounts: [savedMatchingAccount],
            baseAccount: baseAccount,
            remoteEmail: "user@example.com"
        )

        #expect(result?.window(.session)?.usedPercent == 100)
        #expect(result?.window(.session)?.resetsAt != nil)
        #expect(result?.window(.weekly)?.usedPercent == 31)
        #expect(result?.window(.weekly)?.resetsAt != nil)
    }

    @Test
    func fallsBackWhenRemoteWindowHasExpiredResetTime() {
        let now = Date()
        let fallbackReset = now.addingTimeInterval(21 * 60)
        let baseAccount = makeAccount(
            email: "user@example.com",
            stableAccountID: "acct-team",
            usage: makeUsage(
                sessionUsedPercent: 100,
                sessionResetsAt: fallbackReset,
                weeklyUsedPercent: 16,
                weeklyResetsAt: now.addingTimeInterval(5 * 24 * 60 * 60)
            )
        )
        let remote = UsageSnapshot.codex(
            planName: "team",
            primary: (usedPercent: 100, resetsAt: now.addingTimeInterval(-45 * 60), durationMinutes: 300),
            secondary: (usedPercent: 16, resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60), durationMinutes: 10_080),
            fetchedAt: now
        )

        let result = RemoteRateLimitResolution().preferredRateLimits(
            remote: remote,
            fallback: baseAccount.usage,
            candidateAccounts: [baseAccount],
            baseAccount: baseAccount,
            remoteEmail: "user@example.com"
        )

        #expect(result?.window(.session)?.displayedUsedPercent(at: now) == 100)
        #expect(result?.window(.session)?.resetsAt == fallbackReset)
        #expect(result?.window(.weekly)?.usedPercent == 16)
    }
}
