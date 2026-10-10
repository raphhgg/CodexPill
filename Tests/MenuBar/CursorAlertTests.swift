import Testing

@testable import CodexPill

struct CursorAlertTests {
    private let errors: [CursorAccountsError] = [
        .cursorNotInstalled, .signedOut, .accountNotFound, .savedAccountsUnreadable, .stateUnreadable, .cursorDidNotQuit,
        .cursorBusy, .writeFailed, .reopenFailed, .switchingUnavailable,
    ]

    @Test
    func eachSwitchFailureGetsItsOwnShortAlert() {
        let alerts = errors.map(MenuBarAlertFactory().makeCursorAccountErrorRequest)

        #expect(Set(alerts.map(\.messageText)).count == errors.count)
        #expect(alerts.allSatisfy { $0.messageText.count <= 32 && $0.informativeText.count <= 40 })
        #expect(alerts.allSatisfy { $0.informativeText.filter { $0 == "." }.count == 1 })
    }
}
