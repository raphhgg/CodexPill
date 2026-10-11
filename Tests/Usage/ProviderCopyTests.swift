import Testing

@testable import Refill

struct ProviderCopyTests {
    private let reasons: [UsageUnavailableReason] = [
        .signedOut, .signInExpired, .keychainAccessNeeded, .signInUnreadable, .signInBusy, .accessDenied,
        .rateLimited, .unreachable, .serviceError, .unexpectedResponse,
    ]

    private let switchNotices: [ProviderNotice] = [
        ClaudeCodeAccountError.unknownAccount, .savedSignInMissing, .savedAccountsUnreadable, .claudeCodeSignedOut,
        .claudeCodeAccountUnknown, .claudeCodeRunning, .keychainAccessNeeded, .unreadable,
        .writeFailed, .restoreFailed, .switchingUnavailable,
    ].map(\.notice)

    private let cursorSwitchNotices: [ProviderNotice] = [
        CursorAccountsError.cursorNotInstalled, .signedOut, .accountNotFound, .savedAccountsUnreadable, .stateUnreadable,
        .cursorDidNotQuit, .cursorBusy, .writeFailed, .reopenFailed, .switchingUnavailable,
    ].map(\.notice)

    @Test
    func everyClaudeFailureReadsDifferentlySoA403NeverSaysAnthropicIsUnreachable() {
        let titles = reasons.map { UsageProvider.claude.copy.unavailableMessage(for: $0).title }

        #expect(Set(titles).count == reasons.count)
        #expect(UsageProvider.claude.copy.unavailableMessage(for: .accessDenied).title.contains("reach") == false)
    }

    @Test
    func aBusyCursorDatabaseIsTransientNotASignInProblem() {
        let message = UsageProvider.cursor.copy.unavailableMessage(for: .signInBusy)

        #expect(message.title == "Cursor is busy")
        #expect(message.detail == "Retrying in a few minutes.")
    }

    @Test
    func menuCopyIsATitleAndAtMostOneShortLine() {
        for provider in [UsageProvider.claude, .cursor] {
            for reason in reasons {
                let message = provider.copy.unavailableMessage(for: reason)
                #expect(message.title.count <= 40)
                #expect((message.detail?.count ?? 0) <= 40)
                #expect(message.detail?.filter { $0 == "." }.count ?? 0 <= 1)
            }
        }
    }

    @Test
    func eachSwitchFailureGetsItsOwnShortAlert() {
        for notices in [switchNotices, cursorSwitchNotices] {
            #expect(Set(notices.map(\.title)).count == notices.count)
            #expect(notices.allSatisfy { $0.title.count <= 32 && ($0.detail?.count ?? 0) <= 40 })
            #expect(notices.allSatisfy { $0.detail?.filter { $0 == "." }.count == 1 })
        }
    }
}
