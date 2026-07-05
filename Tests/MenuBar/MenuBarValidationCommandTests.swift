import AppKit
import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarValidationCommandTests {
    @Test
    func hostedMenuScenarioProducesArtifacts() throws {
        let request = try loadValidationRequest() ?? ValidationRequest(
            artifactDirectory: "",
            scenario: "hosted-menu-default"
        )
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = makeHostedValidationState(for: request.scenario, now: now)
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(state: state, target: coordinator)
        let statusItemState = try makeScenarioStatusItemRuntimeState(
            for: request.scenario,
            state: state
        )
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: state,
            menu: menu,
            statusItemState: statusItemState,
            now: now
        )

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
        let extraArtifacts = try writeScenarioSpecificArtifacts(
            for: request.scenario,
            artifactDirectory: artifactDirectory,
            snapshot: snapshot,
            statusItemState: statusItemState,
            now: now
        )

        try MenuBarHostedDebugRendererTestSupport.renderPNG(
            MenuBarHostedDebugRenderer.makeView(state: state, now: now),
            to: screenshotURL
        )
        try writeJSON(snapshot, to: uiTreeURL)
        try writeJSON(
            ScenarioSummary(
                scenario: request.scenario,
                assertions: scenarioAssertions(for: request.scenario),
                screenshot: screenshotURL.lastPathComponent,
                uiTree: uiTreeURL.lastPathComponent,
                extraArtifacts: extraArtifacts.isEmpty ? nil : extraArtifacts
            ),
            to: summaryURL
        )
    }

    @Test
    func menuEmptyCatalogScenarioProducesUiStructureContractArtifact() throws {
        try assertUiStructureContractArtifact(
            for: UiStructureContractExpectation(
                scenario: "menu-empty-catalog",
                featureId: "account-catalog-empty-state",
                acceptanceCriteria: ["empty-catalog-guides-to-add-account"],
                rootChildIds: [
                    "active-account-section",
                    "manage-accounts-section",
                    "preferences-section"
                ],
                requiredAssertionIds: [
                    "active-account-section-visible",
                    "empty-active-account-row-visible",
                    "add-account-visible-and-enabled",
                    "add-account-action-available",
                    "top-level-menu-order"
                ]
            )
        )
    }

    @Test
    func promotedMenuScenariosProduceUiStructureContractArtifacts() throws {
        let expectations = [
            UiStructureContractExpectation(
                scenario: "hosted-menu-default",
                featureId: "menubar-default-read-state",
                acceptanceCriteria: ["default-menu-shape-does-not-claim-live-state"],
                rootChildIds: [
                    "active-account-section",
                    "other-accounts-section",
                    "more-accounts-section",
                    "manage-accounts-section",
                    "preferences-section"
                ],
                requiredAssertionIds: [
                    "active-account-section-visible",
                    "other-accounts-section-visible",
                    "more-accounts-section-visible",
                    "manage-accounts-section-visible",
                    "preferences-section-visible",
                    "top-level-menu-order"
                ]
            ),
            UiStructureContractExpectation(
                scenario: "menu-unmatched-active-account",
                featureId: "active-account-truth",
                acceptanceCriteria: ["active-account-unmatched-does-not-lie"],
                rootChildIds: [
                    "active-account-section",
                    "other-accounts-section",
                    "more-accounts-section",
                    "manage-accounts-section",
                    "preferences-section"
                ],
                requiredAssertionIds: [
                    "active-account-section-visible",
                    "empty-active-account-row-visible",
                    "other-accounts-section-visible",
                    "more-accounts-section-visible",
                    "top-level-menu-order"
                ]
            ),
            UiStructureContractExpectation(
                scenario: "menu-account-overflow",
                featureId: "account-catalog-overflow",
                acceptanceCriteria: ["overflow-keeps-hidden-accounts-discoverable"],
                rootChildIds: [
                    "active-account-section",
                    "other-accounts-section",
                    "more-accounts-section",
                    "manage-accounts-section",
                    "preferences-section"
                ],
                requiredAssertionIds: [
                    "other-accounts-section-visible",
                    "more-accounts-section-visible",
                    "saved-account-rows-present",
                    "top-level-menu-order"
                ]
            ),
            UiStructureContractExpectation(
                scenario: "menu-busy-status",
                featureId: "menubar-busy-status",
                acceptanceCriteria: ["busy-status-visible-and-conflicting-actions-disabled"],
                rootChildIds: [
                    "active-account-section",
                    "manage-accounts-section",
                    "preferences-section",
                    "status-message"
                ],
                requiredAssertionIds: [
                    "busy-status-message-visible",
                    "add-account-visible-and-disabled",
                    "add-account-action-disabled",
                    "top-level-menu-order"
                ]
            )
        ]

        for expectation in expectations {
            try assertUiStructureContractArtifact(for: expectation)
        }
    }

    private func assertUiStructureContractArtifact(
        for expectation: UiStructureContractExpectation
    ) throws {
        let artifactDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarValidationCommandTests-\(UUID().uuidString)", isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = makeHostedValidationState(for: expectation.scenario, now: now)
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(state: state, target: coordinator)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: state,
            menu: menu,
            now: now
        )

        let extraArtifacts = try writeScenarioSpecificArtifacts(
            for: expectation.scenario,
            artifactDirectory: artifactDirectory,
            snapshot: snapshot,
            statusItemState: nil,
            now: now
        )

        #expect(extraArtifacts == ["ui-structure-contract.json"])

        let contractURL = artifactDirectory.appendingPathComponent("ui-structure-contract.json")
        let data = try Data(contentsOf: contractURL)
        let contract = try JSONDecoder().decode(UiStructureContractArtifact.self, from: data)

        #expect(contract.kind == "ui_structure_contract")
        #expect(contract.schemaVersion == "kite.ui-structure-contract.v1")
        #expect(contract.scenario.id == expectation.scenario)
        #expect(contract.scenario.featureId == expectation.featureId)
        #expect(contract.scenario.acceptanceCriteria == expectation.acceptanceCriteria)
        #expect(contract.scenario.proofType == "ui-structure-contract")
        #expect(contract.root.children?.map(\.id) == expectation.rootChildIds)
        let assertionIds = Set(contract.assertions.map(\.id))
        #expect(expectation.requiredAssertionIds.allSatisfy { assertionIds.contains($0) })
        #expect(contract.nonClaims.contains("Does not prove pixel rendering, typography, spacing, or screenshot visual fidelity."))
        #expect(contract.nonClaims.contains("Does not prove native menu opening, native click routing, focus, or hittability."))
    }

    private struct UiStructureContractExpectation {
        let scenario: String
        let featureId: String
        let acceptanceCriteria: [String]
        let rootChildIds: [String]
        let requiredAssertionIds: [String]
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func writeScenarioSpecificArtifacts(
        for scenario: String,
        artifactDirectory: URL,
        snapshot: MenuBarValidationSnapshot,
        statusItemState: StatusItemRuntimeSnapshot?,
        now: Date
    ) throws -> [String] {
        switch scenario {
        case "hosted-menu-default", "menu-busy-status", "menu-empty-catalog", "menu-account-overflow", "menu-unmatched-active-account":
            let contractURL = artifactDirectory.appendingPathComponent("ui-structure-contract.json")
            try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
            try writeJSON(
                try MenuBarStructureContractExporter.makeContract(for: scenario, from: snapshot),
                to: contractURL
            )
            return [contractURL.lastPathComponent]
        case "launch-at-login-menu-states":
            let matrixURL = artifactDirectory.appendingPathComponent("launch-at-login-states.json")
            try writeJSON(try makeLaunchAtLoginStateMatrix(now: now), to: matrixURL)
            return [matrixURL.lastPathComponent]
        case "status-bar-icon-text-visible":
            let runtimeState = try #require(statusItemState)
            let stateURL = artifactDirectory.appendingPathComponent("status-item-state.json")
            try writeJSON(StatusItemStateArtifact(snapshot: runtimeState), to: stateURL)
            return [stateURL.lastPathComponent]
        default:
            return []
        }
    }

    private func makeScenarioStatusItemRuntimeState(
        for scenario: String,
        state: MenuBarMenuState
    ) throws -> StatusItemRuntimeSnapshot? {
        switch scenario {
        case "status-bar-icon-text-visible":
            return try makeStatusItemRuntimeState(for: state)
        default:
            return nil
        }
    }

    private func makeStatusItemRuntimeState(for state: MenuBarMenuState) throws -> StatusItemRuntimeSnapshot {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        let runtime = StatusItemRuntime(
            statusItem: statusItem,
            hoverActivationDelay: 0,
            hoverExitDelay: 0,
            hoverPollingInterval: 60
        )
        runtime.start(
            presentation: .init(
                activeAccount: makeStatusItemRuntimeAccount(from: state.activeAccount),
                indicatorStyle: state.statusBarIndicatorStyle,
                monochrome: state.statusBarMonochrome,
                displayMode: state.statusBarDisplayMode,
                progressAccentColor: state.progressAccentColor
            )
        )

        let snapshot = try #require(runtime.snapshotState())
        #expect(snapshot.isTitleVisible)
        #expect(snapshot.displayedTitle == "S 42% W 68%")
        #expect(snapshot.imagePosition == "imageLeading")
        #expect(snapshot.buttonFrame != nil)
        return snapshot
    }

    private func makeStatusItemRuntimeAccount(from account: CodexAccount?) -> CodexAccount? {
        guard var account, let rateLimits = account.rateLimits else {
            return account
        }

        let runtimeNow = Date()
        account.rateLimits = CodexRateLimitSnapshot(
            limitID: rateLimits.limitID,
            limitName: rateLimits.limitName,
            planType: rateLimits.planType,
            primary: rateLimits.sessionWindow.map {
                CodexRateLimitWindow(
                    usedPercent: $0.usedPercent,
                    resetsAt: runtimeNow.addingTimeInterval(3_600),
                    windowDurationMinutes: $0.windowDurationMinutes
                )
            },
            secondary: rateLimits.weeklyWindow.map {
                CodexRateLimitWindow(
                    usedPercent: $0.usedPercent,
                    resetsAt: runtimeNow.addingTimeInterval(86_400),
                    windowDurationMinutes: $0.windowDurationMinutes
                )
            },
            fetchedAt: runtimeNow
        )
        return account
    }

    private func makeLaunchAtLoginStateMatrix(now: Date) throws -> LaunchAtLoginStateMatrix {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let variants: [(id: String, state: LoginItemState)] = [
            ("enabled", .enabled),
            ("disabled", .disabled),
            ("requiresApproval", .requiresApproval),
            ("unavailable", .unavailable)
        ]

        let entries = try variants.map { variant in
            let state = makeLaunchAtLoginValidationState(
                loginItemState: variant.state,
                now: now
            )
            let menu = builder.makeMenu(state: state, target: coordinator)
            let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, menu: menu, now: now)
            let preferencesSection = try #require(snapshot.sections.first { $0.title == "Preferences" })
            let preferencesMenu = try #require(menu.items.first { $0.title == "Preferences" }?.submenu)
            let launchItem = try #require(preferencesMenu.items.first { $0.title.hasPrefix("Launch at Login") })
            let preferenceSummary = try #require(preferencesSection.items.first { $0.hasPrefix("Launch at Login:") })

            return LaunchAtLoginStateMatrix.Entry(
                state: variant.id,
                preferencesSummary: preferenceSummary,
                menuTitle: launchItem.title,
                menuState: launchItem.state == .on ? "on" : "off",
                isEnabled: launchItem.isEnabled,
                actionSelector: launchItem.action.map { NSStringFromSelector($0) }
            )
        }

        #expect(entries.map(\.state) == ["enabled", "disabled", "requiresApproval", "unavailable"])
        #expect(entries.map(\.preferencesSummary) == [
            "Launch at Login: On",
            "Launch at Login: Off",
            "Launch at Login: Needs Approval",
            "Launch at Login: Unavailable"
        ])
        #expect(entries.map(\.menuTitle) == [
            "Launch at Login",
            "Launch at Login",
            "Launch at Login…",
            "Launch at Login…"
        ])
        #expect(entries.map(\.menuState) == ["on", "off", "off", "off"])
        #expect(entries.allSatisfy { $0.isEnabled })
        #expect(entries.map(\.actionSelector) == [
            "toggleLaunchAtLogin:",
            "toggleLaunchAtLogin:",
            "openLoginItemsSettings:",
            "openLoginItemsSettings:"
        ])

        return LaunchAtLoginStateMatrix(scenario: "launch-at-login-menu-states", states: entries)
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

    private func flattenedMenuItems(
        in items: [MenuBarValidationSnapshot.MenuItem]
    ) -> [MenuBarValidationSnapshot.MenuItem] {
        items.flatMap { item in
            [item] + flattenedMenuItems(in: item.children)
        }
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

        case "menu-account-overflow":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Other Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            let accountsSection = try #require(snapshot.sections.first(where: { $0.title == "Other Accounts" }))
            let overflowSection = try #require(snapshot.sections.first(where: { $0.title == "More Accounts…" }))
            let allSavedAccountNames = ["Research", "Sandbox", "Overflow"]
            let renderedAccountItems = accountsSection.items + overflowSection.items
            #expect(accountsSection.items.count == 2)
            #expect(overflowSection.items.count == 1)
            #expect(allSavedAccountNames.allSatisfy { name in
                renderedAccountItems.contains(where: { $0.contains(name) })
            })
            #expect(accountsSection.items.allSatisfy { visibleItem in
                overflowSection.items.allSatisfy { overflowItem in
                    allSavedAccountNames.allSatisfy { name in
                        !(visibleItem.contains(name) && overflowItem.contains(name))
                    }
                }
            })

            let moreAccountsItem = try #require(snapshot.menuItems.first(where: { $0.title == "More Accounts…" }))
            #expect(moreAccountsItem.hasAction == false)
            let overflowItem = try #require(moreAccountsItem.children.first(where: { item in
                allSavedAccountNames.contains(where: { item.title.contains($0) })
            }))
            let overflowAccountName = try #require(allSavedAccountNames.first(where: { overflowItem.title.contains($0) }))
            #expect(overflowItem.hasAction == false)
            #expect(overflowSection.items.first?.contains(overflowAccountName) == true)
            #expect(overflowItem.children.contains(where: { $0.title.hasSuffix("@example.com") }))
            #expect(overflowItem.children.contains(where: { $0.title == "Not currently in use" }))
            #expect(overflowItem.children.first(where: { $0.title == "Switch on This Mac" })?.actionSelector == "switchAccount:")
            #expect(overflowItem.children.first(where: { $0.title == "Rename…" })?.actionSelector == "renameAccount:")
            #expect(overflowItem.children.first(where: { $0.title == "Remove…" })?.actionSelector == "removeAccount:")
            #expect(snapshot.statusMessage == nil)

        case "token-usage-ready-card":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Other Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            let activeSection = try #require(snapshot.sections.first(where: { $0.title == "Active Account" }))
            let tokenUsage = try #require(activeSection.items.first(where: { $0.contains("Token Usage") }))
            #expect(activeSection.items.count == 2)
            #expect(tokenUsage.contains("Last 30 days"))
            #expect(tokenUsage.contains("Today: 3,400 tokens"))
            #expect(tokenUsage.contains("Last 30 days: 4,600 tokens"))
            #expect(tokenUsage.contains("Peak day: May 20: 3,400 tokens"))
            #expect(!tokenUsage.contains("Primary"))
            #expect(!tokenUsage.contains("Research"))
            #expect(!tokenUsage.contains("@example.com"))
            #expect(!tokenUsage.localizedCaseInsensitiveContains("workspace"))
            #expect(!tokenUsage.localizedCaseInsensitiveContains("remote"))
            #expect(!tokenUsage.localizedCaseInsensitiveContains("host"))
            #expect(snapshot.remoteHosts.isEmpty)
            #expect(snapshot.statusMessage == nil)

        case "token-usage-off-hidden":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Other Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            let activeSection = try #require(snapshot.sections.first(where: { $0.title == "Active Account" }))
            #expect(activeSection.items.count == 1)
            #expect(activeSection.items.allSatisfy { !$0.contains("Token Usage") })
            #expect(activeSection.items.allSatisfy { !$0.contains("Last 30 days") })
            #expect(activeSection.items.allSatisfy { !$0.localizedCaseInsensitiveContains("scanning") })
            #expect(snapshot.remoteHosts.isEmpty)
            #expect(snapshot.statusMessage == nil)

        case "token-usage-loading-progress":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Other Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            let activeSection = try #require(snapshot.sections.first(where: { $0.title == "Active Account" }))
            let tokenUsage = try #require(activeSection.items.first(where: { $0.contains("Token Usage") }))
            #expect(activeSection.items.count == 2)
            #expect(tokenUsage.contains("Last 30 days"))
            #expect(tokenUsage.contains("Scanning 42 of 310 sessions..."))
            #expect(!tokenUsage.contains("%"))
            #expect(!tokenUsage.contains("Primary"))
            #expect(!tokenUsage.contains("Research"))
            #expect(!tokenUsage.contains("@example.com"))
            #expect(!tokenUsage.localizedCaseInsensitiveContains("workspace"))
            #expect(!tokenUsage.localizedCaseInsensitiveContains("remote"))
            #expect(!tokenUsage.localizedCaseInsensitiveContains("host"))
            #expect(!tokenUsage.localizedCaseInsensitiveContains("jsonl"))
            #expect(!tokenUsage.localizedCaseInsensitiveContains("path"))
            #expect(snapshot.remoteHosts.isEmpty)
            #expect(snapshot.statusMessage == nil)

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

        case "menu-busy-status", "hosted-menu-busy":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.statusMessage == "Refreshing account data...")
            #expect(snapshot.sections[1].items.contains("Add Account… (disabled)"))
            let menuItems = snapshot.menuItems
            let statusIndex = try #require(menuItems.firstIndex { $0.title == "Refreshing account data..." })
            let quitIndex = try #require(menuItems.firstIndex { $0.title == "Quit" })
            #expect(statusIndex < quitIndex)
            let addAccountItem = try #require(flattenedMenuItems(in: menuItems).first { $0.title == "Add Account…" })
            #expect(addAccountItem.isEnabled == false)

        case "launch-at-login-menu-states":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Other Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            let preferencesSection = try #require(snapshot.sections.first { $0.title == "Preferences" })
            #expect(preferencesSection.items.contains("Launch at Login: Needs Approval"))
            let preferencesMenu = try #require(snapshot.menuItems.first { $0.title == "Preferences" })
            let launchItem = try #require(preferencesMenu.children.first { $0.title == "Launch at Login…" })
            #expect(launchItem.state == "off")
            #expect(launchItem.isEnabled)
            #expect(launchItem.actionSelector == "openLoginItemsSettings:")
            #expect(snapshot.statusMessage == nil)

        case "status-bar-icon-text-visible":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Other Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            let preferencesSection = try #require(snapshot.sections.first { $0.title == "Preferences" })
            #expect(preferencesSection.items.contains("Menu Bar Label: Icon + Text"))
            let statusItem = try #require(snapshot.statusItem)
            #expect(statusItem.isTitleVisible)
            #expect(statusItem.displayedTitle == "S 42% W 68%")
            #expect(statusItem.imagePosition == "imageLeading")
            #expect(statusItem.buttonFrame != nil)
            #expect(snapshot.effectiveStatusBarDisplayMode == "iconAndText")
            #expect(snapshot.statusMessage == nil)

        case "menu-empty-catalog":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.sections[0].items == ["No active saved account"])
            #expect(snapshot.sections[1].items.contains("Add Account…"))
            #expect(snapshot.sections.contains(where: { $0.title == "Accounts" }) == false)
            #expect(snapshot.sections.contains(where: { $0.title == "Other Accounts" }) == false)
            #expect(snapshot.sections.contains(where: { $0.title == "More Accounts…" }) == false)
            #expect(snapshot.currentAccount == nil)
            #expect(menuItem(containing: "Add Account", in: snapshot.menuItems)?.actionSelector == "addAccount")
            #expect(flattenedMenuItems(in: snapshot.menuItems).contains(where: { item in
                item.actionSelector == "switchAccount:" ||
                    item.actionSelector == "switchAccountOnHost:"
            }) == false)
            #expect(snapshot.statusMessage == nil)

        case "menu-unmatched-active-account":
            #expect(snapshot.sections.map(\.title) == [
                "Active Account",
                "Other Accounts",
                "More Accounts…",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.sections[0].items == ["No active saved account"])
            #expect(snapshot.sections[1].items.count == 2)
            #expect(snapshot.sections[2].items.count == 1)
            #expect(snapshot.sections[1].items.allSatisfy { !$0.contains("This Mac") })
            #expect(snapshot.statusMessage == nil)

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
        case "menu-account-overflow":
            return [
                "Visible account rows stop at the configured account limit",
                "Hidden saved accounts remain discoverable under More Accounts…",
                "Overflow rows preserve the same submenu actions as visible account rows"
            ]
        case "token-usage-ready-card":
            return [
                "Token Usage ready card renders in the active account area",
                "Synthetic aggregate data renders today, period total, and peak day",
                "Token Usage card does not emit account, email, workspace, remote, or host attribution"
            ]
        case "token-usage-off-hidden":
            return [
                "Token Usage disabled state omits the active-area card",
                "Disabled state omits Token Usage period and loading copy from the active account area",
                "Disabled state emits no Token Usage workspace, remote, host, path, or raw session detail"
            ]
        case "token-usage-loading-progress":
            return [
                "Token Usage loading card renders in the active account area",
                "Synthetic file-count progress renders without fake percentages",
                "Loading card does not emit account, email, workspace, remote, host, path, or raw session detail"
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
        case "menu-busy-status", "hosted-menu-busy":
            return [
                "Busy state exposes only the current account plus shared account and preference controls",
                "Busy status message is rendered before Quit in the artifact snapshot",
                "Add-account action is marked disabled in the snapshot"
            ]
        case "launch-at-login-menu-states":
            return [
                "Requires-approval state renders Launch at Login with System Settings routing",
                "Structured state matrix covers enabled, disabled, requires-approval, and unavailable states",
                "State matrix preserves checked state and action selectors without real macOS login-item mutation"
            ]
        case "status-bar-icon-text-visible":
            return [
                "Status item runtime snapshot renders the visible icon-and-text state",
                "Synthetic active account produces S 42% W 68% as the displayed title",
                "Runtime state is captured without live menubar screen capture, hover, or shortcut proof"
            ]
        case "menu-empty-catalog":
            return [
                "Empty state shows no active saved account",
                "Add Account… remains available when the menu is idle and empty",
                "Saved-account rows and switch actions are omitted when there are no saved accounts"
            ]
        case "menu-unmatched-active-account":
            return [
                "Unmatched local auth state does not render a saved account as active",
                "Saved accounts remain available as account catalog rows",
                "Overflow behavior remains intact while the active account state is empty"
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
        MenuBarValidationScenarioFixtures.makeState(for: scenario, now: now)
    }

    private func makeLaunchAtLoginValidationState(
        loginItemState: LoginItemState,
        now: Date
    ) -> MenuBarMenuState {
        MenuBarValidationScenarioFixtures.makeLaunchAtLoginState(
            loginItemState: loginItemState,
            now: now
        )
    }

    private func makeCoordinator() throws -> MenuBarCoordinator {
        let repository = try makeIsolatedRepository()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: NullCodexAppProcessClient(),
            accountStatusClient: DisabledAccountStatusClient()
        )
        let suiteName = "MenuBarValidationCommandTests-\(UUID().uuidString)"
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
            .appendingPathComponent("MenuBarValidationCommandTests-\(UUID().uuidString)", isDirectory: true)
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
    let extraArtifacts: [String]?
}

