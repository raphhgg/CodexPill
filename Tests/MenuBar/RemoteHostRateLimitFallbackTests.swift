import Foundation
import Testing

@testable import CodexPill

struct RemoteHostRateLimitFallbackTests {
    @Test
    func usesMatchingSavedAccountLimitsWhenRemoteAndPersistedRemoteAreBothZeroed() {
        let baseAccount = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "acct-team",
            sessionUsedPercent: 0,
            sessionResetsAt: nil,
            weeklyUsedPercent: 0,
            weeklyResetsAt: nil
        )
        let savedMatchingAccount = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "acct-team",
            sessionUsedPercent: 97,
            sessionResetsAt: Date().addingTimeInterval(3600),
            weeklyUsedPercent: 15,
            weeklyResetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60)
        )
        let remote = CodexRateLimitSnapshot(
            limitID: nil,
            limitName: nil,
            planType: "team",
            primary: CodexRateLimitWindow(
                usedPercent: 0,
                resetsAt: nil,
                windowDurationMinutes: 300
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 0,
                resetsAt: nil,
                windowDurationMinutes: 10_080
            ),
            fetchedAt: .now
        )

        let result = preferredRemoteRateLimits(
            remote: remote,
            fallback: baseAccount.rateLimits,
            candidateAccounts: [savedMatchingAccount],
            baseAccount: baseAccount,
            remoteEmail: "raphaelgrau@gmail.com"
        )

        #expect(result?.primary?.usedPercent == 97)
        #expect(result?.secondary?.usedPercent == 15)
        #expect(result?.primary?.resetsAt != nil)
        #expect(result?.secondary?.resetsAt != nil)
    }

    @Test
    func keepsRemoteRateLimitsWhenRemotePayloadIsMeaningful() {
        let baseAccount = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "acct-team",
            sessionUsedPercent: 0,
            sessionResetsAt: nil,
            weeklyUsedPercent: 0,
            weeklyResetsAt: nil
        )
        let savedMatchingAccount = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "acct-team",
            sessionUsedPercent: 97,
            sessionResetsAt: Date().addingTimeInterval(3600),
            weeklyUsedPercent: 15,
            weeklyResetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60)
        )
        let remote = CodexRateLimitSnapshot(
            limitID: nil,
            limitName: nil,
            planType: "team",
            primary: CodexRateLimitWindow(
                usedPercent: 12,
                resetsAt: Date().addingTimeInterval(1800),
                windowDurationMinutes: 300
            ),
            secondary: nil,
            fetchedAt: .now
        )

        let result = preferredRemoteRateLimits(
            remote: remote,
            fallback: baseAccount.rateLimits,
            candidateAccounts: [savedMatchingAccount],
            baseAccount: baseAccount,
            remoteEmail: "raphaelgrau@gmail.com"
        )

        #expect(result?.primary?.usedPercent == 12)
        #expect(result?.primary?.resetsAt != nil)
    }

    @Test
    func preservesFallbackResetTimeWhenRemoteWindowOmitsIt() {
        let fallbackReset = Date().addingTimeInterval(37 * 60)
        let baseAccount = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "acct-team",
            sessionUsedPercent: 0,
            sessionResetsAt: nil,
            weeklyUsedPercent: 0,
            weeklyResetsAt: nil
        )
        let savedMatchingAccount = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "acct-team",
            sessionUsedPercent: 81,
            sessionResetsAt: fallbackReset,
            weeklyUsedPercent: 15,
            weeklyResetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60)
        )
        let remote = CodexRateLimitSnapshot(
            limitID: nil,
            limitName: nil,
            planType: "team",
            primary: CodexRateLimitWindow(
                usedPercent: 92,
                resetsAt: nil,
                windowDurationMinutes: 300
            ),
            secondary: nil,
            fetchedAt: .now
        )

        let result = preferredRemoteRateLimits(
            remote: remote,
            fallback: baseAccount.rateLimits,
            candidateAccounts: [savedMatchingAccount],
            baseAccount: baseAccount,
            remoteEmail: "raphaelgrau@gmail.com"
        )

        #expect(result?.primary?.usedPercent == 92)
        #expect(result?.primary?.resetsAt == fallbackReset)
    }

    @Test
    func usesScopedStableIdentityToChooseMatchingSavedAccountWhenRemoteEmailIsAmbiguous() {
        let baseAccount = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "team-stable",
            sessionUsedPercent: 0,
            sessionResetsAt: nil,
            weeklyUsedPercent: 0,
            weeklyResetsAt: nil,
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-2",
                workspaceLabel: "Personal"
            )
        )
        let businessTwo = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "team-stable",
            sessionUsedPercent: 100,
            sessionResetsAt: Date().addingTimeInterval(3600),
            weeklyUsedPercent: 16,
            weeklyResetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60),
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-2",
                workspaceLabel: "Personal"
            )
        )
        let personal = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "personal-stable",
            sessionUsedPercent: 44,
            sessionResetsAt: Date().addingTimeInterval(7200),
            weeklyUsedPercent: 8,
            weeklyResetsAt: Date().addingTimeInterval(3 * 24 * 60 * 60),
            authPrincipalIdentity: CodexAuthPrincipalIdentity(
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2"
            ),
            workspaceIdentity: CodexWorkspaceIdentity(
                workspaceAccountID: "org-business-2",
                workspaceLabel: "Personal"
            )
        )
        let remote = CodexRateLimitSnapshot(
            limitID: nil,
            limitName: nil,
            planType: "team",
            primary: CodexRateLimitWindow(
                usedPercent: 0,
                resetsAt: nil,
                windowDurationMinutes: 300
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 0,
                resetsAt: nil,
                windowDurationMinutes: 10_080
            ),
            fetchedAt: .now
        )

        let result = preferredRemoteRateLimits(
            remote: remote,
            fallback: baseAccount.rateLimits,
            candidateAccounts: [businessTwo, personal],
            baseAccount: baseAccount,
            remoteEmail: "raphaelgrau@gmail.com"
        )

        #expect(result?.primary?.usedPercent == 100)
        #expect(result?.secondary?.usedPercent == 16)
    }

    @Test
    func mergesPerWindowWhenRemoteOnlyHasWeeklyData() {
        let baseAccount = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "acct-team",
            sessionUsedPercent: 0,
            sessionResetsAt: nil,
            weeklyUsedPercent: 0,
            weeklyResetsAt: nil
        )
        let savedMatchingAccount = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "acct-team",
            sessionUsedPercent: 100,
            sessionResetsAt: Date().addingTimeInterval(59 * 60),
            weeklyUsedPercent: 16,
            weeklyResetsAt: Date().addingTimeInterval(5 * 24 * 60 * 60)
        )
        let remote = CodexRateLimitSnapshot(
            limitID: nil,
            limitName: nil,
            planType: "team",
            primary: nil,
            secondary: CodexRateLimitWindow(
                usedPercent: 31,
                resetsAt: Date().addingTimeInterval(6 * 24 * 60 * 60),
                windowDurationMinutes: 10_080
            ),
            fetchedAt: .now
        )

        let result = preferredRemoteRateLimits(
            remote: remote,
            fallback: baseAccount.rateLimits,
            candidateAccounts: [savedMatchingAccount],
            baseAccount: baseAccount,
            remoteEmail: "raphaelgrau@gmail.com"
        )

        #expect(result?.primary?.usedPercent == 100)
        #expect(result?.primary?.resetsAt != nil)
        #expect(result?.secondary?.usedPercent == 31)
        #expect(result?.secondary?.resetsAt != nil)
    }

    @Test
    func fallsBackWhenRemoteWindowHasExpiredResetTime() {
        let now = Date()
        let fallbackReset = now.addingTimeInterval(21 * 60)
        let baseAccount = makeAccount(
            email: "raphaelgrau@gmail.com",
            stableAccountID: "acct-team",
            sessionUsedPercent: 100,
            sessionResetsAt: fallbackReset,
            weeklyUsedPercent: 16,
            weeklyResetsAt: now.addingTimeInterval(5 * 24 * 60 * 60)
        )
        let remote = CodexRateLimitSnapshot(
            limitID: nil,
            limitName: nil,
            planType: "team",
            primary: CodexRateLimitWindow(
                usedPercent: 100,
                resetsAt: now.addingTimeInterval(-45 * 60),
                windowDurationMinutes: 300
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 16,
                resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                windowDurationMinutes: 10_080
            ),
            fetchedAt: now
        )

        let result = preferredRemoteRateLimits(
            remote: remote,
            fallback: baseAccount.rateLimits,
            candidateAccounts: [baseAccount],
            baseAccount: baseAccount,
            remoteEmail: "raphaelgrau@gmail.com"
        )

        #expect(result?.primary?.displayedUsedPercent(at: now) == 100)
        #expect(result?.primary?.resetsAt == fallbackReset)
        #expect(result?.secondary?.usedPercent == 16)
    }

    private func makeAccount(
        email: String,
        stableAccountID: String,
        sessionUsedPercent: Int,
        sessionResetsAt: Date?,
        weeklyUsedPercent: Int,
        weeklyResetsAt: Date?,
        authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil,
        workspaceIdentity: CodexWorkspaceIdentity? = nil
    ) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "business-2.json",
            createdAt: .distantPast,
            updatedAt: .now,
            email: email,
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: sessionUsedPercent,
                    resetsAt: sessionResetsAt,
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: weeklyUsedPercent,
                    resetsAt: weeklyResetsAt,
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: .now
            ),
            identity: CodexAccountIdentity(
                stableAccountID: stableAccountID,
                authPrincipalIdentity: authPrincipalIdentity,
                workspaceIdentity: workspaceIdentity,
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}
