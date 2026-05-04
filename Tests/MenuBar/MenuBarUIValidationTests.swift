import AppKit
import Foundation
import SwiftUI
import Testing

@testable import CodexPill

@MainActor
struct MenuBarUIValidationTests {
    @Test
    func currentAccountSummaryShowsDetailedLimitLines() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeHostedValidationState(for: "hosted-menu-default", now: now),
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
            state: makeHostedValidationState(for: "hosted-menu-default", now: now),
            now: now
        )
        let accountsSection = try #require(snapshot.sections.first(where: { $0.title == "Other Accounts" }))
        let summary = try #require(accountsSection.items.first(where: { $0.contains(" • S ") && $0.contains("  W ") }))

        #expect(!summary.contains("research@example.com"))
        #expect(!summary.contains("sandbox@example.com"))
        #expect(!summary.contains("overflow@example.com"))
    }

    @Test
    func remoteAccountsSectionRendersWithoutChangingAccountsSource() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeHostedValidationState(for: "hosted-menu-with-host", now: now),
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
            state: makeHostedValidationState(for: "hosted-menu-multiple-hosts", now: now),
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
        let state = makeHostedValidationState(for: "hosted-menu-with-host", now: now)
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
        let state = makeHostedValidationState(for: "hosted-menu-default", now: now)
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
        let state = makeHostedValidationState(for: "host-account-missing-on-host", now: now)
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
            state: makeHostedValidationState(for: "host-account-missing-on-host", now: now),
            now: now
        )

        #expect(snapshot.sections.contains(where: { $0.title == "Remote Accounts" }) == false)
    }

    @Test
    func disconnectedHostsStayTargetableWithoutPrimaryRemoteCard() throws {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = makeHostedValidationState(for: "hosted-menu-disconnected-host", now: now)
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
            state: makeHostedValidationState(for: "hosted-menu-empty", now: now),
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
            activeAccount: makeHostedValidationState(for: "hosted-menu-default", now: now).activeAccount,
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
            email: "raphaelgrau@icloud.com",
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
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@icloud.com")
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
        #expect(snapshot.currentAccount?.email == "raphaelgrau@icloud.com")
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
            buttonFrame: .init(x: 10, y: 20, width: 54, height: 22),
            pointerLocation: .init(x: 32, y: 28)
        )

        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeHostedValidationState(for: "hosted-menu-default", now: now),
            statusItemState: runtimeState,
            now: now
        )

        #expect(snapshot.statusItem?.isHovered == true)
        #expect(snapshot.statusItem?.isTitleVisible == true)
        #expect(snapshot.statusItem?.displayedTitle == "S 42% W 68%")
        #expect(snapshot.statusItem?.imagePosition == "imageLeading")
        #expect(snapshot.statusItem?.isPointerInsideButton == true)
    }

    @Test
    func hostedMenuScenarioProducesArtifacts() throws {
        let request = try loadValidationRequest() ?? ValidationRequest(
            artifactDirectory: "",
            scenario: "hosted-menu-default"
        )
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = makeHostedValidationState(for: request.scenario, now: now)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, now: now)

        try assertScenarioSnapshot(snapshot, scenario: request.scenario)

        guard !request.artifactDirectory.isEmpty else {
            return
        }

        let artifactDirectory = URL(fileURLWithPath: request.artifactDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

        let screenshotURL = artifactDirectory
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent("\(request.scenario).png")
        try FileManager.default.createDirectory(at: screenshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let uiTreeURL = artifactDirectory.appendingPathComponent("ui-tree.json")
        let summaryURL = artifactDirectory.appendingPathComponent("scenario-summary.json")

        try renderHostedValidationView(
            MenuBarValidationSupport.makeHostedValidationView(state: state, now: now),
            to: screenshotURL
        )
        try writeJSON(snapshot, to: uiTreeURL)
        try writeJSON(
            ScenarioSummary(
                scenario: request.scenario,
                assertions: scenarioAssertions(for: request.scenario),
                screenshot: screenshotURL.lastPathComponent,
                uiTree: uiTreeURL.lastPathComponent
            ),
            to: summaryURL
        )
    }

    private func renderHostedValidationView<V: View>(_ view: V, to url: URL) throws {
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize
        let frame = NSRect(origin: .zero, size: NSSize(width: max(360, size.width), height: max(1, size.height)))
        hostingView.frame = frame
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: frame) else {
            throw ValidationError.failedToCreateBitmap
        }

        hostingView.cacheDisplay(in: frame, to: representation)

        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw ValidationError.failedToEncodePNG
        }

        try pngData.write(to: url, options: .atomic)
    }

    private func hexString(for color: NSColor) -> String {
        let normalized = (color.usingColorSpace(.deviceRGB) ?? color.usingColorSpace(.sRGB)) ?? color
        let red = Int(round(normalized.redComponent * 255))
        let green = Int(round(normalized.greenComponent * 255))
        let blue = Int(round(normalized.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func menuItem(
        containing titleFragment: String,
        in items: [MenuBarValidationSnapshot.MenuItem]
    ) -> MenuBarValidationSnapshot.MenuItem? {
        for item in items {
            if item.title.contains(titleFragment) {
                return item
            }
            if let child = menuItem(containing: titleFragment, in: item.children) {
                return child
            }
        }
        return nil
    }

    private func menuItem(
        withChildTitled childTitle: String,
        in items: [MenuBarValidationSnapshot.MenuItem]
    ) -> MenuBarValidationSnapshot.MenuItem? {
        for item in items {
            if item.children.contains(where: { $0.title == childTitle }) {
                return item
            }
            if let child = menuItem(withChildTitled: childTitle, in: item.children) {
                return child
            }
        }
        return nil
    }

    private func assertScenarioSnapshot(_ snapshot: MenuBarValidationSnapshot, scenario: String) throws {
        switch scenario {
        case "hosted-menu-default":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.statusMessage == nil)
            #expect(snapshot.sections[1].items.count == 3)
            #expect(snapshot.sections[2].items.count == 1)
            #expect(snapshot.sections[3].items.contains("Add Account…"))

        case "hosted-menu-with-host":
            #expect(snapshot.sections.map(\.title) == [
                "Active Accounts",
                "Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.sections[0].items.contains(where: { $0.contains("buildbox") && $0.contains("Remote Active") }))
            #expect(snapshot.sections[1].items.count == 3)
            #expect(snapshot.sections[2].items.count == 1)

        case "hosted-menu-local-and-remote-same-account":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Accounts",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.sections[0].items.first?.contains("This Mac + debian-vm") == true)
            #expect(snapshot.sections.contains(where: { $0.title == "Remote Accounts" }) == false)
            #expect(snapshot.remoteHosts.map(\.name) == ["debian-vm"])

        case "hosted-menu-multiple-hosts":
            #expect(snapshot.sections.map(\.title) == [
                "Active Accounts",
                "Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.sections[0].items.count == 3)
            #expect(snapshot.sections[1].items.count == 3)
            #expect(snapshot.sections[2].items.count == 2)

        case "host-account-missing-on-host":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.sections[1].items.count == 3)

        case "hosted-menu-disconnected-host":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.sections.contains(where: { $0.title == "Remote Accounts" }) == false)
            #expect(snapshot.remoteHosts.isEmpty)

        case "hosted-pacing-prototypes":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences",
                "Pacing Prototypes"
            ])
            let section = try #require(snapshot.sections.last)
            #expect(section.items.count == 6)
            #expect(section.items.allSatisfy { $0.contains("Session") && $0.contains("Weekly") })

        case "hosted-menu-busy":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.statusMessage == "Refreshing account data...")
            #expect(snapshot.sections[1].items.contains("Add Account… (disabled)"))

        case "hosted-menu-empty":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.sections[0].items == ["No active saved account"])
            #expect(snapshot.sections[1].items.contains("Add Account…"))
            #expect(snapshot.statusMessage == nil)

        case "live-menu-open",
             "live-account-switch",
             "live-add-host-destination-validation-failed",
             "live-add-host-prompt",
             "live-add-account-name-dialog-cancelled",
             "live-scheduled-refresh",
             "live-status-item-hover":
            #expect(!snapshot.sections.isEmpty)

        default:
            throw ValidationError.unknownScenario(scenario)
        }
    }

    private func scenarioAssertions(for scenario: String) -> [String] {
        switch scenario {
        case "hosted-menu-default":
            return [
                "Active Account section includes the active account summary",
                "Two inactive accounts are visible and one account overflows into More Accounts…",
                "Status message is omitted when the menu is not busy"
            ]
        case "hosted-menu-with-host":
            return [
                "Remote host active account renders as an active account card",
                "Accounts continues to reflect the local saved-account catalog",
                "One inactive account still overflows into More Accounts… with a connected host present"
            ]
        case "hosted-menu-local-and-remote-same-account":
            return [
                "Same saved account active locally and on a verified host collapses to one Active Account card",
                "Active Account communicates the remote host location",
                "Connected host metadata remains in the snapshot for Hosts management"
            ]
        case "hosted-menu-multiple-hosts":
            return [
                "Each connected host with a different account renders its own active-account card",
                "Accounts still reflects only the local saved-account catalog",
                "Overflow account behavior stays intact with multiple connected hosts"
            ]
        case "host-account-missing-on-host":
            return [
                "Missing remote snapshots change the action copy to install-and-switch",
                "Accounts still comes from the local catalog only"
            ]
        case "hosted-menu-disconnected-host":
            return [
                "Disconnected hosts stay out of the primary Active Account section",
                "Configured hosts remain available under Hosts and per-account switch targets"
            ]
        case "hosted-pacing-prototypes":
            return [
                "Debug pacing prototype menu is visible only in the prototype scenario",
                "Baseline plus five materially different variants render with the current account card layout",
                "Prototype variants compare text placement and progress bar treatments without changing production cards"
            ]
        case "hosted-menu-busy":
            return [
                "Busy state exposes only the current account plus shared account and preference controls",
                "Busy status message is rendered into the artifact snapshot",
                "Add-account action is marked disabled in the snapshot"
            ]
        case "hosted-menu-empty":
            return [
                "Empty state shows no active saved account",
                "Add Account… remains available when the menu is idle and empty",
                "Per-account management actions are omitted when there are no saved accounts"
            ]
        default:
            return []
        }
    }

    private func loadValidationRequest() throws -> ValidationRequest? {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let requestURL = repoRoot
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("verification", isDirectory: true)
            .appendingPathComponent("request.json")

        guard FileManager.default.fileExists(atPath: requestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: requestURL)
        let request = try JSONDecoder().decode(ValidationRequest.self, from: data)
        return request
    }

    private func makeHostedValidationState(for scenario: String, now: Date) -> MenuBarMenuState {
        switch scenario {
        case "hosted-menu-default":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let others = [
                makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now),
                makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now),
                makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)
            ]

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: others,
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

        case "hosted-menu-with-host":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let others = [
                makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now),
                makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now),
                makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)
            ]
            let remoteActive = makeAccount(
                name: "Remote Active",
                email: "remote-active@example.com",
                planType: "team",
                sessionUsedPercent: 11,
                weeklyUsedPercent: 27,
                now: now
            )

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: others,
                remoteHosts: [RemoteHostMenuState(
                    name: "buildbox",
                    connectionState: .connected,
                    activeAccount: remoteActive,
                    deployedAccountIDs: others.map(\.id)
                )],
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

        case "hosted-menu-local-and-remote-same-account":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )
            let research = makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now)
            var remoteActive = active
            remoteActive.updatedAt = active.updatedAt.addingTimeInterval(60)

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: [research],
                remoteHosts: [RemoteHostMenuState(
                    name: "debian-vm",
                    destination: "user@debian-vm",
                    connectionState: .connected,
                    desiredAccount: active,
                    activeAccount: remoteActive,
                    verificationStatus: .verified,
                    deployedAccountIDs: [active.id, research.id]
                )],
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

        case "hosted-menu-multiple-hosts":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let others = [
                makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now),
                makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now),
                makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now),
                makeAccount(name: "Archive", email: "archive@example.com", planType: "team", sessionUsedPercent: 4, weeklyUsedPercent: 11, now: now)
            ]
            let buildboxActive = makeAccount(
                name: "Buildbox Active",
                email: "buildbox-active@example.com",
                planType: "team",
                sessionUsedPercent: 11,
                weeklyUsedPercent: 27,
                now: now
            )
            let debianActive = makeAccount(
                name: "Debian Active",
                email: "debian-active@example.com",
                planType: "plus",
                sessionUsedPercent: 33,
                weeklyUsedPercent: 45,
                now: now
            )

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: others,
                remoteHosts: [
                    RemoteHostMenuState(
                        name: "buildbox",
                        destination: "user@buildbox",
                        connectionState: .connected,
                        activeAccount: buildboxActive,
                        deployedAccountIDs: others.map(\.id)
                    ),
                    RemoteHostMenuState(
                        name: "debian-vm",
                        destination: "user@debian-vm",
                        connectionState: .connected,
                        activeAccount: debianActive,
                        deployedAccountIDs: [others[0].id, others[2].id]
                    )
                ],
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

        case "host-account-missing-on-host":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let research = makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now)
            let sandbox = makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now)
            let overflow = makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: [research, sandbox, overflow],
                remoteHosts: [RemoteHostMenuState(
                    name: "buildbox",
                    connectionState: .connected,
                    activeAccount: nil,
                    deployedAccountIDs: [sandbox.id]
                )],
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

        case "hosted-menu-disconnected-host":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let research = makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now)
            let sandbox = makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now)
            let overflow = makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: [research, sandbox, overflow],
                remoteHosts: [RemoteHostMenuState(
                    name: "buildbox",
                    destination: "user@buildbox",
                    connectionState: .disconnected,
                    activeAccount: makeAccount(
                        name: "Stale Remote",
                        email: "stale-remote@example.com",
                        planType: "team",
                        sessionUsedPercent: 52,
                        weeklyUsedPercent: 61,
                        now: now
                    ),
                    deployedAccountIDs: [research.id]
                )],
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

        case "hosted-pacing-prototypes":
            var state = makeHostedValidationState(for: "hosted-menu-default", now: now)
            state = MenuBarMenuState(
                activeAccount: state.activeAccount,
                inactiveAccounts: state.inactiveAccounts,
                remoteHosts: state.remoteHosts,
                visibleInactiveAccountCount: state.visibleInactiveAccountCount,
                visibleInactiveAccountCountOptions: state.visibleInactiveAccountCountOptions,
                refreshIntervalMinutes: state.refreshIntervalMinutes,
                refreshIntervalOptions: state.refreshIntervalOptions,
                statusBarMonochrome: state.statusBarMonochrome,
                statusBarIndicatorStyle: state.statusBarIndicatorStyle,
                statusBarDisplayMode: state.statusBarDisplayMode,
                progressAccentColor: state.progressAccentColor,
                hasCustomProgressAccentColor: state.hasCustomProgressAccentColor,
                isBusy: state.isBusy,
                statusMessage: state.statusMessage,
                notificationsWhenBlockedEnabled: state.notificationsWhenBlockedEnabled,
                notificationsWhenOutEnabled: state.notificationsWhenOutEnabled,
                notificationAuthorizationState: state.notificationAuthorizationState,
                showsPacingPrototypeMenu: true
            )
            return state

        case "hosted-menu-busy":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 57,
                weeklyUsedPercent: 73,
                now: now
            )

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: [],
                remoteHosts: [],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: true,
                statusBarIndicatorStyle: .twinPills,
                statusBarDisplayMode: .textOnHover,
                isBusy: true,
                statusMessage: "Refreshing account data..."
            )

        case "hosted-menu-empty":
            return MenuBarMenuState(
                activeAccount: nil,
                inactiveAccounts: [],
                remoteHosts: [],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 10,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .stackedBars,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready"
            )

        default:
            return makeHostedValidationState(for: "hosted-menu-default", now: now)
        }
    }

    private func makeCoordinator() throws -> MenuBarCoordinator {
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarUIValidationTests-\(UUID().uuidString)"
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
            .appendingPathComponent("MenuBarUIValidationTests-\(UUID().uuidString)", isDirectory: true)
        return try AccountRepository(
            environment: [AppRuntimeEnvironment.validationAppSupportDirectoryEnvironmentKey: appSupportDirectory.path]
        )
    }

    private func makeAccount(
        name: String,
        email: String,
        planType: String,
        sessionUsedPercent: Int,
        weeklyUsedPercent: Int,
        now: Date
    ) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: now.addingTimeInterval(-3_600),
            updatedAt: now.addingTimeInterval(-600),
            email: email,
            planType: planType,
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: planType,
                primary: CodexRateLimitWindow(
                    usedPercent: sessionUsedPercent,
                    resetsAt: now.addingTimeInterval(3_600),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: weeklyUsedPercent,
                    resetsAt: now.addingTimeInterval(86_400),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now.addingTimeInterval(-300)
            ),
            identity: CodexAccountIdentity(
                stableAccountID: nil,
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}

private struct ScenarioSummary: Codable {
    let scenario: String
    let assertions: [String]
    let screenshot: String
    let uiTree: String
}

private struct ValidationRequest: Codable {
    let artifactDirectory: String
    let scenario: String
}

private enum ValidationError: Error {
    case failedToCreateBitmap
    case failedToEncodePNG
    case unknownScenario(String)
}

private struct NullCodexAppProcessClient: CodexAppProcessClient {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}
