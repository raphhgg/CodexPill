import AppKit
import Foundation
import SwiftUI
import Testing

@testable import CodexPill

@MainActor
final class TestMenuBarAlertPresenter: MenuBarAlertPresenting {
    private(set) var textInputRequests: [MenuBarTextInputAlertRequest] = []
    private(set) var confirmationRequests: [MenuBarConfirmationAlertRequest] = []
    private(set) var infoRequests: [MenuBarInfoAlertRequest] = []
    private(set) var hostSetupRequests: [MenuBarHostSetupAlertRequest] = []

    var textInputResponse: String?
    var confirmationResponse = false
    var hostSetupResponse: RemoteHost?

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

    func presentHostSetup(
        _ request: MenuBarHostSetupAlertRequest,
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
}

@MainActor
struct MenuBarMenuBuilderTests {
    @Test
    func realAlertPresenterSuppressesInfoAlertsDuringAutomatedTests() {
        let presenter = MenuBarAlertPresenter(
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
    func realAlertPresenterCancelsInteractivePromptsDuringAutomatedTests() async {
        let presenter = MenuBarAlertPresenter(
            environment: [AppRuntimeEnvironment.xctestConfigurationFilePathEnvironmentKey: "/tmp/test.xctestconfiguration"]
        )

        let textValue = presenter.presentTextInput(
            MenuBarTextInputAlertRequest(
                messageText: "Rename",
                informativeText: "Rename account",
                fieldTitle: "Name",
                placeholder: "Business",
                confirmTitle: "Save",
                cancelTitle: "Cancel"
            )
        )
        let confirmation = presenter.presentConfirmation(
            MenuBarConfirmationAlertRequest(
                messageText: "Remove",
                informativeText: "Delete account",
                confirmTitle: "Remove",
                cancelTitle: "Cancel"
            )
        )
        var cancelled = false
        let hostValue = await presenter.presentHostSetup(
            MenuBarHostSetupAlertRequest(
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
    func liveValidationSnapshotCapturesStatusItemContentMetadata() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let state = makeState(activeAccount: makeAccount(name: "Active", withRateLimits: false))
        let menu = builder.makeMenu(state: state, target: coordinator)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, menu: menu)

        let display = try #require(snapshot.menuItems.first(where: { $0.title == "Display" }))
        let content = try #require(display.children.first(where: { $0.title == "Content" }))
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
    func saveCurrentAccountRemainsEnabledForActiveSavedAccount() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let addAccountMenu = try #require(
            menu.items
                .first(where: { $0.title == "Add Account…" })?
                .submenu
        )
        let saveCurrent = try #require(addAccountMenu.items.first(where: { $0.title == "Save Current Account" }))

        #expect(saveCurrent.isEnabled)
        #expect(saveCurrent.action == #selector(MenuBarCoordinator.addCurrentAccount))
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
        let statusItem = try #require(submenu.items.first)
        let localAction = try #require(submenu.items.first(where: { $0.title == "Switch on This Mac" }))
        let renameAction = try #require(submenu.items.first(where: { $0.title == "Rename…" }))
        let removeAction = try #require(submenu.items.first(where: { $0.title == "Remove…" }))
        let renameIndex = try #require(submenu.items.firstIndex(where: { $0.title == "Rename…" }))
        let removeIndex = try #require(submenu.items.firstIndex(where: { $0.title == "Remove…" }))

        #expect(visibleRow.view == nil)
        #expect(visibleRow.attributedTitle?.string.contains("S ") == true)
        #expect(visibleRow.attributedTitle?.string.contains("W ") == true)
        #expect(visibleRow.attributedTitle?.string.contains("Local") == false)
        #expect(visibleRow.representedObject as? String == business3.id.uuidString)
        #expect(visibleRow.action != #selector(MenuBarCoordinator.switchAccount(_:)))
        #expect(visibleRow.isEnabled == true)
        #expect(statusItem.title == "Not currently in use")
        #expect(statusItem.isEnabled == false)
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
        let overflowSwitch = try #require(firstOverflowAccount.submenu?.items.first(where: { $0.title == "Switch on This Mac" }))

        #expect(moreAccounts.image == nil)
        #expect(moreAccounts.submenu?.title == "More Accounts…")
        #expect(!firstOverflowAccount.title.isEmpty)
        #expect(
            ["Business 1", "Business 2", "Business 3", "Business 4"]
                .contains(where: { firstOverflowAccount.title.contains($0) })
        )
        #expect(firstOverflowAccount.submenu != nil)
        #expect(firstOverflowAccount.action != #selector(MenuBarCoordinator.switchAccount(_:)))
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
        let statusItem = try #require(submenu.items.first(where: { $0.title == "Not currently in use" }))
        let localAction = try #require(submenu.items.first(where: { $0.title == "Switch on This Mac" }))
        let remoteAction = try #require(submenu.items.first(where: { $0.title == "Switch on devbox" }))
        let renameAction = try #require(submenu.items.first(where: { $0.title == "Rename…" }))
        let removeAction = try #require(submenu.items.first(where: { $0.title == "Remove…" }))

        #expect(accountItem.submenu === submenu)
        #expect(accountItem.attributedTitle?.string.contains("S ") == true)
        #expect(accountItem.attributedTitle?.string.contains("W ") == true)
        #expect(accountItem.attributedTitle?.string.contains("Remote") == false)
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
        let pendingStatus = try #require(pendingItem.submenu?.items.first)
        let failedStatus = try #require(failedItem.submenu?.items.first)

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
    func activeAccountHostedViewFitsWithinConfiguredMenuWidth() {
        let view = NSHostingView(
            rootView: ActiveAccountMenuContent(
                account: makeAccount(name: "Business 2", withRateLimits: true),
                progressAccentColor: .blue
            )
        )

        view.frame = NSRect(x: 0, y: 0, width: 372, height: 1)
        view.layoutSubtreeIfNeeded()

        #expect(view.fittingSize.width <= 372)
    }

    @Test
    func remoteAccountHostedViewFitsWithinConfiguredMenuWidth() {
        let view = NSHostingView(
            rootView: RemoteHostMenuContent(
                remoteHost: makeRemoteHost(activeAccount: makeAccount(name: "Personal 1", withRateLimits: true)),
                progressAccentColor: .blue,
                primaryActionTitle: nil,
                onPrimaryAction: nil,
                isPrimaryActionEnabled: true,
                isPrimaryActionProminent: false
            )
        )

        view.frame = NSRect(x: 0, y: 0, width: 372, height: 1)
        view.layoutSubtreeIfNeeded()

        #expect(view.fittingSize.width <= 372)
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
                .compactMap { $0 as? NSHostingView<RemoteHostMenuContent> }
                .isEmpty
        )
    }

    @Test
    func remoteMismatchCardExposesAdoptDetectedAccountAction() throws {
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

        let remoteCard = try #require(
            menu.items
                .compactMap(\.view)
                .compactMap { $0 as? NSHostingView<RemoteHostMenuContent> }
                .first
        )

        #expect(remoteCard.rootView.remoteHost.detectedAccount?.name == "Business 1")
        #expect(remoteCard.rootView.primaryActionTitle == "Use Business 1")
        #expect(remoteCard.rootView.onPrimaryAction != nil)
        #expect(remoteCard.rootView.isPrimaryActionProminent == true)
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
    func remoteHostCardAndAccountUsageResolveAgainstCanonicalSavedAccountIdentity() throws {
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
                .compactMap { $0 as? NSHostingView<RemoteHostMenuContent> }
                .first
        )
        let accountItem = try #require(menu.items.first(where: { $0.attributedTitle?.string.contains(canonical.name) == true }))
        let usageStatusItem = try #require(accountItem.submenu?.items.first)

        #expect(remoteCard.rootView.remoteHost.activeAccount?.id == canonical.id)
        #expect(remoteCard.rootView.remoteHost.activeAccount?.rateLimits?.primary?.usedPercent == canonical.rateLimits?.primary?.usedPercent)
        #expect(usageStatusItem.title == "In use on: debian-vm")
    }

