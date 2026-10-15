import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Refill

@MainActor
final class AlertPresenterProbe: AlertPresenter {
    private(set) var confirmationRequests: [MenuBarConfirmationAlertRequest] = []
    private(set) var infoRequests: [MenuBarInfoAlertRequest] = []

    var confirmationResponse = false

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
    private(set) var addAccountSignInRequests: [MenuBarAddAccountSignInPanelRequest] = []

    var addAccountSignInResult: MenuBarAddAccountSignInPanelResult = .cancelled

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
    var stateCallCount = 0
    var setEnabledCalls: [Bool] = []
    var errorToThrow: Error?

    init(currentState: LoginItemState = .disabled) {
        self.currentState = currentState
    }

    func state() -> LoginItemState {
        stateCallCount += 1
        return currentState
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        setEnabledCalls.append(isEnabled)
        currentState = isEnabled ? .enabled : .disabled
    }
}

actor TokenUsageMenuProviderProbe: TokenUsageMenuProviding {
    private(set) var loadPeriods: [CodexTokenUsagePeriod] = []
    private var progressHandler: (@Sendable (TokenUsageScanProgress) -> Void)?
    private var loadContinuation: CheckedContinuation<TokenUsageMenuLoadState, Never>?

    func load(
        period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        forceRefresh: Bool,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState {
        loadPeriods.append(period)
        progressHandler = progress
        progress(TokenUsageScanProgress(scannedFiles: 0, totalFiles: 2))
        progress(TokenUsageScanProgress(scannedFiles: 1, totalFiles: 2))
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func emitProgress(_ progress: TokenUsageScanProgress) {
        progressHandler?(progress)
    }

    func finish(with buckets: [CodexDailyTokenUsage]) {
        loadContinuation?.resume(returning: .loaded(TokenUsageMenuLoadedData(buckets: buckets, allTimePeak: nil)))
        loadContinuation = nil
        progressHandler = nil
    }

    var loadCount: Int {
        loadPeriods.count
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
        return URL(fileURLWithPath: "/tmp/Refill-Diagnostics.json")
    }
}

@MainActor
struct MenuBarMenuBuilderTests {
    @Test
    func realPresentersCancelInteractivePromptsWhenSuppressed() async {
        let alertPresenter = SystemAlertPresenter(suppressesInteractivePrompts: true)
        let panelPresenter = SystemPanelPresenter(suppressesInteractivePrompts: true)

        let confirmation = alertPresenter.presentConfirmation(
            MenuBarConfirmationAlertRequest(
                messageText: "Remove",
                informativeText: "Delete account",
                confirmTitle: "Remove",
                cancelTitle: "Cancel"
            )
        )
        alertPresenter.presentInfo(
            MenuBarInfoAlertRequest(
                messageText: "Refill Error",
                informativeText: "Permission denied",
                style: .warning,
                buttonTitle: "OK"
            )
        )
        var signInCancelled = false
        let signInResult = await panelPresenter.presentAddAccountSignIn(
            MenuBarAddAccountSignInPanelRequest(
                messageText: "Sign in",
                informativeText: "Sign in to Codex",
                userCode: "ABCD-EFGH",
                promptURL: URL(string: "https://example.com/device")!,
                waitingStatusText: "Waiting",
                copiedStatusText: "Copied",
                browserOpenedStatusText: "Opened",
                copyTitle: "Copy",
                openBrowserTitle: "Open",
                cancelTitle: "Cancel"
            ),
            waitForCompletion: { .failure(CancellationError()) },
            onCancel: { signInCancelled = true }
        )

        #expect(confirmation == false)
        #expect(signInCancelled)
        guard case .cancelled = signInResult else {
            Issue.record("Expected the suppressed sign-in panel to cancel")
            return
        }
    }

    @Test
    func tokenUsageCardHiddenWhenDisabled() throws {
        let (disabled, disabledStatusItem) = try makeCoordinatorWithStatusItem()
        let (enabled, enabledStatusItem) = try makeCoordinatorWithStatusItem(configureTokenUsage: { $0.isEnabled = true })
        defer {
            NSStatusBar.system.removeStatusItem(disabledStatusItem)
            NSStatusBar.system.removeStatusItem(enabledStatusItem)
        }

        #expect(disabled.menuState().tokenUsageCard == nil)
        #expect(enabled.menuState().tokenUsageCard?.period == .last30Days)
    }

    @Test
    func tokenUsageCardSummarizesEachToolWithReadableModelNames() throws {
        let card = makeTokenUsageCard(loadState: .loaded(TokenUsageMenuLoadedData(
            buckets: [],
            allTimePeak: nil,
            tools: [
                toolSeries(.codex, [0: ["gpt-5.6-sol": 3_000, "gpt-6-sol": 1_000]]),
                toolSeries(.claudeCode, [0: ["claude-opus-5-5": 9_000], 1: ["claude-sonnet-5-5": 1_000]]),
            ],
            unavailableTools: [.cursor]
        )))

        #expect(card.subtitle == "Last 30 days · 14K · Today 13K")
        #expect(card.toolSummaries.map(\.tool) == [.codex, .claudeCode, .cursor])
        #expect(card.toolSummaries[0].models == [
            TokenUsageMenuCard.ModelShare(name: "GPT-5.6 Sol", share: 0.75),
            TokenUsageMenuCard.ModelShare(name: "GPT-6 Sol", share: 0.25),
        ])
        #expect(card.toolSummaries[2].isUnavailable)
        #expect(card.topModels.map(\.name) == ["Opus 5.5", "GPT-5.6 Sol", "GPT-6 Sol", "Sonnet 5.5"])
        #expect(card.share(of: .claudeCode) == 10_000.0 / 14_000.0)
        #expect(card.tooltip(forDay: 29) == "May 20: 13K tokens\nCodex 4K · Claude Code 9K")
    }

    @Test
    func tokenUsageCardFirstRunShowsPlaceholderBarsAndOneLoadingLine() {
        let card = makeTokenUsageCard(loadState: .loading(TokenUsageScanProgress(scannedFiles: 8, totalFiles: 100)))

        #expect(card.subtitle == "Last 30 days · Loading 8%")
        #expect(card.showsPlaceholderChart)
        #expect(!card.showsSplits)
        #expect(card.accessibilitySummary == "Token Usage • Last 30 days • Last 30 days · Loading 8%")
    }

    @Test
    func tokenUsageCardShowsTheCachedChartUntilLoadingFinishes() {
        let cached = TokenUsageMenuLoadedData(
            buckets: [],
            allTimePeak: nil,
            tools: [toolSeries(.codex, [1: ["gpt-5.6-sol": 3_000]]), toolSeries(.claudeCode, [:])]
        )
        let loading = makeTokenUsageCard(loadState: .loading(nil, preview: cached))
        let finished = makeTokenUsageCard(loadState: .loaded(TokenUsageMenuLoadedData(
            buckets: [],
            allTimePeak: nil,
            tools: [toolSeries(.codex, [0: ["gpt-5.6-sol": 1_000], 1: ["gpt-5.6-sol": 3_000]]), toolSeries(.claudeCode, [0: ["claude-opus-5-5": 500]])]
        )))

        #expect(loading.subtitle == "Last 30 days · Loading 0%")
        #expect(!loading.showsPlaceholderChart)
        #expect(loading.tokenCount(for: .codex, onDay: 28) == 3_000)
        #expect(!loading.showsSplits)
        #expect(finished.subtitle == "Last 30 days · 4.5K · Today 1.5K")
        #expect(finished.showsSplits)
        #expect(loading.layoutTemplate == finished.layoutTemplate)
        #expect(finished.layoutTemplate.toolSummaries.map(\.models.count) == [3, 3])
        #expect(finished.layoutTemplate.topModels.count == 5)
    }

    @Test
    func tokenUsageCardWithOnlyCodexBucketsStillShowsCodex() {
        let card = makeTokenUsageCard(loadState: loadedTokenUsageData([
            dailyUsage(daysAgo: 1, totalTokens: 7_433_881_744),
            dailyUsage(daysAgo: 0, totalTokens: 108_637_804)
        ]))

        #expect(card.subtitle == "Last 30 days · 7.5B · Today 108.6M")
        #expect(card.toolSummaries.map(\.tool) == [.codex])
        #expect(card.toolSummaries[0].models == [TokenUsageMenuCard.ModelShare(name: "Other", share: 1)])
    }

    @Test
    func tokenUsageCardShowsNoDataAndErrorStates() {
        let noData = makeTokenUsageCard(loadState: loadedTokenUsageData([
            dailyUsage(daysAgo: 1, totalTokens: 0),
            dailyUsage(daysAgo: 0, totalTokens: 0)
        ]))
        let unavailable = makeTokenUsageCard(loadState: .unavailable)

        #expect(!noData.hasData)
        #expect(unavailable.accessibilitySummary.contains("Token usage unavailable"))
    }

    @Test
    func statusItemContentOptionsAreDisabledWhenNoStatusDataExists() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active")),
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
    func mainMenuIncludesDiagnosticReportExportActionNearAbout() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now))),
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
        #expect(report.schemaVersion == 3)
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
    func menuBarLabelOffersOnlyIconOnlyWhenActiveAccountHasNoUsageData() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let state = makeState(activeAccount: makeAccount(name: "Active"))
        let menu = builder.makeMenu(state: state, target: coordinator)

        let content = try #require(statusItemContentMenu(in: menu))
        let iconOnly = try #require(content.items.first(where: { $0.title == "Icon Only" }))
        let iconAndText = try #require(content.items.first(where: { $0.title == "Icon + Text" }))
        let textOnHover = try #require(content.items.first(where: { $0.title == "Text on Hover" }))

        #expect(iconOnly.isEnabled)
        #expect(iconOnly.action == #selector(MenuBarCoordinator.selectStatusBarDisplayMode(_:)))
        #expect(iconOnly.state == .on)
        #expect(!iconAndText.isEnabled)
        #expect(iconAndText.action == nil)
        #expect(iconAndText.state == .off)
        #expect(!textOnHover.isEnabled)
        #expect(textOnHover.action == nil)
        #expect(textOnHover.state == .off)
    }

    @Test
    func statusItemContentOptionsStaySelectableWhenStatusDataExists() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now))),
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
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
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
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
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
    func statusItemMenuIncludesColorCustomizationAndReset() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now))),
            target: coordinator
        )

        let preferencesMenu = try appearanceMenu(in: menu)
        let usageBarsMenu = try #require(preferencesMenu.items.first(where: { $0.title == "Usage Bars" })?.submenu)
        let session = try #require(usageBarsMenu.items.first(where: { $0.title == "Session Color…" }))
        let weekly = try #require(usageBarsMenu.items.first(where: { $0.title == "Weekly Color…" }))
        let sameColor = try #require(usageBarsMenu.items.first(where: { $0.title == "Same Color for Both" }))
        let reset = try #require(usageBarsMenu.items.first(where: { $0.title == "Use Theme Colors" }))

        #expect(session.action == #selector(MenuBarCoordinator.chooseSessionAccentColor(_:)))
        #expect(session.image == nil)
        #expect(weekly.action == #selector(MenuBarCoordinator.chooseWeeklyAccentColor(_:)))
        #expect(sameColor.action == #selector(MenuBarCoordinator.toggleOneUsageColor(_:)))
        #expect(sameColor.state == .on)
        #expect(reset.action == #selector(MenuBarCoordinator.resetUsageColors(_:)))
        #expect(!reset.isEnabled)
    }

    @Test
    func themeMenuListsThemesWithCurrentOneChecked() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)), theme: .honey),
            target: try makeCoordinator()
        )

        let themeMenu = try #require(appearanceMenu(in: menu).items.first(where: { $0.title == "Theme" })?.submenu)

        #expect(themeMenu.items.map(\.title) == ["Cobalt", "Deep Teal", "Emerald", "Violet", "Honey", "Rose", "", "Monochrome", "Tool Colors"])
        #expect(themeMenu.items.filter { $0.state == .on }.map(\.title) == ["Honey"])
    }

    @Test
    func selectingAThemeSavesItAndAppliesItsIcon() throws {
        let applier = AppIconApplierProbe()
        let suiteName = "MenuBarMenuBuilderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStores(userDefaults: defaults)
        let repository = try makeIsolatedRepository()
        let coordinator = MenuBarCoordinator.makeForTesting(
            statusItemRuntime: StatusItemRuntime(statusItem: NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)),
            accountsController: AccountsFeatureFactory(
                repository: repository,
                authService: CodexAuthSnapshotService(repository: repository),
                codexAppProcessClient: CodexAppProcessProbe(),
                accountStatusClient: DisabledAccountStatusClient()
            ).makeController(),
            settings: settings,
            alertPresenter: AlertPresenterProbe(),
            appIconApplier: applier
        )
        func select(_ theme: AppTheme) {
            let item = NSMenuItem()
            item.representedObject = theme.rawValue
            coordinator.selectTheme(item)
        }

        select(.violet)
        select(.toolColors)
        select(.monochrome)

        #expect(settings.themePreferences.theme == .monochrome)
        // Tool Colors has no icon of its own, so Violet's stays until Monochrome picks Graphite.
        #expect(applier.appliedColors == [.violet, .violet, .graphite])
    }

    @Test
    func appearanceMenuGroupsIconAndMarkerControls() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now))),
            target: coordinator
        )

        let preferencesMenu = try appearanceMenu(in: menu)
        let usageBarsMenu = try #require(preferencesMenu.items.first(where: { $0.title == "Usage Bars" })?.submenu)
        let usageBarTitles = usageBarsMenu.items.map(\.title)
        let showMarkers = try #require(usageBarsMenu.items.first(where: { $0.title == "Show Pace Markers" }))

        #expect(preferencesMenu.items.map(\.title) == ["Show Tools", "Menu Bar Label", "Icon Style", "Usage Bars", "Theme", "", "Show Token Usage"])
        #expect(usageBarTitles == [
            "Show % Used", "Show % Left", "",
            "Classic Layout", "Compact Layout", "",
            "Show Pace Markers", "",
            "Session Color…", "Weekly Color…", "Same Color for Both", "Use Theme Colors"
        ])
        #expect(preferencesMenu.items.first(where: { $0.title == "Menu Bar Label" })?.image == nil)
        #expect(preferencesMenu.items.first(where: { $0.title == "Icon Style" })?.image == nil)
        #expect(usageBarsMenu.items.first(where: { $0.title == "Show % Used" })?.state == .on)
        #expect(usageBarsMenu.items.first(where: { $0.title == "Classic Layout" })?.state == .on)
        #expect(showMarkers.action == #selector(MenuBarCoordinator.togglePacingMarkers(_:)))
        #expect(showMarkers.state == .on)
    }

    @Test
    func launchAtLoginPreferenceReflectsEnabledState() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
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
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
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
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
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
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
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

        #expect(alertPresenter.confirmationRequests.last?.messageText == "Launch Refill at Login?")
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

        #expect(alertPresenter.confirmationRequests.last?.messageText == "Launch Refill at Login?")
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
        #expect(alertPresenter.confirmationRequests.last?.messageText == "Launch Refill at Login?")
        #expect(loginItemController.currentState == .disabled)
        #expect(alertPresenter.infoRequests.last?.informativeText == "Could not update Launch at Login. Open System Settings and try again.")
    }

    @Test
    func statusItemMenuEnablesUseDefaultWhenCustomAccentColorExists() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
                sessionAccentColor: NSColor(deviceRed: 0.12, green: 0.45, blue: 0.78, alpha: 1),
                hasCustomUsageColors: true
            ),
            target: coordinator
        )

        let preferencesMenu = try appearanceMenu(in: menu)
        let usageBarsMenu = try #require(preferencesMenu.items.first(where: { $0.title == "Usage Bars" })?.submenu)
        let reset = try #require(usageBarsMenu.items.first(where: { $0.title == "Use Theme Colors" }))

        #expect(reset.action == #selector(MenuBarCoordinator.resetUsageColors(_:)))
        #expect(reset.isEnabled)
    }

    @Test
    func openingMenuKeepsTheSameMenuInstanceAttachedToStatusItem() throws {
        let builder = MenuBarMenuBuilder()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
                inactiveAccounts: [makeAccount(name: "Business 3", usage: makeUsage(resettingAfter: .now))]
            ),
            target: coordinator
        )

        statusItem.menu = menu
        coordinator.menuWillOpen(menu)

        #expect(statusItem.menu === menu)
    }

    @Test
    func menuNeedsUpdateDoesNotRepopulateMenuItemsDuringOpen() throws {
        let builder = MenuBarMenuBuilder()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
                inactiveAccounts: [makeAccount(name: "Business 3", usage: makeUsage(resettingAfter: .now))]
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

    @Test
    func tokenUsageProgressDoesNotRepopulateMenuItemsDuringOpen() async throws {
        let builder = MenuBarMenuBuilder()
        let provider = TokenUsageMenuProviderProbe()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem(
            tokenUsageProvider: provider,
            configureTokenUsage: {
                $0.isEnabled = true
                $0.period = .last30Days
            }
        )
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
                tokenUsageEnabled: true,
                tokenUsageCard: makeTokenUsageCard(loadState: .loading(nil))
            ),
            target: coordinator
        )

        statusItem.menu = menu
        let itemsBeforeProgress = menu.items
        coordinator.menuWillOpen(menu)

        await waitUntil { await provider.loadCount == 1 }
        await yieldMainActorWork()

        #expect(menuItems(menu.items, areSameInstancesAs: itemsBeforeProgress))

        await provider.finish(with: [
            dailyUsage(daysAgo: 1, totalTokens: 7_433_881_744),
            dailyUsage(daysAgo: 0, totalTokens: 108_637_804)
        ])
        await yieldMainActorWork()

        #expect(menuItems(menu.items, areSameInstancesAs: itemsBeforeProgress))

        coordinator.menuDidClose(menu)
        await waitUntil { !menuItems(menu.items, areSameInstancesAs: itemsBeforeProgress) }

        #expect(!menuItems(menu.items, areSameInstancesAs: itemsBeforeProgress))
    }

    @Test
    func openTokenUsageCardUpdatesInPlaceAsDataArrives() async throws {
        let provider = TokenUsageMenuProviderProbe()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem(
            tokenUsageProvider: provider,
            configureTokenUsage: { $0.isEnabled = true }
        )
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let menu = MenuBarMenuBuilder().makeMenu(state: coordinator.menuState(), target: coordinator)
        statusItem.menu = menu
        let liveCard = try #require(coordinator.menuState().tokenUsage)

        coordinator.menuWillOpen(menu)
        await waitUntil { await provider.loadCount == 1 }
        await provider.finish(with: [dailyUsage(daysAgo: 0, totalTokens: 1_200)])
        await waitUntil { liveCard.card.phase == .loaded }

        #expect(liveCard.card.phase == .loaded)
        #expect(coordinator.menuState().tokenUsage === liveCard)
    }

    @Test
    func tokenUsageProgressWhileMenuClosedDefersMenuRebuildUntilNextOpen() async throws {
        let builder = MenuBarMenuBuilder()
        let provider = TokenUsageMenuProviderProbe()
        let loginItemController = LoginItemControllerProbe()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem(
            loginItemController: loginItemController,
            tokenUsageProvider: provider,
            configureTokenUsage: {
                $0.isEnabled = true
                $0.period = .last30Days
            }
        )
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
                tokenUsageEnabled: true,
                tokenUsageCard: makeTokenUsageCard(loadState: .loading(nil))
            ),
            target: coordinator
        )

        statusItem.menu = menu
        coordinator.menuWillOpen(menu)
        await waitUntil { await provider.loadCount == 1 }
        await yieldMainActorWork()

        let itemsBeforeClose = menu.items
        coordinator.menuDidClose(menu)
        await waitUntil { !menuItems(menu.items, areSameInstancesAs: itemsBeforeClose) }

        let itemsBeforeClosedProgress = menu.items
        let stateCallCountBeforeClosedProgress = loginItemController.stateCallCount

        await provider.emitProgress(TokenUsageScanProgress(scannedFiles: 10, totalFiles: 10))
        await yieldMainActorWork()

        #expect(loginItemController.stateCallCount == stateCallCountBeforeClosedProgress)
        #expect(menuItems(menu.items, areSameInstancesAs: itemsBeforeClosedProgress))

        coordinator.menuWillOpen(menu)
        await yieldMainActorWork()

        #expect(loginItemController.stateCallCount > stateCallCountBeforeClosedProgress)
        #expect(!menuItems(menu.items, areSameInstancesAs: itemsBeforeClosedProgress))
    }

    @Test
    func mainMenuShowsOneCardPerToolThenTheAppItemsAndQuit() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
                providerUsage: [
                    ProviderUsageState(provider: .claude, status: .current(providerSnapshot(.claude))),
                    ProviderUsageState(provider: .cursor, status: .current(providerSnapshot(.cursor))),
                ]
            ),
            target: try makeCoordinator()
        )

        #expect(menu.items.map(\.title) == [
            "Claude", "", "Codex", "", "Cursor", "",
            "Add Account", "", "Appearance", "Refresh Every", "Hide Emails", "Launch at Login", "", "Diagnostics…", "About", "",
            "Quit",
        ])
        #expect(!menu.items.contains { $0.title == "Settings" })
        #expect(menu.items.filter { $0.view is MenuCardItemView }.map(\.title) == ["Claude", "Codex", "Cursor"])
        #expect(menu.items.filter { $0.view is MenuCardItemView }.allSatisfy { $0.submenu != nil })
        #expect(menu.items.last?.keyEquivalent == "q")
    }

    @Test
    func firstRunMenuOffersOnlyCodexUnderAddAccount() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: nil,
                providerUsage: [
                    ProviderUsageState(provider: .claude, status: .notConnected),
                    ProviderUsageState(provider: .cursor, status: .notConnected),
                ]
            ),
            target: try makeCoordinator()
        )
        let addAccount = try #require(menu.items.first?.submenu)

        #expect(menu.items.map(\.title) == [
            "Add Account", "", "Appearance", "Refresh Every", "Hide Emails", "Launch at Login", "", "Diagnostics…", "About", "", "Quit",
        ])
        #expect(addAccount.items.map(\.title) == ["Codex…"])
        #expect(addAccount.items.map(providerAction) == [.addAccount])
    }

    @Test
    func codexSideMenuSwitchesAccountsAndUsesResetsWhileTokenUsageFollowsTheToolCards() throws {
        let nov5 = Date(timeIntervalSince1970: 1_793_880_000)
        var usage = makeUsage(resettingAfter: .now)
        usage.resetCredits = UsageResetCredits(
            availableCount: 2,
            credits: [UsageResetCredit(expiresAt: nov5.addingTimeInterval(15 * 86_400)), UsageResetCredit(expiresAt: nov5)]
        )
        let active = makeAccount(email: "alex@example.com", usage: usage)
        let first = makeAccount(email: "side@example.com")
        let second = makeAccount(email: "team@example.com")
        let menu = MenuBarMenuBuilder(locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "GMT")!).makeMenu(
            state: makeState(
                activeAccount: active,
                inactiveAccounts: [first, second],
                tokenUsageEnabled: true,
                tokenUsageCard: makeTokenUsageCard(loadState: .loading(nil))
            ),
            target: try makeCoordinator()
        )

        let side = try #require(menu.items.first { $0.title == "Codex" }?.submenu)
        let rows = try side.items[1...2].map { try #require($0.submenu) }

        #expect(side.items.map(\.title) == [
            "alex@example.com", "side@example.com", "team@example.com", "",
            "Use a Reset…", "Expires 5 Nov", "Expires 20 Nov", "",
            "Add Codex Account…",
        ])
        let codexIndex = try #require(menu.items.firstIndex { $0.title == "Codex" })
        let tokenUsageIndex = try #require(menu.items.firstIndex { $0.title == "Token Usage" })
        let addAccountIndex = try #require(menu.items.firstIndex { $0.title.hasPrefix("Add Account") })
        #expect(codexIndex < tokenUsageIndex && tokenUsageIndex < addAccountIndex)
        #expect(menu.items[tokenUsageIndex].view != nil && menu.items[tokenUsageIndex].submenu == nil)
        #expect(side.items[0].state == .on && !side.items[0].isEnabled && side.items[0].submenu == nil)
        #expect(rows.map { $0.items.map(\.title) } == [["Use", "Remove…"], ["Use", "Remove…"]])
        #expect(rows.map { $0.items.map(providerAction) } == [
            [.switchAccount(first.id), .removeAccount(first.id)], [.switchAccount(second.id), .removeAccount(second.id)],
        ])
        #expect(side.items[5].isEnabled == false && side.items[5].indentationLevel == 1)
        #expect(providerAction(side.items[4]) == .useResetCredit)
    }

    @Test(arguments: [UsageProvider.claude, .cursor])
    func claudeAndCursorSideMenusShowOnlyTheSignedInEmail(provider: UsageProvider) throws {
        var usage = providerSnapshot(provider)
        usage.accountEmail = "alex@example.com"
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(activeAccount: nil, providerUsage: [ProviderUsageState(provider: provider, status: .current(usage))]),
            target: try makeCoordinator()
        )

        let side = try #require(menu.items.first?.submenu)

        #expect(side.items.map(\.title) == ["alex@example.com"])
        #expect(side.items[0].state == .on && !side.items[0].isEnabled && side.items[0].submenu == nil)
    }

    @Test
    func showToolsChecksEachVisibleToolAndUncheckingIsDisconnect() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
                providerUsage: [
                    ProviderUsageState(provider: .claude, status: .current(providerSnapshot(.claude))),
                    ProviderUsageState(provider: .cursor, status: .notConnected),
                ]
            ),
            target: try makeCoordinator()
        )

        let tools = try #require(try appearanceMenu(in: menu).items.first { $0.title == "Show Tools" }?.submenu)

        #expect(tools.items.map(\.title) == ["Claude", "Codex", "Cursor"])
        #expect(tools.items.map(\.state) == [.on, .on, .off])
        #expect(tools.items.map(providerAction) == [.disconnect, .disconnect, .connect])
        #expect(tools.items.allSatisfy { $0.isEnabled })
        #expect(!menu.items.contains { $0.title.hasPrefix("Disconnect") })
    }

    @Test
    func claudeSideMenuShowsTheMaskedEmailOfItsLastReadingAndAKeychainStateAddsItsActionUnderTheCard() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lastUsage = UsageSnapshot(
            provider: .claude,
            planName: "max",
            windows: [UsageWindow(kind: .session, usedPercent: 12, resetsAt: now.addingTimeInterval(3_600), durationMinutes: 300)],
            fetchedAt: now,
            accountEmail: "alex@example.com"
        )
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Work", usage: makeUsage(resettingAfter: now)),
                providerUsage: [ProviderUsageState(provider: .claude, status: .unavailable(.keychainAccessNeeded, lastSnapshot: lastUsage))],
                masksEmails: true,
                now: now
            ),
            target: try makeCoordinator()
        )

        let side = try #require(menu.items.first?.submenu)

        #expect(menu.items.map(\.title) == ["Claude", "Allow Keychain Access…", "", "Codex", "", "Add Account", "", "Appearance", "Refresh Every", "Hide Emails", "Launch at Login", "", "Diagnostics…", "About", "", "Quit"])
        #expect(providerAction(menu.items[1]) == .allowKeychainAccess)
        #expect(side.items.map(\.title) == ["a•••x@example.com", "", "Move to Top", "Move Up", "Move Down"])
        #expect(side.items.filter { $0.title.hasPrefix("Move") }.map(\.isEnabled) == [false, false, true])
        #expect(side.items[2...4].compactMap { $0.representedObject as? [UsageProvider] } == [[.codex, .claude, .cursor]])
    }

    @Test
    func aSignedOutClaudeOffersRefillsOwnSignInUnderTheCardAndInItsSideMenu() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: nil,
                providerUsage: [ProviderUsageState(provider: .claude, status: .unavailable(.signInExpired, lastSnapshot: nil), ownSignIn: .signedOut)]
            ),
            target: try makeCoordinator()
        )

        let side = try #require(menu.items.first?.submenu)

        #expect(Array(menu.items.map(\.title).prefix(4)) == ["Claude", "Sign in with Claude…", "", "Add Account"])
        #expect(providerAction(menu.items[1]) == .signIn)
        #expect(side.items.map(\.title) == ["Sign in with Claude…"])
        #expect(side.items.map(providerAction) == [.signIn])
    }

    @Test
    func claudeSignedInWithRefillShowsItsEmailThenSignOut() throws {
        var usage = providerSnapshot(.claude)
        usage.accountEmail = "alex@example.com"
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(activeAccount: nil, providerUsage: [ProviderUsageState(provider: .claude, status: .current(usage), ownSignIn: .signedIn)]),
            target: try makeCoordinator()
        )

        let side = try #require(menu.items.first?.submenu)

        #expect(Array(menu.items.map(\.title).prefix(3)) == ["Claude", "", "Add Account"])
        #expect(side.items.map(\.title) == ["alex@example.com", "", "Sign Out of Claude"])
        #expect(providerAction(side.items[2]) == .signOut)
    }

    @Test(arguments: [UsageProvider.claude, .cursor])
    func aSignedOutToolOffersNoSignIn(provider: UsageProvider) throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(activeAccount: nil, providerUsage: [ProviderUsageState(provider: provider, status: .unavailable(.signedOut, lastSnapshot: nil))]),
            target: try makeCoordinator()
        )

        #expect(Array(menu.items.map(\.title).prefix(3)) == [provider.copy.sectionTitle, "", "Add Account"])
        #expect(try #require(menu.items.first?.submenu).items.isEmpty)
    }

    @Test
    func mainMenuHoldsSetupAndRareChoicesUnderTheCards() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
                providerUsage: [ProviderUsageState(provider: .claude, status: .current(providerSnapshot(.claude)))],
                masksEmails: true
            ),
            target: try makeCoordinator()
        )

        let addAccount = try #require(menu.items.first { $0.title == "Add Account" }?.submenu)
        let refresh = try #require(menu.items.first { $0.title == "Refresh Every" }?.submenu)

        #expect(menu.items.map(\.title) == ["Claude", "", "Codex", "", "Add Account", "", "Appearance", "Refresh Every", "Hide Emails", "Launch at Login", "", "Diagnostics…", "About", "", "Quit"])
        #expect(menu.items.first { $0.title == "Hide Emails" }?.state == .on)
        #expect(addAccount.items.map(\.title) == ["Codex…"])
        #expect(addAccount.items.map(providerAction) == [.addAccount])
        #expect(refresh.items.map(\.title) == ["1 minute", "2 minutes", "5 minutes", "10 minutes", "15 minutes", "30 minutes"])
        #expect(refresh.items.first { $0.state == .on }?.title == "5 minutes")
    }

    @Test
    func hideEmailsAndSectionMovesPersistThroughTheCoordinator() throws {
        let coordinator = try makeCoordinator()
        let move = NSMenuItem()
        move.representedObject = [UsageProvider.cursor, .codex, .claude]

        coordinator.toggleMasksEmails(NSMenuItem())
        coordinator.reorderTools(move)

        #expect(coordinator.menuState().masksEmails)
        #expect(coordinator.menuState().toolOrder == [.cursor, .codex, .claude])
    }

    @Test
    func claudeSideMenuNamesTheModelLimitToggleAfterTheReadingsModels() throws {
        func sideMenuTitles(modelNames: [String]) throws -> [String] {
            let menu = MenuBarMenuBuilder().makeMenu(state: claudeState(modelNames: modelNames), target: try makeCoordinator())
            return try #require(menu.items.first?.submenu).items.map(\.title)
        }

        #expect(try sideMenuTitles(modelNames: ["Fable"]) == ["alex@example.com", "", "Show Fable Limits"])
        #expect(try sideMenuTitles(modelNames: ["Fable", "Opus", "Sonnet"]) == ["alex@example.com", "", "Show Fable, Opus and Sonnet Limits"])
        #expect(try sideMenuTitles(modelNames: []) == ["alex@example.com"])
    }

    @Test
    func turningOffTheFableToggleHidesTheFableThisWeekMeter() throws {
        let coordinator = try makeCoordinator()
        func claudeMenu() throws -> (card: NSMenuItem, toggle: NSMenuItem) {
            let menu = MenuBarMenuBuilder().makeMenu(
                state: claudeState(modelNames: ["Fable"], showsModelLimits: coordinator.menuState().showsModelLimits),
                target: coordinator
            )
            let card = try #require(menu.items.first)
            let side = try #require(card.submenu)
            return (card, try #require(side.items.first { $0.title == "Show Fable Limits" }))
        }

        let before = try claudeMenu()
        NSApplication.shared.sendAction(try #require(before.toggle.action), to: before.toggle.target, from: before.toggle)
        let after = try claudeMenu()

        #expect(before.toggle.state == .on)
        #expect(after.toggle.state == .off)
        #expect(try #require(after.card.view).frame.height < (try #require(before.card.view).frame.height))
    }

    /// A Claude reading with Session, Weekly and one weekly limit per model in `modelNames`.
    private func claudeState(modelNames: [String], showsModelLimits: Bool = true) -> MenuBarMenuState {
        let reset = Date.now.addingTimeInterval(86_400)
        let snapshot = UsageSnapshot(
            provider: .claude,
            planName: "max",
            windows: [
                UsageWindow(kind: .session, usedPercent: 12, resetsAt: reset, durationMinutes: 300),
                UsageWindow(kind: .weekly, usedPercent: 40, resetsAt: reset, durationMinutes: 10_080),
            ] + modelNames.map { UsageWindow(kind: .modelWeekly(modelName: $0), usedPercent: 8, resetsAt: reset, durationMinutes: 10_080) },
            fetchedAt: .now,
            accountEmail: "alex@example.com"
        )
        return makeState(
            activeAccount: nil,
            providerUsage: [ProviderUsageState(provider: .claude, status: .current(snapshot))],
            showsModelLimits: showsModelLimits
        )
    }

    private func providerSnapshot(_ provider: UsageProvider) -> UsageSnapshot {
        let kind: UsageWindowKind = provider == .cursor ? .billingCycle : .weekly
        return UsageSnapshot(
            provider: provider,
            planName: "pro",
            windows: [UsageWindow(kind: kind, usedPercent: 40, resetsAt: .now.addingTimeInterval(86_400), durationMinutes: nil)],
            fetchedAt: .now
        )
    }

    private func appearanceMenu(in menu: NSMenu) throws -> NSMenu {
        try #require(menu.items.first(where: { $0.title == "Appearance" })?.submenu)
    }

    private func statusItemContentMenu(in menu: NSMenu) -> NSMenu? {
        try? appearanceMenu(in: menu).items.first(where: { $0.title == "Menu Bar Label" })?.submenu
    }

    private func launchAtLoginItem(in menu: NSMenu) throws -> NSMenuItem {
        try #require(menu.items.first(where: { $0.title.hasPrefix("Launch at Login") }))
    }

    private func makeCoordinator() throws -> MenuBarCoordinator {
        try makeCoordinatorWithStatusItem().0
    }

    private func makeCoordinatorWithStatusItem(
        alertPresenter: AlertPresenterProbe? = nil,
        loginItemController: LoginItemControlling = LoginItemControllerProbe(),
        loginItemsSettingsLauncher: LoginItemsSettingsLaunching = LoginItemsSettingsLauncherProbe(),
        diagnosticReportPresenter: DiagnosticReportPresenting? = nil,
        tokenUsageProvider: TokenUsageMenuProviding = LocalCodexSessionTokenUsageMenuProvider(
            cacheFile: FileManager.default.temporaryDirectory
                .appendingPathComponent("MenuBarMenuBuilderTests-\(UUID().uuidString)/token-usage-cache.json")
        ),
        configureTokenUsage: (TokenUsagePreferencesStore) -> Void = { _ in }
    ) throws -> (MenuBarCoordinator, NSStatusItem) {
        let repository = try makeIsolatedRepository()
        let accountsController = AccountsFeatureFactory(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: CodexAppProcessProbe(),
            accountStatusClient: DisabledAccountStatusClient()
        ).makeController()
        let suiteName = "MenuBarMenuBuilderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStores(userDefaults: defaults)
        configureTokenUsage(settings.tokenUsagePreferences)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let statusItemRuntime = StatusItemRuntime(statusItem: statusItem)
        let coordinator = MenuBarCoordinator.makeForTesting(
            statusItemRuntime: statusItemRuntime,
            accountsController: accountsController,
            settings: settings,
            alertPresenter: alertPresenter ?? AlertPresenterProbe(),
            panelPresenter: PanelPresenterProbe(),
            loginItemController: loginItemController,
            loginItemsSettingsLauncher: loginItemsSettingsLauncher,
            diagnosticReportPresenter: diagnosticReportPresenter ?? DiagnosticReportPresenterProbe(),
            tokenUsageProvider: tokenUsageProvider
        )
        return (coordinator, statusItem)
    }

    private func makeIsolatedRepository() throws -> AccountRepository {
        let appSupportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarMenuBuilderTests-\(UUID().uuidString)", isDirectory: true)
        return try AccountRepository(
            isolatedRootDirectory: appSupportDirectory
        )
    }

    private func waitUntil(
        _ condition: @escaping () async -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<100 {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for async condition", sourceLocation: sourceLocation)
    }

    private func yieldMainActorWork() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    private func menuItems(_ items: [NSMenuItem], areSameInstancesAs expectedItems: [NSMenuItem]) -> Bool {
        guard items.count == expectedItems.count else { return false }
        return zip(items, expectedItems).allSatisfy { item, expectedItem in
            item === expectedItem
        }
    }

    private func makeState(
        activeAccount: CodexAccount?,
        inactiveAccounts: [CodexAccount] = [],
        sessionAccentColor: NSColor? = nil,
        hasCustomUsageColors: Bool = false,
        usagePercentMode: UsagePercentMode = .used,
        loginItemState: LoginItemState = .disabled,
        revealStatusItemTitleShortcut: Refill.KeyboardShortcut? = .defaultRevealStatusItemTitle,
        isBusy: Bool = false,
        tokenUsageEnabled: Bool = false,
        tokenUsageCard: TokenUsageMenuCard? = nil,
        providerUsage: [ProviderUsageState] = [],
        toolOrder: [UsageProvider] = [.claude, .codex, .cursor],
        masksEmails: Bool = false,
        theme: AppTheme = .cobalt,
        showsModelLimits: Bool = true,
        now: Date = .now
    ) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: inactiveAccounts,
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
            statusBarIndicatorStyle: .moon,
            statusBarDisplayMode: .textOnHover,
            revealStatusItemTitleShortcut: revealStatusItemTitleShortcut,
            sessionAccentColor: sessionAccentColor,
            hasCustomUsageColors: hasCustomUsageColors,
            usagePercentMode: usagePercentMode,
            isBusy: isBusy,
            statusMessage: "Ready",
            loginItemState: loginItemState,
            tokenUsageEnabled: tokenUsageEnabled,
            tokenUsage: tokenUsageCard.map {
                TokenUsageCardModel(card: $0, preferences: TokenUsagePreferencesStore(userDefaults: UserDefaults(suiteName: "token-usage-\(UUID().uuidString)")!))
            },
            providerUsage: providerUsage,
            toolOrder: toolOrder,
            masksEmails: masksEmails,
            showsModelLimits: showsModelLimits,
            theme: theme,
            now: now
        )
    }

    private var tokenUsageNow: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 12))!
    }

    private func makeTokenUsageCard(
        period: CodexTokenUsagePeriod = .last30Days,
        loadState: TokenUsageMenuLoadState
    ) -> TokenUsageMenuCard {
        TokenUsageMenuCard.make(
            period: period,
            loadState: loadState,
            calendar: Calendar(identifier: .gregorian),
            now: tokenUsageNow
        )
    }

    /// Daily models by days before `tokenUsageNow`.
    private func toolSeries(_ tool: TokenUsageTool, _ modelsByDaysAgo: [Int: [String: Int]]) -> ToolTokenUsageSeries {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: tokenUsageNow)
        return ToolTokenUsageSeries(tool: tool, days: modelsByDaysAgo.map { daysAgo, models in
            ToolDailyTokenUsage(day: calendar.date(byAdding: .day, value: -daysAgo, to: today)!, tokensByModel: models)
        })
    }

    private func totals(_ total: Int) -> CodexTokenUsageTotals {
        CodexTokenUsageTotals(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: total)
    }

    private func loadedTokenUsageData(
        _ buckets: [CodexDailyTokenUsage],
        allTimePeak: CodexDailyTokenUsage? = nil
    ) -> TokenUsageMenuLoadState {
        .loaded(TokenUsageMenuLoadedData(buckets: buckets, allTimePeak: allTimePeak))
    }

    private func dailyUsage(daysAgo: Int, totalTokens: Int) -> CodexDailyTokenUsage {
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)) ?? .now
        return CodexDailyTokenUsage(
            day: calendar.date(byAdding: .day, value: -daysAgo, to: base) ?? base,
            usage: CodexTokenUsageTotals(
                inputTokens: 0,
                cachedInputTokens: 0,
                outputTokens: 0,
                reasoningOutputTokens: 0,
                totalTokens: totalTokens
            )
        )
    }
}

/// The tool action a menu item sends, or nil when it sends none.
@MainActor
private func providerAction(_ item: NSMenuItem) -> ProviderAction? {
    guard item.action == #selector(MenuBarCoordinator.performProviderAction(_:)),
          let menuAction = item.representedObject as? ProviderMenuAction
    else { return nil }
    return menuAction.action
}
