import Foundation

extension MenuBarAlertFactory {
    func makeConnectCursorRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Connect Cursor?",
            informativeText: "CodexPill will read Cursor's sign-in on this Mac to show your plan usage from cursor.com. You can disconnect in Preferences.",
            confirmTitle: "Connect",
            cancelTitle: "Cancel"
        )
    }
}
