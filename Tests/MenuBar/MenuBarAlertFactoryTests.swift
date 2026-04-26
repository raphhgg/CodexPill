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
    func addAccountWarningOmitsCliNoticeWhenNoSessionsRunning() {
        let request = factory.makeAddAccountRequest(runningCLISessions: 0)

        #expect(request.messageText == "Add another account?")
        #expect(request.confirmTitle == "Add Account")
        #expect(request.informativeText.contains("save it in your account collection"))
        #expect(request.informativeText.contains("signs into another Codex account in Codex"))
        #expect(!request.informativeText.contains("running Codex CLI session"))
    }

    @Test
    func addAccountWarningMentionsTerminalNoticeWhenCliSessionsExist() {
        let request = factory.makeAddAccountRequest(runningCLISessions: 1)

        #expect(request.informativeText.contains("1 running Codex CLI session was detected"))
        #expect(request.informativeText.contains("Restart any open Codex CLI terminals after sign-in"))
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
    func addHostRequestUsesTestThenAddCopy() {
        let request = factory.makeAddHostRequest()

        #expect(request.messageText == "Add remote host")
        #expect(request.placeholder == "user@host")
        #expect(request.nameFieldTitle == "Host Name (Optional)")
        #expect(request.namePlaceholder == "buildbox")
        #expect(request.confirmTitle == "Add Host")
        #expect(request.cancelTitle == "Cancel")
        #expect(request.idleStatusText == "CodexPill checks the connection automatically.")
        #expect(request.successStatusText == "Connection successful.")
    }

    @Test
    func errorRequestUsesWarningStyle() {
        let request = factory.makeErrorRequest(message: "Boom")

        #expect(request.messageText == "CodexPill Error")
        #expect(request.informativeText == "Boom")
        #expect(request.style == .warning)
    }

    @Test
    func installCurrentAccountOnHostRequestExplainsCancelAbortsSetup() {
        let request = factory.makeInstallCurrentAccountOnHostRequest(accountName: "Business 1", hostName: "buildbox")

        #expect(request.messageText == "Install current account on buildbox?")
        #expect(request.informativeText.contains("install and switch Business 1 on buildbox now"))
        #expect(request.informativeText.contains("the host will not be added yet"))
        #expect(request.confirmTitle == "Install and Switch")
        #expect(request.cancelTitle == "Cancel")
    }

    @Test
    func notificationActionRequestExplainsSubstitutionWhenPresent() {
        let request = factory.makeNotificationActionRequest(
            accountName: "Business 2",
            targetDescription: "debian-vm",
            substitutionMessage: "Business 4 is no longer the best option. Switching to Business 2 instead.",
            runningCLISessions: nil
        )

        #expect(request.messageText == "Use Business 2 now?")
        #expect(request.informativeText.contains("Business 4 is no longer the best option. Switching to Business 2 instead."))
        #expect(request.informativeText.contains("CodexPill will switch debian-vm to Business 2."))
        #expect(request.confirmTitle == "Switch")
    }
}
