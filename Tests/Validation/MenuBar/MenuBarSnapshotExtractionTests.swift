import AppKit
import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarSnapshotExtractionTests {
    @Test
    func currentAccountSummaryShowsDetailedLimitLines() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeState(for: "hosted-menu-default", now: now),
            now: now
        )

        let summary = try! #require(snapshot.sections.first(where: { $0.title == "Active Account" })?.items.first(where: { $0.contains("Primary • Pro x20") }))
        #expect(summary.contains("Primary • Pro x20"))
        #expect(!summary.contains("primary@example.com"))
        #expect(summary.contains("Session: 42% used"))
    }

    @Test
    func accountsStayCompact() throws {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeState(for: "hosted-menu-default", now: now),
            now: now
        )
        let accountsSection = try #require(snapshot.sections.first(where: { $0.title == "Other Accounts" }))
        let summary = try #require(accountsSection.items.first(where: { $0.contains(" • S ") && $0.contains("  W ") }))

        #expect(!summary.contains("research@example.com"))
        #expect(!summary.contains("sandbox@example.com"))
        #expect(!summary.contains("overflow@example.com"))
    }

    @Test
    func unmatchedActiveAccountDoesNotDisplaySavedAccountAsCurrent() throws {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeState(for: "menu-unmatched-active-account", now: now),
            now: now
        )

        let activeSection = try #require(snapshot.sections.first(where: { $0.title == "Active Account" }))
        let accountsSection = try #require(snapshot.sections.first(where: { $0.title == "Other Accounts" }))
        let overflowSection = try #require(snapshot.sections.first(where: { $0.title == "More Accounts…" }))
        let savedAccountItems = accountsSection.items + overflowSection.items

        #expect(activeSection.items == ["No active saved account"])
        #expect(savedAccountItems.contains(where: { $0.contains("Research") }))
        #expect(savedAccountItems.contains(where: { $0.contains("Sandbox") }))
        #expect(activeSection.items.allSatisfy { !$0.contains("Research") && !$0.contains("Sandbox") })
    }

    @Test
    func remoteAccountsSectionRendersWithoutChangingAccountsSource() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeState(for: "hosted-menu-with-host", now: now),
            now: now
        )

        let hostSummary = try! #require(snapshot.sections.first(where: { $0.title == "Active Accounts" })?.items.first(where: { $0.contains("Remote Active") }))
        let otherAccounts = try! #require(snapshot.sections.first(where: { $0.title == "Accounts" }))

        #expect(hostSummary.contains("buildbox"))
        #expect(hostSummary.contains("Remote Active"))
        #expect(otherAccounts.items.count == 3)
        #expect(otherAccounts.items.allSatisfy { !$0.contains("remote-active@example.com") })
    }

    @Test
    func multipleConnectedHostsRenderSeparateRemoteCardsWithoutChangingAccountsSource() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeState(for: "hosted-menu-multiple-hosts", now: now),
            now: now
        )

        let remoteSection = try! #require(snapshot.sections.first(where: { $0.title == "Active Accounts" }))
        let accountsSection = try! #require(snapshot.sections.first(where: { $0.title == "Accounts" }))

        #expect(remoteSection.items.count == 3)
        #expect(remoteSection.items.contains(where: { $0.contains("Primary") && $0.contains("This Mac") }))
        #expect(remoteSection.items.contains(where: { $0.contains("buildbox") && $0.contains("Buildbox Active") }))
        #expect(remoteSection.items.contains(where: { $0.contains("debian-vm") && $0.contains("Debian Active") }))
        #expect(accountsSection.items.count == 3)
        #expect(accountsSection.items.allSatisfy { !$0.contains("buildbox-active@example.com") })
        #expect(accountsSection.items.allSatisfy { !$0.contains("debian-active@example.com") })
    }

    @Test
    func hostScenarioCapturesTargetSpecificAccountActionsInMenuSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = makeState(for: "hosted-menu-with-host", now: now)
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(state: state, target: coordinator)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, menu: menu, now: now)

        let accountItem = try #require(menuItem(withChildTitled: "Switch on buildbox", in: snapshot.menuItems))
        let localAction = try #require(accountItem.children.first(where: { $0.title == "Switch on This Mac" }))
        let remoteAction = try #require(accountItem.children.first(where: { $0.title == "Switch on buildbox" }))
        let renameAction = try #require(accountItem.children.first(where: { $0.title == "Rename…" }))
        let removeAction = try #require(accountItem.children.first(where: { $0.title == "Remove…" }))

        #expect(accountItem.hasAction == false)
        #expect(localAction.actionSelector == "switchAccount:")
        #expect(remoteAction.actionSelector == "switchAccountOnHost:")
        #expect(renameAction.actionSelector == "renameAccount:")
        #expect(removeAction.actionSelector == "removeAccount:")
    }

    @Test
    func localAccountsRemainNativeMenuRowsWithSubmenusInMenuSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = makeState(for: "hosted-menu-default", now: now)
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(state: state, target: coordinator)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, menu: menu, now: now)

        let accountItem = try #require(snapshot.menuItems.first(where: { item in
            item.children.dropFirst().first?.title == "Not currently in use" &&
                item.children.contains(where: { $0.title == "Switch on This Mac" })
        }))
        let emailItem = try #require(accountItem.children.first)
        let statusItem = try #require(accountItem.children.dropFirst().first)
        let localAction = try #require(accountItem.children.first(where: { $0.title == "Switch on This Mac" }))
        let renameAction = try #require(accountItem.children.first(where: { $0.title == "Rename…" }))
        let removeAction = try #require(accountItem.children.first(where: { $0.title == "Remove…" }))

        #expect(accountItem.viewFrameWidth == nil)
        #expect(accountItem.hasAction == false)
        #expect(accountItem.actionSelector == nil)
        #expect(emailItem.title.hasSuffix("@example.com"))
        #expect(emailItem.isEnabled == false)
        #expect(statusItem.title == "Not currently in use")
        #expect(statusItem.isEnabled == false)
        #expect(localAction.actionSelector == "switchAccount:")
        #expect(renameAction.actionSelector == "renameAccount:")
        #expect(removeAction.actionSelector == "removeAccount:")
    }

    @Test
    func hostMissingScenarioUsesInstallAndSwitchCopyInMenuSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = makeState(for: "host-account-missing-on-host", now: now)
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(state: state, target: coordinator)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, menu: menu, now: now)

        let remoteAction = try #require(
            menuItem(withChildTitled: "Install on buildbox and switch", in: snapshot.menuItems)?
                .children
                .first(where: { $0.title == "Install on buildbox and switch" })
        )

        #expect(remoteAction.actionSelector == "switchAccountOnHost:")
    }

    @Test
    func remoteAccountsSectionStaysHiddenWhenHostHasNoActiveRemoteAccount() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeState(for: "host-account-missing-on-host", now: now),
            now: now
        )

        #expect(snapshot.sections.contains(where: { $0.title == "Remote Accounts" }) == false)
    }

    @Test
    func disconnectedHostsStayTargetableWithoutPrimaryRemoteCard() throws {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = makeState(for: "hosted-menu-disconnected-host", now: now)
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(state: state, target: coordinator)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, menu: menu, now: now)

        #expect(snapshot.sections.contains(where: { $0.title == "Remote Accounts" }) == false)
        #expect(snapshot.remoteHosts.isEmpty)

        let targetableAccountItem = try #require(menuItem(withChildTitled: "Install on buildbox and switch", in: snapshot.menuItems))
        let remoteAction = try #require(targetableAccountItem.children.first(where: { $0.title == "Install on buildbox and switch" }))
        let hostsMenu = try #require(snapshot.menuItems.first(where: { $0.title == "Hosts" }))
        let buildboxItem = try #require(hostsMenu.children.first(where: { $0.title == "buildbox" }))
        let hostStatus = try #require(buildboxItem.children.first(where: { $0.title == "Status: Disconnected" }))

        #expect(remoteAction.actionSelector == "switchAccountOnHost:")
        #expect(hostStatus.isEnabled == false)
    }

    @Test
    func accountsDoNotInventFullUsageWhenRateLimitsAreMissing() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = MenuBarMenuState(
            activeAccount: CodexAccount(
                id: UUID(),
                name: "Primary",
                snapshotFileName: "\(UUID().uuidString).json",
                createdAt: now,
                updatedAt: now,
                email: "primary@example.com",
                planType: "pro",
                rateLimits: nil,
                identity: .empty
            ),
            inactiveAccounts: [
                CodexAccount(
                    id: UUID(),
                    name: "Research",
                    snapshotFileName: "\(UUID().uuidString).json",
                    createdAt: now,
                    updatedAt: now,
                    email: "research@example.com",
                    planType: "pro",
                    rateLimits: nil,
                    identity: .empty
                )
            ],
            remoteHosts: [],
            visibleInactiveAccountCount: 2,
            visibleInactiveAccountCountOptions: [2, 3, 5, 0],
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .dualArcBadge,
            statusBarDisplayMode: .iconOnly,
            isBusy: false,
            statusMessage: "Ready"
        )

        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, now: now)
        let summary = try! #require(snapshot.sections.first(where: { $0.title == "Other Accounts" })?.items.first)

        #expect(summary.contains("S --"))
        #expect(summary.contains("W --"))
        #expect(!summary.contains("100%"))
    }

    @Test
    func emptyStateForcesIconOnlyStatusItemContentInValidationSnapshot() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeState(for: "menu-empty-catalog", now: now),
            now: now
        )

        let preferences = try! #require(snapshot.sections.first(where: { $0.title == "Preferences" }))
        #expect(preferences.items.contains("Menu Bar Label: Icon Only"))
        #expect(!preferences.items.contains("Menu Bar Label: Text on Hover"))
    }

    @Test
    func snapshotCapturesConfiguredProgressBarColors() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = MenuBarMenuState(
            activeAccount: makeState(for: "hosted-menu-default", now: now).activeAccount,
            inactiveAccounts: [],
            remoteHosts: [],
            visibleInactiveAccountCount: 2,
            visibleInactiveAccountCountOptions: [2, 3, 5, 0],
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .dualArcBadge,
            statusBarDisplayMode: .textOnHover,
            progressAccentColor: NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.78, alpha: 1),
            hasCustomProgressAccentColor: true,
            isBusy: false,
            statusMessage: "Ready"
        )

        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, now: now)
        let preferences = try! #require(snapshot.sections.first(where: { $0.title == "Preferences" }))

        #expect(preferences.items.contains("Accent Color: \(hexString(for: state.progressAccentColor))"))
    }

    @Test
    func snapshotCapturesStructuredCurrentAccountIdentity() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let account = CodexAccount(
            id: UUID(),
            name: "Business 4",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: now,
            updatedAt: now,
            email: "team@example.com",
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: "acct-team",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|business-4",
                    chatGPTUserID: "user-business-4"
                ),
                workspaceIdentity: CodexWorkspaceIdentity(
                    workspaceAccountID: "org-business-4",
                    workspaceLabel: "Personal"
                ),
                snapshotFingerprint: "business-four-fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "team@example.com")
            )
        )
        let state = MenuBarMenuState(
            activeAccount: account,
            inactiveAccounts: [],
            remoteHosts: [],
            visibleInactiveAccountCount: 2,
            visibleInactiveAccountCountOptions: [2, 3, 5, 0],
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .dualArcBadge,
            statusBarDisplayMode: .textOnHover,
            isBusy: false,
            statusMessage: "Ready"
        )

        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, now: now)

        #expect(snapshot.currentAccount?.name == "Business 4")
        #expect(snapshot.currentAccount?.email == "team@example.com")
        #expect(snapshot.currentAccount?.identityDigest?.isEmpty == false)
    }

    @Test
    func snapshotCapturesStatusItemRuntimeStateWhenProvided() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let runtimeState = StatusItemRuntimeSnapshot(
            isHovered: true,
            isPointerInsideButton: true,
            isTitleVisible: true,
            displayedTitle: "S 42% W 68%",
            imagePosition: "imageLeading",
            isHoverPollingActive: true,
            buttonFrame: .init(x: 10, y: 20, width: 54, height: 22),
            pointerLocation: .init(x: 32, y: 28)
        )

        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeState(for: "hosted-menu-default", now: now),
            statusItemState: runtimeState,
            now: now
        )

        #expect(snapshot.statusItem?.isHovered == true)
        #expect(snapshot.statusItem?.isTitleVisible == true)
        #expect(snapshot.statusItem?.displayedTitle == "S 42% W 68%")
        #expect(snapshot.statusItem?.imagePosition == "imageLeading")
        #expect(snapshot.statusItem?.isPointerInsideButton == true)
    }

    private func makeState(for scenario: String, now: Date) -> MenuBarMenuState {
        MenuBarValidationScenarioFixtures.makeState(for: scenario, now: now)
    }

    private func makeCoordinator() throws -> MenuBarCoordinator {
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarSnapshotExtractionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = CodexPillSettingsStore(userDefaults: defaults)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        return MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            store: store,
            settings: settings,
            alertPresenter: AlertPresenterProbe()
        )
    }

    private func makeIsolatedRepository() throws -> AccountRepository {
        let appSupportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarSnapshotExtractionTests-\(UUID().uuidString)", isDirectory: true)
        return try AccountRepository(
            environment: [AppRuntimeEnvironment.validationAppSupportDirectoryEnvironmentKey: appSupportDirectory.path]
        )
    }

    private func menuItem(
        withChildTitled title: String,
        in items: [MenuBarValidationSnapshot.MenuItem]
    ) -> MenuBarValidationSnapshot.MenuItem? {
        items.first(where: { item in
            item.children.contains(where: { $0.title == title })
                || menuItem(withChildTitled: title, in: item.children) != nil
        })
    }

    private func hexString(for color: NSColor) -> String {
        let normalized = (color.usingColorSpace(.deviceRGB) ?? color.usingColorSpace(.sRGB)) ?? color
        let red = Int(round(normalized.redComponent * 255))
        let green = Int(round(normalized.greenComponent * 255))
        let blue = Int(round(normalized.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private struct NullCodexAppProcessClient: CodexAppProcessClient {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}
