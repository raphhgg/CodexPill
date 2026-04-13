import AppKit
import Foundation
import Testing

@testable import CodexPill

struct MenuBarAlertFactoryTests {
    private let factory = MenuBarAlertFactory()

    @Test
    func saveCurrentAccountUsesEmailPlaceholderWhenAvailable() {
        let request = factory.makeSaveCurrentAccountRequest(activeAccountEmail: "person@example.com")

        #expect(request.placeholder == "person@example.com")
        #expect(request.confirmTitle == "Save")
    }

    @Test
    func saveCurrentAccountFallsBackToDefaultPlaceholder() {
        let request = factory.makeSaveCurrentAccountRequest(activeAccountEmail: nil)

        #expect(request.placeholder == "Personal 1")
    }

    @Test
    func switchAccountWarningMentionsRunningCliSessions() {
        let request = factory.makeSwitchAccountRequest(accountName: "Work", runningCLISessions: 2)

        #expect(request.informativeText.contains("switch the local Codex account to Work"))
        #expect(request.informativeText.contains("2 running Codex CLI sessions were detected"))
        #expect(request.informativeText.contains("Restart any open Codex CLI terminals to use the new account."))
    }

    @Test
    func signInAnotherWarningOmitsCliNoticeWhenNoSessionsRunning() {
        let request = factory.makeSignInAnotherRequest(runningCLISessions: 0)

        #expect(request.informativeText.contains("sign Codex out, restart the app"))
        #expect(!request.informativeText.contains("running Codex CLI session"))
    }

    @Test
    func signInAnotherWarningMentionsTerminalRestartWhenCliSessionsExist() {
        let request = factory.makeSignInAnotherRequest(runningCLISessions: 1)

        #expect(request.informativeText.contains("1 running Codex CLI session was detected"))
        #expect(request.informativeText.contains("Restart any open Codex CLI terminals after signing in to use the new account."))
    }

    @Test
    func removeAccountWarningMentionsCurrentAccountConsequence() {
        let request = factory.makeRemoveAccountRequest(accountName: "Work", isCurrent: true)

        #expect(request.informativeText.contains("saved snapshot for Work"))
        #expect(request.informativeText.contains("live Codex session will remain logged in"))
        #expect(request.confirmTitle == "Remove")
    }

    @Test
    func renameAccountRequestUsesCurrentNameAsPlaceholder() {
        let request = factory.makeRenameAccountRequest(accountName: "Business 1")

        #expect(request.messageText == "Rename saved account")
        #expect(request.placeholder == "Business 1")
        #expect(request.confirmTitle == "Rename")
    }

    @Test
    func errorRequestUsesWarningStyle() {
        let request = factory.makeErrorRequest(message: "Boom")

        #expect(request.messageText == "CodexPill Error")
        #expect(request.informativeText == "Boom")
        #expect(request.style == .warning)
    }
}
