import AppKit
import Foundation
import SwiftUI
import Testing

@testable import CodexPill

@MainActor
final class AlertPresenterProbe: AlertPresenter {
    private(set) var textInputRequests: [MenuBarTextInputAlertRequest] = []
    private(set) var confirmationRequests: [MenuBarConfirmationAlertRequest] = []
    private(set) var infoRequests: [MenuBarInfoAlertRequest] = []

    var textInputResponse: String?
    var confirmationResponse = false

    func presentTextInput(_ request: MenuBarTextInputAlertRequest) -> String? {
        textInputRequests.append(request)
        return textInputResponse
    }

    func presentConfirmation(_ request: MenuBarConfirmationAlertRequest) -> Bool {
        confirmationRequests.append(request)
        return confirmationResponse
    }

    func presentInfo(_ request: MenuBarInfoAlertRequest) {
        infoRequests.append(request)
    }
}

@MainActor
final class PanelPresenterProbe: PanelPresenter {
    private(set) var hostSetupRequests: [MenuBarHostSetupPanelRequest] = []
    private(set) var addAccountSignInRequests: [MenuBarAddAccountSignInPanelRequest] = []

    var hostSetupResponse: RemoteHost?
    var addAccountSignInResult: MenuBarAddAccountSignInPanelResult = .cancelled

    func presentHostSetup(
        _ request: MenuBarHostSetupPanelRequest,
        testConnection _: @escaping (RemoteHost) async -> Result<Void, Error>,
        onPresented: @escaping () -> Void = {},
        onCancelled _: @escaping () -> Void = {},
        onValidationStarted _: @escaping (RemoteHost) -> Void = { _ in },
        onValidationFinished _: @escaping (RemoteHost, Result<Void, Error>) -> Void = { _, _ in }
    ) async -> RemoteHost? {
        hostSetupRequests.append(request)
        onPresented()
        return hostSetupResponse
    }

    func presentAddAccountSignIn(
        _ request: MenuBarAddAccountSignInPanelRequest,
        waitForCompletion _: @escaping () async -> Result<CodexAccount, Error>,
        onCancel _: @escaping () -> Void
    ) async -> MenuBarAddAccountSignInPanelResult {
        addAccountSignInRequests.append(request)
        return addAccountSignInResult
    }
}

final class LoginItemControllerProbe: LoginItemControlling {
    var currentState: LoginItemState
    var setEnabledCalls: [Bool] = []
    var errorToThrow: Error?

    init(currentState: LoginItemState = .disabled) {
        self.currentState = currentState
    }

    func state() -> LoginItemState {
        currentState
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        setEnabledCalls.append(isEnabled)
        currentState = isEnabled ? .enabled : .disabled
    }
}

final class LoginItemsSettingsLauncherProbe: LoginItemsSettingsLaunching {
    var opens = 0
    var result = true

    func openLoginItemsSettings() -> Bool {
        opens += 1
        return result
    }
}

private struct LoginItemProbeError: Error {}

@MainActor
final class DiagnosticReportPresenterProbe: DiagnosticReportPresenting {
    private(set) var reports: [DiagnosticReport] = []

    func export(report: DiagnosticReport) throws -> URL? {
        reports.append(report)
        return URL(fileURLWithPath: "/tmp/CodexPill-Diagnostics.json")
    }
}

