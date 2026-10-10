import Testing

@testable import CodexPill

struct ClaudeCodeAccountAlertTests {
    private let errors: [ClaudeCodeAccountError] = [
        .unknownAccount, .savedSignInMissing, .savedAccountsUnreadable, .claudeCodeSignedOut, .claudeCodeAccountUnknown,
        .currentSignInNotSaved, .claudeCodeRunning, .keychainAccessNeeded, .unreadable, .writeFailed, .restoreFailed,
        .switchingUnavailable,
    ]

    @Test
    func eachSwitchFailureGetsItsOwnShortAlert() {
        let alerts = errors.map(MenuBarAlertFactory().makeClaudeCodeAccountErrorRequest)

        #expect(Set(alerts.map(\.messageText)).count == errors.count)
        #expect(alerts.allSatisfy { $0.messageText.count <= 32 && $0.informativeText.count <= 40 })
        #expect(alerts.allSatisfy { $0.informativeText.filter { $0 == "." }.count == 1 })
    }
}
