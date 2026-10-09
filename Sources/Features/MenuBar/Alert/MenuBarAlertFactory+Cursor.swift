import Foundation

extension MenuBarAlertFactory {
    func makeConnectCursorRequest() -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: "Connect Cursor?",
            informativeText: [
                "CodexPill will read your Cursor sign-in from Cursor's app data on this Mac. It only reads it and never changes Cursor's files.",
                "CodexPill sends your sign-in only to cursor.com, to fetch your plan usage, on-demand spend, and billing cycle. It does not store, log, or show your sign-in.",
                "To stop, choose Disconnect Cursor in Preferences."
            ].joined(separator: "\n\n"),
            confirmTitle: "Connect",
            cancelTitle: "Cancel"
        )
    }
}