@MainActor
struct MenuBarMenuBuilderTests {
    @Test
    func appIconSourcePrefersBundledPngResource() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let bundleDirectory = temporaryDirectory.appendingPathComponent("IconFixture.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.raphhgg.codexpill.tests.iconfixture</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
        </dict>
        </plist>
        """.write(to: bundleDirectory.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let image = NSImage(size: NSSize(width: 12, height: 12))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 12).fill()
        image.unlockFocus()
        let representation = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let data = try #require(representation.representation(using: .png, properties: [:]))
        try data.write(to: bundleDirectory.appendingPathComponent("AppIcon.png"))

        let bundle = try #require(Bundle(url: bundleDirectory))

        let icon = try #require(NSImage.codexPillAppIcon(bundle: bundle))

        #expect(icon.size.width > 0)
        #expect(icon.size.height > 0)
    }

    @Test
    func realAlertPresenterSuppressesInfoAlertsDuringAutomatedTests() {
        let presenter = SystemAlertPresenter(
            environment: [AppRuntimeEnvironment.xctestConfigurationFilePathEnvironmentKey: "/tmp/test.xctestconfiguration"]
        )

        presenter.presentInfo(
            MenuBarInfoAlertRequest(
                messageText: "CodexPill Error",
                informativeText: "Permission denied",
                style: .warning,
                buttonTitle: "OK"
            )
        )
    }

    @Test
    func realPresentersCancelInteractivePromptsDuringAutomatedTests() async {
        let alertPresenter = SystemAlertPresenter(
            environment: [AppRuntimeEnvironment.xctestConfigurationFilePathEnvironmentKey: "/tmp/test.xctestconfiguration"]
        )
        let panelPresenter = SystemPanelPresenter(
            environment: [AppRuntimeEnvironment.xctestConfigurationFilePathEnvironmentKey: "/tmp/test.xctestconfiguration"]
        )

        let textValue = alertPresenter.presentTextInput(
            MenuBarTextInputAlertRequest(
                messageText: "Rename",
                informativeText: "Rename account",
                fieldTitle: "Name",
                placeholder: "Business",
                confirmTitle: "Save",
                cancelTitle: "Cancel",
                requiresNonEmptyValue: false
            )
        )
        let confirmation = alertPresenter.presentConfirmation(
            MenuBarConfirmationAlertRequest(
                messageText: "Remove",
                informativeText: "Delete account",
                confirmTitle: "Remove",
                cancelTitle: "Cancel"
            )
        )
        var cancelled = false
        let hostValue = await panelPresenter.presentHostSetup(
            MenuBarHostSetupPanelRequest(
                messageText: "Add host",
                informativeText: "Connect a host",
                fieldTitle: "SSH Destination",
                placeholder: "user@host",
                nameFieldTitle: "Host Name",
                namePlaceholder: "buildbox",
                confirmTitle: "Add Host",
                cancelTitle: "Cancel",
                idleStatusText: "Idle",
                successStatusText: "Success"
            ),
            testConnection: { _ in .success(()) },
            onCancelled: { cancelled = true }
        )

        #expect(textValue == nil)
        #expect(confirmation == false)
        #expect(hostValue == nil)
        #expect(cancelled)
    }

    @Test
    func statusItemContentOptionsAreDisabledWhenNoStatusDataExists() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: false)),
            target: coordinator
        )

        let contentMenu = try #require(statusItemContentMenu(in: menu))
        let iconOnly = try #require(contentMenu.items.first(where: { $0.title == "Icon Only" }))
        let iconAndText = try #require(contentMenu.items.first(where: { $0.title == "Icon + Text" }))
        let textOnHover = try #require(contentMenu.items.first(where: { $0.title == "Text on Hover" }))

        #expect(iconOnly.isEnabled)
        #expect(iconOnly.action != nil)
        #expect(iconAndText.state == .off)
        #expect(!iconAndText.isEnabled)
        #expect(iconAndText.action == nil)
        #expect(textOnHover.state == .off)
        #expect(!textOnHover.isEnabled)
        #expect(textOnHover.action == nil)
    }

    @Test
    func menuIncludesDiagnosticReportExportActionNearAbout() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let exportIndex = try #require(menu.items.firstIndex(where: { $0.title == "Diagnostics…" }))
        let aboutIndex = try #require(menu.items.firstIndex(where: { $0.title == "About" }))
        let export = menu.items[exportIndex]

        #expect(exportIndex < aboutIndex)
        #expect(export.action == #selector(MenuBarCoordinator.exportDiagnosticReport))
        #expect(export.target === coordinator)
        #expect(export.isEnabled)
    }

    @Test
    func quitItemReservesIconColumnForStableTextAlignment() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let quit = try #require(menu.items.first(where: { $0.title == "Quit" }))

        #expect(quit.action == #selector(MenuBarCoordinator.quitApp))
        #expect(quit.keyEquivalent == "q")
        #expect(quit.image?.size == NSSize(width: 16, height: 16))
    }

    @Test
    func exportDiagnosticReportActionShowsDisclosureBeforePresentingRedactedReport() throws {
        let alertPresenter = AlertPresenterProbe()
        alertPresenter.confirmationResponse = true
        let presenter = DiagnosticReportPresenterProbe()
        let (coordinator, _) = try makeCoordinatorWithStatusItem(
            alertPresenter: alertPresenter,
            diagnosticReportPresenter: presenter
        )

        coordinator.exportDiagnosticReport()

        let disclosure = try #require(alertPresenter.confirmationRequests.first)
        #expect(disclosure.messageText == "Export Diagnostics?")
        #expect(disclosure.confirmTitle == "Export")
        #expect(disclosure.cancelTitle == "Cancel")
        let report = try #require(presenter.reports.first)
        #expect(report.schemaVersion == 1)
        #expect(report.redactionManifest.aliasScope == "per-export")
        #expect(report.events.contains(where: { $0.name == "menu_action" }))
    }

    @Test
    func exportDiagnosticReportActionCancelsBeforeSavePanelWhenDisclosureIsRejected() throws {
        let alertPresenter = AlertPresenterProbe()
        alertPresenter.confirmationResponse = false
        let presenter = DiagnosticReportPresenterProbe()
        let (coordinator, _) = try makeCoordinatorWithStatusItem(
            alertPresenter: alertPresenter,
            diagnosticReportPresenter: presenter
        )

        coordinator.exportDiagnosticReport()

        #expect(alertPresenter.confirmationRequests.map(\.messageText) == ["Export Diagnostics?"])
        #expect(presenter.reports.isEmpty)
    }

    @Test
    func liveValidationSnapshotCapturesStatusItemContentMetadata() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let state = makeState(activeAccount: makeAccount(name: "Active", withRateLimits: false))
        let menu = builder.makeMenu(state: state, target: coordinator)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, menu: menu)

        let display = try #require(snapshot.menuItems.first(where: { $0.title == "Preferences" }))
        let content = try #require(display.children.first(where: { $0.title == "Menu Bar Label" }))
        let iconOnly = try #require(content.children.first(where: { $0.title == "Icon Only" }))
        let iconAndText = try #require(content.children.first(where: { $0.title == "Icon + Text" }))
        let textOnHover = try #require(content.children.first(where: { $0.title == "Text on Hover" }))

        #expect(iconOnly.isEnabled)
        #expect(iconOnly.hasAction)
        #expect(iconOnly.actionSelector == "selectStatusBarDisplayMode:")
        #expect(iconOnly.state == "on")
        #expect(!iconAndText.isEnabled)
        #expect(!iconAndText.hasAction)
        #expect(iconAndText.actionSelector == nil)
        #expect(iconAndText.state == "off")
        #expect(!textOnHover.isEnabled)
        #expect(!textOnHover.hasAction)
        #expect(textOnHover.actionSelector == nil)
        #expect(textOnHover.state == "off")
    }

    @Test
    func statusItemContentOptionsStaySelectableWhenStatusDataExists() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let contentMenu = try #require(statusItemContentMenu(in: menu))
        let iconAndText = try #require(contentMenu.items.first(where: { $0.title == "Icon + Text" }))
        let textOnHover = try #require(contentMenu.items.first(where: { $0.title == "Text on Hover" }))

        #expect(iconAndText.isEnabled)
        #expect(iconAndText.action != nil)
        #expect(textOnHover.isEnabled)
        #expect(textOnHover.action != nil)
    }

    @Test
    func revealShortcutRowDisplaysShortcutWithNativeKeyEquivalent() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let shortcut = KeyboardShortcut(keyCode: 11, modifiers: [.control, .shift])
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                revealStatusItemTitleShortcut: shortcut
            ),
            target: coordinator
        )

        let contentMenu = try #require(statusItemContentMenu(in: menu))
        let revealShortcut = try #require(contentMenu.items.first(where: { $0.title.hasPrefix("Reveal Shortcut…") }))

        #expect(revealShortcut.attributedTitle?.string.isEmpty ?? true)
        #expect(revealShortcut.keyEquivalent == "b")
        #expect(revealShortcut.keyEquivalentModifierMask == [.control, .shift])
        #expect(revealShortcut.action == #selector(MenuBarCoordinator.configureRevealStatusItemTitleShortcut(_:)))
    }

    @Test
    func revealShortcutRowDisplaysNoneWhenShortcutIsCleared() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                revealStatusItemTitleShortcut: nil
            ),
            target: coordinator
        )

        let contentMenu = try #require(statusItemContentMenu(in: menu))
        let revealShortcut = try #require(contentMenu.items.first(where: { $0.title.hasPrefix("Reveal Shortcut…") }))

        #expect(revealShortcut.keyEquivalent == "")
        #expect(revealShortcut.keyEquivalentModifierMask.isEmpty)
    }

    @Test
    func addAccountIsDirectMenuActionWhenHostsAreConfigured() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [makeAccount(name: "Other", withRateLimits: true)],
                remoteHosts: [makeRemoteHost(activeAccount: nil)]
            ),
            target: coordinator
        )

        let addAccount = try #require(menu.items.first(where: { $0.title == "Add Account…" }))

        #expect(addAccount.submenu == nil)
        #expect(addAccount.isEnabled)
        #expect(addAccount.action == #selector(MenuBarCoordinator.addAccount))
    }

    @Test
    func notificationsSubmenuReflectsPersistedToggleState() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                notificationsWhenBlockedEnabled: true,
                notificationsWhenOutEnabled: false
            ),
            target: coordinator
        )

        let notifications = try #require(menu.items.first(where: { $0.title == "Notifications" }))
        let submenu = try #require(notifications.submenu)
        let whenBlocked = try #require(submenu.items.first(where: { $0.title == "Account Available" }))
        let whenOut = try #require(submenu.items.first(where: { $0.title == "Current Runs Out" }))

        #expect(whenBlocked.state == .on)
        #expect(whenBlocked.action == #selector(MenuBarCoordinator.toggleNotificationsWhenBlocked(_:)))
        #expect(whenOut.state == .off)
        #expect(whenOut.action == #selector(MenuBarCoordinator.toggleNotificationsWhenOut(_:)))
    }

    @Test
    func notificationsSubmenuDoesNotShowEnableNotificationsWhenAppNotificationsAreOff() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                notificationAuthorizationState: .authorized
            ),
            target: coordinator
        )

        let submenu = try notificationsSubmenu(in: menu)

        #expect(!submenu.items.contains(where: { $0.title == "Enable Notifications…" }))
        #expect(!submenu.items.contains(where: { $0.title == "Enable in macOS Settings…" }))
    }

    @Test
    func notificationsSubmenuDoesNotShowEnableNotificationsWhenAuthorizationIsUnknown() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                notificationAuthorizationState: .unknown
            ),
            target: coordinator
        )

        let submenu = try notificationsSubmenu(in: menu)

        #expect(!submenu.items.contains(where: { $0.title == "Enable Notifications…" }))
        #expect(!submenu.items.contains(where: { $0.title == "Enable in macOS Settings…" }))
    }

    @Test
    func notificationsSubmenuHidesRecoveryWhenAppNotificationsAreOnAndAuthorized() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                notificationsWhenBlockedEnabled: true,
                notificationAuthorizationState: .authorized
            ),
            target: coordinator
        )

        let submenu = try notificationsSubmenu(in: menu)

        #expect(!submenu.items.contains(where: { $0.title == "Enable Notifications…" }))
        #expect(!submenu.items.contains(where: { $0.title == "Enable in macOS Settings…" }))
    }

    @Test
    func notificationsSubmenuShowsMacSettingsRecoveryWhenMacNotificationsAreDenied() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                notificationsWhenBlockedEnabled: true,
                notificationAuthorizationState: .denied
            ),
            target: coordinator
        )

        let submenu = try notificationsSubmenu(in: menu)
        let enable = try #require(submenu.items.first(where: { $0.title == "Enable in macOS Settings…" }))

        #expect(enable.action == #selector(MenuBarCoordinator.enableNotifications(_:)))
    }

    @Test
    func notificationsSubmenuDisablesEffectiveTogglesWhenMacNotificationsAreDenied() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                notificationsWhenBlockedEnabled: true,
                notificationsWhenOutEnabled: true,
                notificationAuthorizationState: .denied
            ),
            target: coordinator
        )

        let submenu = try notificationsSubmenu(in: menu)
        let whenBlocked = try #require(submenu.items.first(where: { $0.title == "Account Available" }))
        let whenOut = try #require(submenu.items.first(where: { $0.title == "Current Runs Out" }))

        #expect(whenBlocked.state == .off)
        #expect(!whenBlocked.isEnabled)
        #expect(whenOut.state == .off)
        #expect(!whenOut.isEnabled)
    }

    @Test
    func visibleAccountsUseNativeSubmenusForSwitching() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let business3 = makeAccount(name: "Business 3", withRateLimits: true)
        let business4 = makeAccount(name: "Business 4", withRateLimits: true)
        let business2 = makeAccount(name: "Business 2", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [business3, business4, business2]
            ),
            target: coordinator
        )

        let visibleRow = try #require(
            menu.items.first(where: { $0.submenu?.title == business3.name })
        )
        let submenu = try #require(visibleRow.submenu)
        let emailItem = try #require(submenu.items.first)
        let statusItem = try #require(submenu.items.dropFirst().first)
        let localAction = try #require(submenu.items.first(where: { $0.title == "Switch on This Mac" }))
        let renameAction = try #require(submenu.items.first(where: { $0.title == "Rename…" }))
        let removeAction = try #require(submenu.items.first(where: { $0.title == "Remove…" }))
        let localActionIndex = try #require(submenu.items.firstIndex(where: { $0.title == "Switch on This Mac" }))
        let renameIndex = try #require(submenu.items.firstIndex(where: { $0.title == "Rename…" }))
        let removeIndex = try #require(submenu.items.firstIndex(where: { $0.title == "Remove…" }))

        #expect(visibleRow.view == nil)
        #expect(visibleRow.attributedTitle?.string.contains("S ") == true)
        #expect(visibleRow.attributedTitle?.string.contains("W ") == true)
        #expect(visibleRow.attributedTitle?.string.contains("Local") == false)
        #expect(visibleRow.representedObject as? String == business3.id.uuidString)
        #expect(visibleRow.action != #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(visibleRow.isEnabled == true)
        #expect(emailItem.title == "business 3@example.com")
        #expect(emailItem.isEnabled == false)
        #expect(statusItem.title == "Not currently in use")
        #expect(statusItem.isEnabled == false)
        #expect(localActionIndex > 1)
        #expect(localAction.action == #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(localAction.target === coordinator)
        #expect(localAction.representedObject as? String == business3.id.uuidString)
        #expect(renameAction.action == #selector(MenuBarCoordinator.renameAccount(_:)))
        #expect(renameAction.representedObject as? String == business3.id.uuidString)
        #expect(removeAction.action == #selector(MenuBarCoordinator.removeAccount(_:)))
        #expect(removeAction.representedObject as? String == business3.id.uuidString)
        #expect(submenu.items[renameIndex - 1].isSeparatorItem)
        #expect(removeIndex == renameIndex + 1)
        #expect(menu.autoenablesItems)
    }

    @Test
    func singleAccountWithoutHostsUsesAccountManagementSubmenu() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let active = makeAccount(name: "Personal", withRateLimits: true)
        let state = makeState(activeAccount: active)
        let menu = builder.makeMenu(state: state, target: coordinator)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, menu: menu)

        let accountMenu = try #require(menu.items.first(where: { $0.title == "Account" })?.submenu)
        let addAccount = try #require(accountMenu.items.first(where: { $0.title == "Add Account…" }))
        let rename = try #require(accountMenu.items.first(where: { $0.title == "Rename…" }))
        let remove = try #require(accountMenu.items.first(where: { $0.title == "Remove…" }))

        #expect(snapshot.sections.contains(where: { $0.title == "Accounts" }) == false)
        #expect(snapshot.sections.contains(where: { $0.title == "Other Accounts" }) == false)
        #expect(menu.items.contains(where: { $0.title == "Add Account…" }) == false)
        #expect(addAccount.action == #selector(MenuBarCoordinator.addAccount))
        #expect(rename.action == #selector(MenuBarCoordinator.renameAccount(_:)))
        #expect(rename.representedObject as? String == active.id.uuidString)
        #expect(remove.action == #selector(MenuBarCoordinator.removeAccount(_:)))
        #expect(remove.representedObject as? String == active.id.uuidString)
    }

    @Test
    func multipleAccountsWithoutHostsShowsOtherAccountsAndManagesActiveAccountSeparately() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let active = makeAccount(name: "Personal", withRateLimits: true)
        let business1 = makeAccount(name: "Business 1", withRateLimits: true)
        let business2 = makeAccount(name: "Business 2", withRateLimits: true)
        let state = makeState(
            activeAccount: active,
            inactiveAccounts: [business1, business2]
        )
        let menu = builder.makeMenu(state: state, target: coordinator)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, menu: menu)

        let accountSection = try #require(snapshot.sections.first(where: { $0.title == "Other Accounts" }))
        let activeRow = menu.items.first(where: { $0.submenu?.title == active.name })
        let accountItem = try #require(menu.items.first(where: { $0.title == "Account" }))
        let accountMenu = try #require(accountItem.submenu)
        let rename = try #require(accountMenu.items.first(where: { $0.title == "Rename…" }))
        let remove = try #require(accountMenu.items.first(where: { $0.title == "Remove…" }))
        let addAccount = try #require(accountMenu.items.first(where: { $0.title == "Add Account…" }))

        #expect(accountSection.items.count == 2)
        #expect(accountSection.items.allSatisfy { !$0.contains(active.name) })
        #expect(activeRow == nil)
        #expect(accountItem.image != nil)
        #expect(addAccount.action == #selector(MenuBarCoordinator.addAccount))
        #expect(menu.items.contains(where: { $0.title == "Add Account…" }) == false)
        #expect(rename.representedObject as? String == active.id.uuidString)
        #expect(remove.representedObject as? String == active.id.uuidString)
    }

    @Test
    func configuredHostsKeepFullAccountsListForTargetActions() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let active = makeAccount(name: "Personal", withRateLimits: true)
        let business = makeAccount(name: "Business 1", withRateLimits: true)
        let state = makeState(
            activeAccount: active,
            inactiveAccounts: [business],
            remoteHosts: [makeRemoteHost(activeAccount: nil)]
        )
        let menu = builder.makeMenu(state: state, target: coordinator)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, menu: menu)

        let accountSection = try #require(snapshot.sections.first(where: { $0.title == "Accounts" }))
        let activeRow = try #require(menu.items.first(where: { $0.submenu?.title == active.name }))
        let activeSubmenu = try #require(activeRow.submenu)

        #expect(accountSection.items.contains(where: { $0.contains(active.name) }))
        #expect(activeSubmenu.items.contains(where: { $0.title == "Install on devbox and switch" }))
        #expect(menu.items.contains(where: { $0.title == "Account" }) == false)
    }

    @Test
    func inactiveAccountSubmenuShowsNoEmailFallbackBeforeUsage() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        var account = makeAccount(name: "Business 3", withRateLimits: true)
        account.email = nil
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [account]
            ),
            target: coordinator
        )

        let accountItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(account.name) == true }))
        let submenu = try #require(accountItem.submenu)
        let emailItem = try #require(submenu.items.first)
        let statusItem = try #require(submenu.items.dropFirst().first)

        #expect(emailItem.title == "No email")
        #expect(emailItem.isEnabled == false)
        #expect(statusItem.title == "Not currently in use")
        #expect(statusItem.isEnabled == false)
    }

    @Test
    func moreAccountsRowUsesTextOnlyDisclosureLabel() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [
                    makeAccount(name: "Business 3", withRateLimits: true),
                    makeAccount(name: "Business 4", withRateLimits: true),
                    makeAccount(name: "Business 2", withRateLimits: true),
                    makeAccount(name: "Business 1", withRateLimits: true)
                ]
            ),
            target: coordinator
        )

        let moreAccounts = try #require(menu.items.first(where: { $0.title == "More Accounts…" }))
        let firstOverflowAccount = try #require(moreAccounts.submenu?.items.first)
        let overflowSubmenu = try #require(firstOverflowAccount.submenu)
        let overflowEmail = try #require(overflowSubmenu.items.first)
        let overflowUsage = try #require(overflowSubmenu.items.dropFirst().first)
        let overflowSwitch = try #require(overflowSubmenu.items.first(where: { $0.title == "Switch on This Mac" }))

        #expect(moreAccounts.image == nil)
        #expect(moreAccounts.submenu?.title == "More Accounts…")
        #expect(!firstOverflowAccount.title.isEmpty)
        #expect(
            ["Business 1", "Business 2", "Business 3", "Business 4"]
                .contains(where: { firstOverflowAccount.title.contains($0) })
        )
        #expect(firstOverflowAccount.submenu != nil)
        #expect(firstOverflowAccount.action != #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(overflowEmail.title.hasSuffix("@example.com"))
        #expect(overflowEmail.isEnabled == false)
        #expect(overflowUsage.title == "Not currently in use")
        #expect(overflowUsage.isEnabled == false)
        #expect(overflowSwitch.action == #selector(MenuBarCoordinator.switchAccount(_:)))
    }

    @Test
    func inactiveAccountUsesTargetSubmenuWhenRemoteHostIsPresent() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let inactive = makeAccount(name: "Business 3", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [inactive],
                remoteHosts: [makeRemoteHost(
                    activeAccount: makeAccount(name: "Remote", withRateLimits: true),
                    deployedAccountIDs: [inactive.id]
                )]
            ),
            target: coordinator
        )

        let accountItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(inactive.name) == true }))
        let submenu = try #require(accountItem.submenu)
        let emailItem = try #require(submenu.items.first)
        let statusItem = try #require(submenu.items.first(where: { $0.title == "Not currently in use" }))
        let localAction = try #require(submenu.items.first(where: { $0.title == "Switch on This Mac" }))
        let remoteAction = try #require(submenu.items.first(where: { $0.title == "Switch on devbox" }))
        let renameAction = try #require(submenu.items.first(where: { $0.title == "Rename…" }))
        let removeAction = try #require(submenu.items.first(where: { $0.title == "Remove…" }))

        #expect(accountItem.submenu === submenu)
        #expect(accountItem.attributedTitle?.string.contains("S ") == true)
        #expect(accountItem.attributedTitle?.string.contains("W ") == true)
        #expect(accountItem.attributedTitle?.string.contains("Remote") == false)
        #expect(emailItem.title == "business 3@example.com")
        #expect(emailItem.isEnabled == false)
        #expect(statusItem.isEnabled == false)
        #expect(localAction.action == #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(localAction.representedObject as? String == inactive.id.uuidString)
        #expect(localAction.target === coordinator)
        #expect(remoteAction.action == #selector(MenuBarCoordinator.switchAccountOnHost(_:)))
        #expect(remoteAction.target === coordinator)
        #expect(renameAction.action == #selector(MenuBarCoordinator.renameAccount(_:)))
        #expect(removeAction.action == #selector(MenuBarCoordinator.removeAccount(_:)))
        let remotePayload = try #require(remoteAction.representedObject as? HostAccountMenuItemPayload)
        #expect(remotePayload.accountID == inactive.id)
        #expect(remotePayload.hostDestination == "user@devbox")
    }

    @Test
    func inactiveAccountSubmenuShowsPendingAndFailedRemoteUsageStates() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let pending = makeAccount(name: "Business 3", withRateLimits: true)
        let failed = makeAccount(name: "Business 4", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [pending, failed],
                remoteHosts: [
                    makeRemoteHost(
                        name: "buildbox",
                        desiredAccount: pending,
                        activeAccount: nil,
                        verificationStatus: .verifying
                    ),
                    makeRemoteHost(
                        name: "debian-vm",
                        destination: "user@debian-vm",
                        connectionState: .disconnected,
                        desiredAccount: failed,
                        activeAccount: nil,
                        verificationStatus: .failed,
                        lastVerificationError: "debian-vm is using Business 1, not Business 4."
                    )
                ]
            ),
            target: coordinator
        )

        let pendingItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(pending.name) == true }))
        let failedItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(failed.name) == true }))
        let pendingEmail = try #require(pendingItem.submenu?.items.first)
        let failedEmail = try #require(failedItem.submenu?.items.first)
        let pendingStatus = try #require(pendingItem.submenu?.items.dropFirst().first)
        let failedStatus = try #require(failedItem.submenu?.items.dropFirst().first)

        #expect(pendingEmail.title == "business 3@example.com")
        #expect(failedEmail.title == "business 4@example.com")
        #expect(pendingStatus.title == "Pending on: buildbox")
        #expect(failedStatus.title == "Verification failed on: debian-vm")
    }

    @Test
    func failedHostSubmenuOffersAdoptDetectedAccountAction() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let desired = makeAccount(name: "Business 2", withRateLimits: true)
        let detected = makeAccount(name: "Business 1", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: nil,
                inactiveAccounts: [desired],
                remoteHosts: [
                    makeRemoteHost(
                        name: "buildbox",
                        destination: "user@buildbox",
                        connectionState: .connected,
                        desiredAccount: desired,
                        activeAccount: nil,
                        detectedAccount: detected,
                        verificationStatus: .failed,
                        lastVerificationError: "buildbox is using Business 1, not Business 2."
                    )
                ]
            ),
            target: coordinator
        )

        let hostsMenu = try #require(menu.items.first(where: { $0.title == "Hosts" })?.submenu)
        let hostSubmenu = try #require(hostsMenu.items.first(where: { $0.title == "buildbox" })?.submenu)
        let detectedRow = try #require(hostSubmenu.items.first(where: { $0.title == "Detected account: Business 1" }))
        let adoptAction = try #require(hostSubmenu.items.first(where: { $0.title == "Use Detected Account (Business 1)" }))
        let reverify = try #require(hostSubmenu.items.first(where: { $0.title == "Re-verify Remote Account" }))

        #expect(detectedRow.isEnabled == false)
        #expect(adoptAction.action == #selector(MenuBarCoordinator.adoptDetectedRemoteAccount(_:)))
        #expect(adoptAction.target === coordinator)
        let payload = try #require(adoptAction.representedObject as? HostAccountMenuItemPayload)
        #expect(payload.accountID == detected.id)
        #expect(payload.hostDestination == "user@buildbox")
        #expect(reverify.action == #selector(MenuBarCoordinator.reverifyHost(_:)))
    }

    @Test
    func inactiveAccountSubmenuAddsOneHostTargetPerConfiguredHost() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let inactive = makeAccount(name: "Business 3", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [inactive],
                remoteHosts: [
                    makeRemoteHost(
                        name: "buildbox",
                        destination: "user@buildbox",
                        activeAccount: makeAccount(name: "Remote 1", withRateLimits: true),
                        deployedAccountIDs: [inactive.id]
                    ),
                    makeRemoteHost(
                        name: "debian-vm",
                        destination: "user@debian-vm",
                        connectionState: .disconnected,
                        activeAccount: makeAccount(name: "Remote 2", withRateLimits: true),
                        deployedAccountIDs: []
                    )
                ]
            ),
            target: coordinator
        )

        let accountItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(inactive.name) == true }))
        let submenu = try #require(accountItem.submenu)
        let buildboxAction = try #require(submenu.items.first(where: { $0.title == "Switch on buildbox" }))
        let debianAction = try #require(submenu.items.first(where: { $0.title == "Install on debian-vm and switch" }))

        let buildboxPayload = try #require(buildboxAction.representedObject as? HostAccountMenuItemPayload)
        let debianPayload = try #require(debianAction.representedObject as? HostAccountMenuItemPayload)

        #expect(buildboxAction.action == #selector(MenuBarCoordinator.switchAccountOnHost(_:)))
        #expect(debianAction.action == #selector(MenuBarCoordinator.switchAccountOnHost(_:)))
        #expect(buildboxPayload.hostDestination == "user@buildbox")
        #expect(debianPayload.hostDestination == "user@debian-vm")
    }

    @Test
    func hostsSubmenuOffersAddHostWhenNoHostIsConfigured() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let hostsMenu = try #require(menu.items.first(where: { $0.title == "Hosts" })?.submenu)
        let addHost = try #require(hostsMenu.items.first(where: { $0.title == "Add Host…" }))

        #expect(addHost.action == #selector(MenuBarCoordinator.addHost(_:)))
        #expect(hostsMenu.items.contains(where: { $0.title == "Remove Host" }) == false)
    }

    @Test
    func hostsSubmenuShowsConfiguredHostAndRemoveAction() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [makeRemoteHost(activeAccount: nil)]
            ),
            target: coordinator
        )

        let hostsMenu = try #require(menu.items.first(where: { $0.title == "Hosts" })?.submenu)
        let hostItem = try #require(hostsMenu.items.first(where: { $0.title == "devbox" }))
        let hostSubmenu = try #require(hostItem.submenu)
        let hostStatus = try #require(hostSubmenu.items.first(where: { $0.title == "devbox (user@devbox)" }))
        let removeHost = try #require(hostSubmenu.items.first(where: { $0.title == "Remove Host" }))

        #expect(hostStatus.isEnabled == false)
        #expect(removeHost.action == #selector(MenuBarCoordinator.removeHost(_:)))
        let removePayload = try #require(removeHost.representedObject as? HostSelectionMenuItemPayload)
        #expect(removePayload.hostDestination == "user@devbox")
    }

    @Test
    func hostsSubmenuOffersReverifyActionWhenHostHasDisplayAccount() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let desired = makeAccount(name: "Business 2", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [
                    makeRemoteHost(
                        desiredAccount: desired,
                        activeAccount: nil,
                        verificationStatus: .failed,
                        lastVerificationError: "devbox is using Business 1, not Business 2."
                    )
                ]
            ),
            target: coordinator
        )

        let hostsMenu = try #require(menu.items.first(where: { $0.title == "Hosts" })?.submenu)
        let hostItem = try #require(hostsMenu.items.first(where: { $0.title == "devbox" }))
        let hostSubmenu = try #require(hostItem.submenu)
        let reverify = try #require(hostSubmenu.items.first(where: { $0.title == "Re-verify Remote Account" }))
        let payload = try #require(reverify.representedObject as? HostSelectionMenuItemPayload)

        #expect(reverify.action == #selector(MenuBarCoordinator.reverifyHost(_:)))
        #expect(reverify.target === coordinator)
        #expect(payload.hostDestination == "user@devbox")
    }

    @Test
    func hostsSubmenuDisablesReverifyActionWhileHostIsAlreadyVerifying() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let desired = makeAccount(name: "Business 2", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [
                    makeRemoteHost(
                        desiredAccount: desired,
                        activeAccount: nil,
                        verificationStatus: .verifying
                    )
                ]
            ),
            target: coordinator
        )

        let hostsMenu = try #require(menu.items.first(where: { $0.title == "Hosts" })?.submenu)
        let hostItem = try #require(hostsMenu.items.first(where: { $0.title == "devbox" }))
        let hostSubmenu = try #require(hostItem.submenu)
        let reverify = try #require(hostSubmenu.items.first(where: { $0.title == "Re-verify Remote Account" }))

        #expect(reverify.isEnabled == false)
    }

    @Test
    func hostsSubmenuOmitsReverifyActionWhenHostHasNoDesiredOrVerifiedAccount() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [
                    makeRemoteHost(desiredAccount: nil, activeAccount: nil, verificationStatus: .unverified)
                ]
            ),
            target: coordinator
        )

        let hostsMenu = try #require(menu.items.first(where: { $0.title == "Hosts" })?.submenu)
        let hostItem = try #require(hostsMenu.items.first(where: { $0.title == "devbox" }))
        let hostSubmenu = try #require(hostItem.submenu)

        #expect(hostSubmenu.items.contains(where: { $0.title == "Re-verify Remote Account" }) == false)
    }

    @Test
    func hostsSubmenuListsConnectedAndDisconnectedHosts() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [
                    makeRemoteHost(
                        name: "buildbox",
                        destination: "user@buildbox",
                        connectionState: .connected,
                        activeAccount: makeAccount(name: "Remote 1", withRateLimits: true)
                    ),
                    makeRemoteHost(
                        name: "debian-vm",
                        destination: "user@debian-vm",
                        connectionState: .disconnected,
                        activeAccount: makeAccount(name: "Remote 2", withRateLimits: true)
                    )
                ]
            ),
            target: coordinator
        )

        let hostsMenu = try #require(menu.items.first(where: { $0.title == "Hosts" })?.submenu)
        let buildbox = try #require(hostsMenu.items.first(where: { $0.title == "buildbox" })?.submenu)
        let debian = try #require(hostsMenu.items.first(where: { $0.title == "debian-vm" })?.submenu)
        let connectedStatus = try #require(buildbox.items.first(where: { $0.title == "Status: Connected" }))
        let disconnectedStatus = try #require(debian.items.first(where: { $0.title == "Status: Disconnected" }))

        #expect(connectedStatus.isEnabled == false)
        #expect(disconnectedStatus.isEnabled == false)
    }

    @Test
    func inactiveAccountSubmenuIncludesAllConfiguredHosts() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let inactive = makeAccount(name: "Business 3", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [inactive],
                remoteHosts: [
                    makeRemoteHost(activeAccount: nil),
                    RemoteHostMenuState(
                        name: "buildbox",
                        destination: "user@buildbox",
                        connectionState: .connected,
                        activeAccount: nil,
                        deployedAccountIDs: []
                    )
                ]
            ),
            target: coordinator
        )

        let accountItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(inactive.name) == true }))
        let submenu = try #require(accountItem.submenu)

        #expect(submenu.items.contains(where: { $0.title == "Install on devbox and switch" }))
        #expect(submenu.items.contains(where: { $0.title == "Install on buildbox and switch" }))
    }

    @Test
    func remoteAccountSectionUsesHostedCardInsteadOfPlainTextRow() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [makeRemoteHost(activeAccount: makeAccount(name: "Business 2", withRateLimits: true))]
            ),
            target: coordinator
        )

        #expect(menu.items.contains(where: { $0.title.contains("devbox • Connected") }) == false)
        #expect(menu.items.filter { $0.view != nil }.count >= 4)
    }

    @Test
    func pacingPrototypeMenuIsHiddenByDefault() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        #expect(menu.items.contains(where: { $0.title == "Pacing Prototypes" }) == false)
    }

    @Test
    func pacingPrototypeMenuShowsAllDebugVariantsWhenEnabled() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                showsPacingPrototypeMenu: true
            ),
            target: coordinator
        )

        let prototypes = try #require(menu.items.first(where: { $0.title == "Pacing Prototypes" }))
        let submenu = try #require(prototypes.submenu)

        #expect(submenu.items.map(\.title) == PacingPrototypeVariant.allCases.map(\.title))
        #expect(submenu.items.allSatisfy { $0.view != nil })
    }

    @Test
    func activeAccountHostedViewFitsWithinConfiguredMenuWidth() {
        let view = NSHostingView(
            rootView: ActiveAccountMenuContent(
                account: makeAccount(name: "Business 2", withRateLimits: true),
                locations: [],
                showsUpdatedTime: true,
                progressAccentColor: .blue,
                showsPacingMarkers: true
            )
        )

        view.frame = NSRect(x: 0, y: 0, width: 372, height: 1)
        view.layoutSubtreeIfNeeded()

        #expect(view.fittingSize.width <= 372)
    }

    @Test
    func activeAccountsSectionAddsSubtleDividerBetweenCardsOnly() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [
                    makeRemoteHost(activeAccount: makeAccount(name: "Business 2", withRateLimits: true))
                ]
            ),
            target: coordinator
        )

        let hostedViewNames = menu.items.compactMap(\.view).map { String(describing: type(of: $0)) }

        #expect(hostedViewNames.filter { $0.contains("ActiveAccountMenuContent") }.count == 2)
        #expect(hostedViewNames.filter { $0.contains("ActiveAccountCardDivider") }.count == 1)
    }

    @Test
    func singleActiveAccountDoesNotAddActiveCardDivider() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let hostedViewNames = menu.items.compactMap(\.view).map { String(describing: type(of: $0)) }

        #expect(hostedViewNames.filter { $0.contains("ActiveAccountMenuContent") }.count == 1)
        #expect(hostedViewNames.contains(where: { $0.contains("ActiveAccountCardDivider") }) == false)
    }

    @Test
    func sectionHeaderAndActiveCardUseSameComputedWidth() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Personal", withRateLimits: true),
                inactiveAccounts: [
                    makeAccount(name: "Business 1", withRateLimits: true),
                    makeAccount(name: "Business 2", withRateLimits: true)
                ]
            ),
            target: coordinator
        )

        let headerWidth = try #require(menu.items.first?.view?.frame.width)
        let cardWidth = try #require(menu.items.dropFirst().first?.view?.frame.width)

        #expect(headerWidth == cardWidth)
        #expect(headerWidth >= 372)
    }

    @Test
    func wideAccountRowsExpandHostedSectionsToMatchMenuBudget() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let wideAccountName = "Extremely Long Business Account Name For Width Regression Coverage"
        let wideAccount = CodexAccount(
            id: UUID(),
            name: wideAccountName,
            snapshotFileName: "wide-account.json",
            createdAt: now,
            updatedAt: now,
            email: "wide@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 100,
                    resetsAt: now.addingTimeInterval((4 * 60 + 59) * 60),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 78,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            )
        )
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Personal", withRateLimits: true),
                inactiveAccounts: [wideAccount]
            ),
            target: coordinator
        )

        let headerWidth = try #require(menu.items.first?.view?.frame.width)
        let widestLocalRow = try #require(
            menu.items.first(where: { $0.submenu?.title == wideAccountName })
        )
        let rowWidth = inactiveAccountTitleWidth(
            for: wideAccount,
            displayName: compactMenuRowDisplayName(for: wideAccountName),
            placement: nil,
            menuContentWidth: headerWidth,
            now: now
        )

        #expect(headerWidth == 372)
        #expect(widestLocalRow.view == nil)
        #expect(widestLocalRow.attributedTitle?.string.contains("…") == true)
        #expect(rowWidth > 0)
    }

    @Test
    func disconnectedVerifiedRemoteHostDoesNotRenderPrimaryRemoteSection() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [RemoteHostMenuState(
                    name: "devbox",
                    destination: "user@devbox",
                    connectionState: .disconnected,
                    desiredAccount: makeAccount(name: "Business 2", withRateLimits: true),
                    activeAccount: makeAccount(name: "Business 2", withRateLimits: true)
                )]
            ),
            target: coordinator
        )

        #expect(
            menu.items
                .compactMap(\.view)
                .contains(where: { String(describing: type(of: $0)).contains("RemoteHostMenuContent") }) == false
        )
    }

    @Test
    func disconnectedFailedRemoteHostDoesNotRenderPrimaryRemoteSection() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let desired = makeAccount(name: "Business 2", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [RemoteHostMenuState(
                    name: "devbox",
                    destination: "user@devbox",
                    connectionState: .disconnected,
                    desiredAccount: desired,
                    activeAccount: nil,
                    verificationStatus: .failed,
                    lastVerificationError: "devbox is using Business 1, not Business 2."
                )]
            ),
            target: coordinator
        )

        #expect(
            menu.items
                .compactMap(\.view)
                .contains(where: { String(describing: type(of: $0)).contains("RemoteHostMenuContent") }) == false
        )
    }

    @Test
    func remoteMismatchStaysInHostSubmenuAndDoesNotRenderActiveCard() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let desired = makeAccount(name: "Business 2", withRateLimits: true)
        let detected = makeAccount(name: "Business 1", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [RemoteHostMenuState(
                    name: "buildbox",
                    destination: "user@buildbox",
                    connectionState: .connected,
                    desiredAccount: desired,
                    activeAccount: nil,
                    detectedAccount: detected,
                    verificationStatus: .failed,
                    lastVerificationError: "buildbox is using Business 1, not Business 2."
                )]
            ),
            target: coordinator
        )

        let activeCards = menu.items
            .compactMap(\.view)
            .compactMap { $0 as? NSHostingView<ActiveAccountMenuContent> }
        let hasRemoteCards = menu.items
            .compactMap(\.view)
            .contains(where: { String(describing: type(of: $0)).contains("RemoteHostMenuContent") })
        let hostsMenu = try #require(menu.items.first(where: { $0.title == "Hosts" })?.submenu)
        let hostSubmenu = try #require(hostsMenu.items.first(where: { $0.title == "buildbox" })?.submenu)
        let adoptAction = try #require(hostSubmenu.items.first(where: { $0.title == "Use Detected Account (Business 1)" }))

        #expect(activeCards.count == 1)
        #expect(activeCards.first?.rootView.account.name == "Active")
        #expect(hasRemoteCards == false)
        #expect(adoptAction.action == #selector(MenuBarCoordinator.adoptDetectedRemoteAccount(_:)))
    }

    @Test
    func inactiveAccountUsesInstallAndSwitchCopyWhenMissingOnRemoteHost() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let inactive = makeAccount(name: "Business 3", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [inactive],
                remoteHosts: [makeRemoteHost(activeAccount: nil, deployedAccountIDs: [])]
            ),
            target: coordinator
        )

        let accountItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(inactive.name) == true }))
        let submenu = try #require(accountItem.submenu)
        let remoteAction = try #require(submenu.items.first(where: { $0.title == "Install on devbox and switch" }))

        #expect(accountItem.attributedTitle?.string.contains("S ") == true)
        #expect(remoteAction.action == #selector(MenuBarCoordinator.switchAccountOnHost(_:)))
        let remotePayload = try #require(remoteAction.representedObject as? HostAccountMenuItemPayload)
        #expect(remotePayload.accountID == inactive.id)
        #expect(remotePayload.hostDestination == "user@devbox")
    }

    @Test
    func activeRemoteAccountCardAndAccountUsageResolveAgainstCanonicalSavedAccountIdentity() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let canonical = makeAccount(name: "Business 2", withRateLimits: true)
        let remoteClone = CodexAccount(
            id: UUID(),
            name: canonical.name,
            snapshotFileName: canonical.snapshotFileName,
            createdAt: canonical.createdAt,
            updatedAt: canonical.updatedAt.addingTimeInterval(60),
            email: canonical.email,
            planType: canonical.planType,
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: canonical.planType,
                primary: nil,
                secondary: canonical.rateLimits?.secondary,
                fetchedAt: canonical.updatedAt.addingTimeInterval(60)
            ),
            identity: canonical.identity
        )
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: nil,
                inactiveAccounts: [canonical],
                remoteHosts: [makeRemoteHost(name: "debian-vm", activeAccount: remoteClone)]
            ),
            target: coordinator
        )

        let remoteCard = try #require(
            menu.items
                .compactMap(\.view)
                .compactMap { $0 as? NSHostingView<ActiveAccountMenuContent> }
                .first
        )
        let accountItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(canonical.name) == true }))
        let emailItem = try #require(accountItem.submenu?.items.first)
        let usageStatusItem = try #require(accountItem.submenu?.items.dropFirst().first)

        #expect(remoteCard.rootView.account.id == canonical.id)
        #expect(remoteCard.rootView.account.rateLimits?.primary?.usedPercent == canonical.rateLimits?.primary?.usedPercent)
        #expect(remoteCard.rootView.locations == ["debian-vm"])
        #expect(emailItem.title == canonical.email)
        #expect(emailItem.isEnabled == false)
        #expect(usageStatusItem.title == "In use on: debian-vm")
    }

    @Test
    func activeAccountsSectionRendersLocalAndOneHostedCardPerConnectedHost() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                remoteHosts: [
                    makeRemoteHost(
                        activeAccount: makeAccount(name: "Business 2", withRateLimits: true)
                    ),
                    RemoteHostMenuState(
                        name: "buildbox",
                        destination: "user@buildbox",
                        connectionState: .connected,
                        activeAccount: makeAccount(name: "Business 3", withRateLimits: true),
                        deployedAccountIDs: []
                    )
                ]
            ),
            target: coordinator
        )

        let activeCards = menu.items
            .compactMap(\.view)
            .compactMap { $0 as? NSHostingView<ActiveAccountMenuContent> }
        let hasRemoteCards = menu.items
            .compactMap(\.view)
            .contains(where: { String(describing: type(of: $0)).contains("RemoteHostMenuContent") })

        #expect(activeCards.map(\.rootView.account.name) == ["Active", "Business 2", "Business 3"])
        #expect(activeCards.map(\.rootView.locations) == [["This Mac"], ["devbox"], ["buildbox"]])
        #expect(hasRemoteCards == false)
    }

    @Test
    func sameLocalAndVerifiedRemoteAccountCollapsesRemoteCardButKeepsHostSubmenu() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let active = makeAccount(name: "Business 2", withRateLimits: true)
        var remote = active
        remote.updatedAt = active.updatedAt.addingTimeInterval(60)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: active,
                remoteHosts: [
                    makeRemoteHost(
                        name: "debian-vm",
                        destination: "user@debian-vm",
                        desiredAccount: active,
                        activeAccount: remote,
                        deployedAccountIDs: [active.id]
                    )
                ]
            ),
            target: coordinator
        )

        let hasRemoteCards = menu.items
            .compactMap(\.view)
            .contains(where: { String(describing: type(of: $0)).contains("RemoteHostMenuContent") })
        let currentCard = try #require(
            menu.items
                .compactMap(\.view)
                .compactMap { $0 as? NSHostingView<ActiveAccountMenuContent> }
                .first
        )
        let hostsMenu = try #require(menu.items.first(where: { $0.title == "Hosts" })?.submenu)
        let hostSubmenu = try #require(hostsMenu.items.first(where: { $0.title == "debian-vm" })?.submenu)
        let statusRow = try #require(hostSubmenu.items.first(where: { $0.title == "Status: Connected" }))
        let desiredRow = try #require(hostSubmenu.items.first(where: { $0.title == "Desired account: Business 2" }))

        #expect(hasRemoteCards == false)
        #expect(currentCard.rootView.locations == ["This Mac", "debian-vm"])
        #expect(statusRow.isEnabled == false)
        #expect(desiredRow.isEnabled == false)
    }

    @Test
    func statusItemMenuIncludesColorCustomizationAndReset() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let preferencesMenu = try #require(menu.items.first(where: { $0.title == "Preferences" })?.submenu)
        let usageBarsMenu = try #require(preferencesMenu.items.first(where: { $0.title == "Usage Bars" })?.submenu)
        let accent = try #require(usageBarsMenu.items.first(where: { $0.title == "Accent Color…" }))
        let reset = try #require(usageBarsMenu.items.first(where: { $0.title == "Use Default" }))

        #expect(accent.action == #selector(MenuBarCoordinator.chooseProgressAccentColor(_:)))
        #expect(accent.image == nil)
        #expect(reset.action == #selector(MenuBarCoordinator.resetProgressAccentColor(_:)))
        #expect(!reset.isEnabled)
    }

    @Test
    func preferencesMenuGroupsIconAndMarkerControls() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let preferencesMenu = try #require(menu.items.first(where: { $0.title == "Preferences" })?.submenu)
        let usageBarsMenu = try #require(preferencesMenu.items.first(where: { $0.title == "Usage Bars" })?.submenu)
        let usageBarTitles = usageBarsMenu.items.map(\.title)
        let showMarkers = try #require(usageBarsMenu.items.first(where: { $0.title == "Show Pace Markers" }))

        #expect(preferencesMenu.items.map(\.title) == ["Menu Bar Label", "Icon Style", "Usage Bars", "", "Launch at Login"])
        #expect(preferencesMenu.items[3].isSeparatorItem)
        #expect(usageBarTitles == ["Show Pace Markers", "Accent Color…", "Use Default"])
        #expect(preferencesMenu.items.first(where: { $0.title == "Menu Bar Label" })?.image == nil)
        #expect(preferencesMenu.items.first(where: { $0.title == "Icon Style" })?.image == nil)
        #expect(usageBarsMenu.items.first(where: { $0.title == "Accent Color…" })?.image == nil)
        #expect(showMarkers.action == #selector(MenuBarCoordinator.togglePacingMarkers(_:)))
        #expect(showMarkers.state == .on)
    }

    @Test
    func launchAtLoginPreferenceReflectsEnabledState() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                loginItemState: .enabled
            ),
            target: try makeCoordinator()
        )

        let item = try launchAtLoginItem(in: menu)

        #expect(item.title == "Launch at Login")
        #expect(item.action == #selector(MenuBarCoordinator.toggleLaunchAtLogin(_:)))
        #expect(item.state == .on)
        #expect(item.isEnabled)
    }

    @Test
    func launchAtLoginPreferenceReflectsDisabledState() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                loginItemState: .disabled
            ),
            target: try makeCoordinator()
        )

        let item = try launchAtLoginItem(in: menu)

        #expect(item.title == "Launch at Login")
        #expect(item.action == #selector(MenuBarCoordinator.toggleLaunchAtLogin(_:)))
        #expect(item.state == .off)
        #expect(item.isEnabled)
    }

    @Test
    func launchAtLoginPreferenceOpensSettingsWhenApprovalIsRequired() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                loginItemState: .requiresApproval
            ),
            target: try makeCoordinator()
        )

        let item = try launchAtLoginItem(in: menu)

        #expect(item.title == "Launch at Login…")
        #expect(item.action == #selector(MenuBarCoordinator.openLoginItemsSettings(_:)))
        #expect(item.state == .off)
        #expect(item.isEnabled)
    }

    @Test
    func launchAtLoginPreferenceOpensSettingsWhenUnavailable() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                loginItemState: .unavailable
            ),
            target: try makeCoordinator()
        )

        let item = try launchAtLoginItem(in: menu)

        #expect(item.title == "Launch at Login…")
        #expect(item.action == #selector(MenuBarCoordinator.openLoginItemsSettings(_:)))
        #expect(item.state == .off)
        #expect(item.isEnabled)
    }

    @Test
    func coordinatorTogglesLaunchAtLoginFromDisabledToEnabled() throws {
        let loginItemController = LoginItemControllerProbe(currentState: .disabled)
        let alertPresenter = AlertPresenterProbe()
        alertPresenter.confirmationResponse = true
        let coordinator = try makeCoordinatorWithStatusItem(
            alertPresenter: alertPresenter,
            loginItemController: loginItemController
        ).0

        coordinator.toggleLaunchAtLogin(NSMenuItem())

        #expect(alertPresenter.confirmationRequests.last?.messageText == "Launch CodexPill at Login?")
        #expect(loginItemController.setEnabledCalls == [true])
    }

    @Test
    func coordinatorLeavesLaunchAtLoginDisabledWhenEnableIsCancelled() throws {
        let loginItemController = LoginItemControllerProbe(currentState: .disabled)
        let alertPresenter = AlertPresenterProbe()
        alertPresenter.confirmationResponse = false
        let coordinator = try makeCoordinatorWithStatusItem(
            alertPresenter: alertPresenter,
            loginItemController: loginItemController
        ).0

        coordinator.toggleLaunchAtLogin(NSMenuItem())

        #expect(alertPresenter.confirmationRequests.last?.messageText == "Launch CodexPill at Login?")
        #expect(loginItemController.setEnabledCalls.isEmpty)
        #expect(loginItemController.currentState == .disabled)
    }

    @Test
    func coordinatorTogglesLaunchAtLoginFromEnabledToDisabled() throws {
        let loginItemController = LoginItemControllerProbe(currentState: .enabled)
        let alertPresenter = AlertPresenterProbe()
        let coordinator = try makeCoordinatorWithStatusItem(
            alertPresenter: alertPresenter,
            loginItemController: loginItemController
        ).0

        coordinator.toggleLaunchAtLogin(NSMenuItem())

        #expect(alertPresenter.confirmationRequests.isEmpty)
        #expect(loginItemController.setEnabledCalls == [false])
    }

    @Test
    func coordinatorOpensLoginItemsSettingsWhenApprovalIsRequired() throws {
        let loginItemController = LoginItemControllerProbe(currentState: .requiresApproval)
        let settingsLauncher = LoginItemsSettingsLauncherProbe()
        let coordinator = try makeCoordinatorWithStatusItem(
            loginItemController: loginItemController,
            loginItemsSettingsLauncher: settingsLauncher
        ).0

        coordinator.toggleLaunchAtLogin(NSMenuItem())

        #expect(loginItemController.setEnabledCalls.isEmpty)
        #expect(settingsLauncher.opens == 1)
    }

    @Test
    func coordinatorOpensLoginItemsSettingsWhenLoginItemIsUnavailable() throws {
        let loginItemController = LoginItemControllerProbe(currentState: .unavailable)
        let settingsLauncher = LoginItemsSettingsLauncherProbe()
        let coordinator = try makeCoordinatorWithStatusItem(
            loginItemController: loginItemController,
            loginItemsSettingsLauncher: settingsLauncher
        ).0

        coordinator.toggleLaunchAtLogin(NSMenuItem())

        #expect(loginItemController.setEnabledCalls.isEmpty)
        #expect(settingsLauncher.opens == 1)
    }

    @Test
    func coordinatorReportsLaunchAtLoginToggleFailureWithoutChangingProbeState() throws {
        let loginItemController = LoginItemControllerProbe(currentState: .disabled)
        loginItemController.errorToThrow = LoginItemProbeError()
        let alertPresenter = AlertPresenterProbe()
        alertPresenter.confirmationResponse = true
        let coordinator = try makeCoordinatorWithStatusItem(
            alertPresenter: alertPresenter,
            loginItemController: loginItemController
        ).0

        coordinator.toggleLaunchAtLogin(NSMenuItem())

        #expect(loginItemController.setEnabledCalls.isEmpty)
        #expect(alertPresenter.confirmationRequests.last?.messageText == "Launch CodexPill at Login?")
        #expect(loginItemController.currentState == .disabled)
        #expect(alertPresenter.infoRequests.last?.informativeText == "Could not update Launch at Login. Open System Settings and try again.")
    }

    @Test
    func statusItemMenuEnablesUseDefaultWhenCustomAccentColorExists() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                progressAccentColor: NSColor(deviceRed: 0.12, green: 0.45, blue: 0.78, alpha: 1),
                hasCustomProgressAccentColor: true
            ),
            target: coordinator
        )

        let preferencesMenu = try #require(menu.items.first(where: { $0.title == "Preferences" })?.submenu)
        let usageBarsMenu = try #require(preferencesMenu.items.first(where: { $0.title == "Usage Bars" })?.submenu)
        let reset = try #require(usageBarsMenu.items.first(where: { $0.title == "Use Default" }))

        #expect(reset.action == #selector(MenuBarCoordinator.resetProgressAccentColor(_:)))
        #expect(reset.isEnabled)
    }

    @Test
    func openingMenuKeepsTheSameMenuInstanceAttachedToStatusItem() throws {
        let builder = MenuBarMenuBuilder()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [makeAccount(name: "Business 3", withRateLimits: true)]
            ),
            target: coordinator
        )

        statusItem.menu = menu
        coordinator.menuWillOpen(menu)

        #expect(statusItem.menu === menu)
    }

    @Test
    func openingMenuDoesNotReplaceInactiveAccountRowsDuringOpen() throws {
        let builder = MenuBarMenuBuilder()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        let inactive = makeAccount(name: "Business 3", withRateLimits: true)
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [inactive]
            ),
            target: coordinator
        )

        statusItem.menu = menu
        let visibleRowBeforeOpen = try #require(
            menu.items.first(where: { ($0.representedObject as? String) == inactive.id.uuidString })
        )

        coordinator.menuWillOpen(menu)

        let visibleRowAfterOpen = try #require(
            menu.items.first(where: { ($0.representedObject as? String) == inactive.id.uuidString })
        )
        let localAction = try #require(
            visibleRowAfterOpen.submenu?.items.first(where: { $0.title == "Switch on This Mac" })
        )

        #expect(visibleRowAfterOpen === visibleRowBeforeOpen)
        #expect(visibleRowAfterOpen.submenu === visibleRowBeforeOpen.submenu)
        #expect(visibleRowAfterOpen.action != #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(localAction.action == #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(localAction.target === coordinator)
    }

    @Test
    func menuNeedsUpdateDoesNotRepopulateMenuItemsDuringOpen() throws {
        let builder = MenuBarMenuBuilder()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", withRateLimits: true),
                inactiveAccounts: [makeAccount(name: "Business 3", withRateLimits: true)]
            ),
            target: coordinator
        )

        statusItem.menu = menu
        let itemsBeforeUpdate = menu.items

        coordinator.menuNeedsUpdate(menu)

        #expect(statusItem.menu === menu)
        #expect(menu.delegate === coordinator)
        #expect(menu.items.count == itemsBeforeUpdate.count)
        for (itemAfterUpdate, itemBeforeUpdate) in zip(menu.items, itemsBeforeUpdate) {
            #expect(itemAfterUpdate === itemBeforeUpdate)
        }
    }

    private func statusItemContentMenu(in menu: NSMenu) -> NSMenu? {
        menu.items
            .first(where: { $0.title == "Preferences" })?
            .submenu?
            .items
            .first(where: { $0.title == "Menu Bar Label" })?
            .submenu
    }

    private func notificationsSubmenu(in menu: NSMenu) throws -> NSMenu {
        let item = try #require(menu.items.first(where: { $0.title == "Notifications" }))
        return try #require(item.submenu)
    }

    private func launchAtLoginItem(in menu: NSMenu) throws -> NSMenuItem {
        let preferencesMenu = try #require(menu.items.first(where: { $0.title == "Preferences" })?.submenu)
        return try #require(preferencesMenu.items.first(where: { $0.title.hasPrefix("Launch at Login") }))
    }

    private func makeCoordinator() throws -> MenuBarCoordinator {
        try makeCoordinatorWithStatusItem().0
    }

    private func makeCoordinatorWithStatusItem(
        alertPresenter: AlertPresenterProbe? = nil,
        loginItemController: LoginItemControlling = LoginItemControllerProbe(),
        loginItemsSettingsLauncher: LoginItemsSettingsLaunching = LoginItemsSettingsLauncherProbe(),
        diagnosticReportPresenter: DiagnosticReportPresenting? = nil
    ) throws -> (MenuBarCoordinator, NSStatusItem) {
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarMenuBuilderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let statusItemRuntime = StatusItemRuntime(statusItem: statusItem)
        let coordinator = MenuBarCoordinator(
            statusItemRuntime: statusItemRuntime,
            store: store,
            settings: settings,
            alertPresenter: alertPresenter ?? AlertPresenterProbe(),
            panelPresenter: PanelPresenterProbe(),
            loginItemController: loginItemController,
            loginItemsSettingsLauncher: loginItemsSettingsLauncher,
            diagnosticReportPresenter: diagnosticReportPresenter ?? DiagnosticReportPresenterProbe()
        )
        return (coordinator, statusItem)
    }

    private func makeIsolatedRepository() throws -> AccountRepository {
        let appSupportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarMenuBuilderTests-\(UUID().uuidString)", isDirectory: true)
        return try AccountRepository(
            environment: [AppRuntimeEnvironment.validationAppSupportDirectoryEnvironmentKey: appSupportDirectory.path]
        )
    }

    private func makeState(
        activeAccount: CodexAccount?,
        inactiveAccounts: [CodexAccount] = [],
        remoteHosts: [RemoteHostMenuState] = [],
        progressAccentColor: NSColor = .controlAccentColor,
        hasCustomProgressAccentColor: Bool = false,
        notificationsWhenBlockedEnabled: Bool = false,
        notificationsWhenOutEnabled: Bool = false,
        notificationAuthorizationState: NotificationAuthorizationState = .unknown,
        loginItemState: LoginItemState = .disabled,
        showsPacingPrototypeMenu: Bool = false,
        revealStatusItemTitleShortcut: CodexPill.KeyboardShortcut? = .defaultRevealStatusItemTitle
    ) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: inactiveAccounts,
            remoteHosts: remoteHosts,
            visibleInactiveAccountCount: 2,
            visibleInactiveAccountCountOptions: [2, 3, 5, 0],
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .dualArcBadge,
            statusBarDisplayMode: .textOnHover,
            revealStatusItemTitleShortcut: revealStatusItemTitleShortcut,
            progressAccentColor: progressAccentColor,
            hasCustomProgressAccentColor: hasCustomProgressAccentColor,
            isBusy: false,
            statusMessage: "Ready",
            notificationsWhenBlockedEnabled: notificationsWhenBlockedEnabled,
            notificationsWhenOutEnabled: notificationsWhenOutEnabled,
            notificationAuthorizationState: notificationAuthorizationState,
            loginItemState: loginItemState,
            showsPacingPrototypeMenu: showsPacingPrototypeMenu
        )
    }

    private func makeAccount(name: String, withRateLimits: Bool) -> CodexAccount {
        let now = Date()
        return CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: now,
            updatedAt: now,
            email: "\(name.lowercased())@example.com",
            planType: "pro",
            rateLimits: withRateLimits ? CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "pro",
                primary: CodexRateLimitWindow(
                    usedPercent: 42,
                    resetsAt: now.addingTimeInterval(3_600),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 68,
                    resetsAt: now.addingTimeInterval(86_400),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now
            ) : nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com")
            )
        )
    }

    private func makeRemoteHost(
        name: String = "devbox",
        destination: String = "user@devbox",
        connectionState: RemoteHostConnectionState = .connected,
        desiredAccount: CodexAccount? = nil,
        activeAccount: CodexAccount? = nil,
        detectedAccount: CodexAccount? = nil,
        verificationStatus: PersistedRemoteHostState.VerificationStatus = .verified,
        lastVerificationError: String? = nil,
        deployedAccountIDs: [UUID] = []
    ) -> RemoteHostMenuState {
        RemoteHostMenuState(
            name: name,
            destination: destination,
            connectionState: connectionState,
            desiredAccount: desiredAccount,
            activeAccount: activeAccount,
            detectedAccount: detectedAccount,
            verificationStatus: verificationStatus,
            lastVerificationError: lastVerificationError,
            deployedAccountIDs: deployedAccountIDs
        )
    }
}

private struct NullCodexAppProcessClient: CodexAppProcessClient {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}
