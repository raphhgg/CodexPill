import Foundation

extension MenuBarAlertFactory {
    func makeConfirmationRequest(_ prompt: ProviderPrompt) -> MenuBarConfirmationAlertRequest {
        MenuBarConfirmationAlertRequest(
            messageText: prompt.title,
            informativeText: prompt.detail,
            confirmTitle: prompt.confirmTitle,
            cancelTitle: "Cancel"
        )
    }

    func makeNoticeRequest(_ notice: ProviderNotice) -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(messageText: notice.title, informativeText: notice.detail ?? "", style: .warning, buttonTitle: "OK")
    }

    func makeUseResetCreditRequest(_ credits: UsageResetCredits?) -> MenuBarConfirmationAlertRequest {
        let count = credits?.availableCount ?? 0
        let detail = if count == 1, let expiry = credits?.nextExpiry {
            "Uses the reset that expires \(shortDate(expiry))."
        } else if count > 1 {
            "Uses 1 of \(count) resets."
        } else {
            "Uses one reset."
        }
        return MenuBarConfirmationAlertRequest(
            messageText: "Reset Codex limits?",
            informativeText: detail,
            confirmTitle: "Reset",
            cancelTitle: "Cancel"
        )
    }

    func makeResetCreditResultRequest(_ result: ResetCreditResult) -> MenuBarInfoAlertRequest {
        MenuBarInfoAlertRequest(
            messageText: result.message,
            informativeText: "",
            style: result == .reset ? .informational : .warning,
            buttonTitle: "OK"
        )
    }
}
