import Foundation

extension MenuBarAlertFactory {
    func makeConnectCursorRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Connect Cursor?",
            informativeText: "Uses Cursor's sign-in to read your usage.",
            confirmTitle: "Connect",
            cancelTitle: "Cancel"
        )
    }

}