    @Test
    func remoteAccountsSectionRendersOneHostedCardPerConnectedHost() throws {
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

        let remoteCards = menu.items.compactMap(\.view).filter {
            String(describing: type(of: $0)).contains("RemoteHostMenuContent")
        }

        #expect(remoteCards.count == 2)
        #expect(menu.items.filter { $0.view != nil }.count == 6)
    }

    @Test
    func statusItemMenuIncludesColorCustomizationAndReset() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", withRateLimits: true)),
            target: coordinator
        )

        let displayMenu = try #require(menu.items.first(where: { $0.title == "Display" })?.submenu)
        let accent = try #require(displayMenu.items.first(where: { $0.title == "Accent Color…" }))
        let reset = try #require(displayMenu.items.first(where: { $0.title == "Use Default" }))

        #expect(accent.action == #selector(MenuBarCoordinator.chooseProgressAccentColor(_:)))
        #expect(accent.image != nil)
        #expect(reset.action == #selector(MenuBarCoordinator.resetProgressAccentColor(_:)))
        #expect(!reset.isEnabled)
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

        let displayMenu = try #require(menu.items.first(where: { $0.title == "Display" })?.submenu)
        let reset = try #require(displayMenu.items.first(where: { $0.title == "Use Default" }))

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
    func menuNeedsUpdateRepopulatesExistingMenuInstance() throws {
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

        coordinator.menuNeedsUpdate(menu)

        #expect(statusItem.menu === menu)
        #expect(menu.delegate === coordinator)
        #expect(!menu.items.isEmpty)
        #expect(menu.items.contains(where: { $0.title == "Add Account…" }))
    }

    private func statusItemContentMenu(in menu: NSMenu) -> NSMenu? {
        menu.items
            .first(where: { $0.title == "Display" })?
            .submenu?
            .items
            .first(where: { $0.title == "Content" })?
            .submenu
    }

    private func makeCoordinator() throws -> MenuBarCoordinator {
        try makeCoordinatorWithStatusItem().0
    }

    private func makeCoordinatorWithStatusItem() throws -> (MenuBarCoordinator, NSStatusItem) {
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            appController: CodexAppController(),
            appServerClient: CodexAppServerClient()
        )
        let suiteName = "MenuBarMenuBuilderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(userDefaults: defaults)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let statusItemRuntime = StatusItemRuntime(statusItem: statusItem)
        let coordinator = MenuBarCoordinator(
            statusItemRuntime: statusItemRuntime,
            store: store,
            settings: settings,
            alertPresenter: TestMenuBarAlertPresenter()
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
        hasCustomProgressAccentColor: Bool = false
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
            progressAccentColor: progressAccentColor,
            hasCustomProgressAccentColor: hasCustomProgressAccentColor,
            isBusy: false,
            statusMessage: "Ready"
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
