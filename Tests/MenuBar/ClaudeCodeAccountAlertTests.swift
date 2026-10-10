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

    @Test
    func everyClaudeSignInFailureGetsAShortAlert() {
        let errors: [ClaudeSignInError] = [
            .denied, .timedOut, .stateMismatch, .listenerFailed,
            .token(.invalidGrant), .token(.transport), .token(.rejected(status: 500)), .token(.malformedResponse),
        ]
        let alerts = errors.map(MenuBarAlertFactory().makeClaudeSignInErrorRequest) + [
            MenuBarAlertFactory().makeClaudeSignInNotRemovedRequest(), MenuBarAlertFactory().makeClaudeSignInNotSavedRequest(),
        ]

        #expect(alerts.allSatisfy { $0.messageText.count <= 32 && $0.informativeText.count <= 40 })
        #expect(alerts.allSatisfy { $0.informativeText.filter { $0 == "." }.count == 1 })
    }
}