private struct LaunchAtLoginStateMatrix: Codable {
    struct Entry: Codable {
        let state: String
        let preferencesSummary: String
        let menuTitle: String
        let menuState: String
        let isEnabled: Bool
        let actionSelector: String?
    }

    let scenario: String
    let states: [Entry]
}

private struct StatusItemStateArtifact: Codable {
    struct Rect: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Point: Codable {
        let x: Double
        let y: Double
    }

    let isHovered: Bool
    let isPointerInsideButton: Bool
    let isTitleVisible: Bool
    let displayedTitle: String?
    let imagePosition: String
    let isHoverPollingActive: Bool
    let buttonFrame: Rect?
    let pointerLocation: Point?

    init(snapshot: StatusItemRuntimeSnapshot) {
        isHovered = snapshot.isHovered
        isPointerInsideButton = snapshot.isPointerInsideButton
        isTitleVisible = snapshot.isTitleVisible
        displayedTitle = snapshot.displayedTitle
        imagePosition = snapshot.imagePosition
        isHoverPollingActive = snapshot.isHoverPollingActive
        buttonFrame = snapshot.buttonFrame.map {
            Rect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        }
        pointerLocation = snapshot.pointerLocation.map {
            Point(x: $0.x, y: $0.y)
        }
    }
}

private struct ValidationRequest: Codable {
    let artifactDirectory: String
    let scenario: String
}

private enum ValidationError: Error {
    case unknownScenario(String)
}

private struct NullCodexAppProcessClient: CodexAppProcessClient {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}
