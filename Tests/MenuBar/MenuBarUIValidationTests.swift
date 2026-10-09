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
                "Other Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.statusMessage == nil)
            #expect(snapshot.sections[1].items.count == 2)
            #expect(snapshot.sections[2].items.count == 1)
            #expect(snapshot.sections[3].items.contains("Add Account…"))

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
                rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 42, weeklyUsedPercent: 68)
            )

            let others = [
                makeAccount(
                    name: "Research",
                    email: "research@example.com",
                    planType: "pro",
                    rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 8, weeklyUsedPercent: 35)
                ),
                makeAccount(
                    name: "Sandbox",
                    email: "sandbox@example.com",
                    planType: "plus",
                    rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 19, weeklyUsedPercent: 50)
                ),
                makeAccount(
                    name: "Overflow",
                    email: "overflow@example.com",
                    planType: "plus",
                    rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 74, weeklyUsedPercent: 88)
                )
            ]

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: others,
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

        case "hosted-menu-busy":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                rateLimits: makeRateLimits(resettingAfter: now, sessionUsedPercent: 57, weeklyUsedPercent: 73)
            )

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: [],
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
        let accountsController = AccountsFeatureFactory(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: CodexAppProcessProbe(),
            accountStatusClient: DisabledAccountStatusClient()
        ).makeController()
        let suiteName = "MenuBarUIValidationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStores(userDefaults: defaults)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        return MenuBarCoordinator.makeForTesting(
            statusItemRuntime: StatusItemRuntime(statusItem: statusItem),
            accountsController: accountsController,
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
