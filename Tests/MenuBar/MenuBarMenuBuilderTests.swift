import AppKit
import Foundation
import SwiftUI
import Testing

@testable import RUsage

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
    /// Waits for the sign-in the way the real panel does, instead of returning `addAccountSignInResult`.
    var waitsForSignIn = false

    func presentAddAccountSignIn(
        _ request: MenuBarAddAccountSignInPanelRequest,
        waitForCompletion: @escaping () async -> Result<CodexSignedInAccount, Error>,
        onCancel _: @escaping () -> Void
    ) async -> MenuBarAddAccountSignInPanelResult {
        addAccountSignInRequests.append(request)
        guard waitsForSignIn else { return addAccountSignInResult }
        switch await waitForCompletion() {
        case .success(let signedIn): return .completed(signedIn)
        case .failure(let error): return .failed(error)
        }
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
        return URL(fileURLWithPath: "/tmp/rusage-Diagnostics.json")
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
                messageText: "rusage Error",
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
    func tokenUsageCardFollowsTheMenuToolOrder() {
        let card = makeTokenUsageCard(
            loadState: .loaded(TokenUsageMenuLoadedData(
                buckets: [],
                allTimePeak: nil,
                tools: [
                    toolSeries(.codex, [0: ["gpt-5.6-sol": 4_000]]),
                    toolSeries(.claudeCode, [0: ["claude-opus-5-5": 9_000]]),
                ],
                unavailableTools: [.cursor]
            )),
            shownTools: [.claudeCode, .cursor, .codex]
        )

        #expect(card.tools.map(\.tool) == [.claudeCode, .codex])
        #expect(card.toolSummaries.map(\.tool) == [.claudeCode, .cursor, .codex])
        #expect(card.tooltip(forDay: 29) == "May 20: 13K tokens\nClaude Code 9K · Codex 4K")
    }

    @Test
    func tokenUsageCardLeavesOutToolsTheMenuHides() {
        let card = makeTokenUsageCard(
            loadState: .loaded(TokenUsageMenuLoadedData(
                buckets: [],
                allTimePeak: nil,
                tools: [
                    toolSeries(.codex, [0: ["gpt-5.6-sol": 4_000]]),
                    toolSeries(.claudeCode, [0: ["claude-opus-5-5": 9_000]]),
                ],
                unavailableTools: [.cursor]
            )),
            shownTools: [.claudeCode]
        )

        #expect(card.toolSummaries.map(\.tool) == [.claudeCode])
        #expect(card.subtitle == "Last 30 days · 9K · Today 9K")
        #expect(card.topModels.map(\.name) == ["Opus 5.5"])
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
    func settingsItemOpensTheSettingsWindowWithCommandComma() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now))),
            target: try makeCoordinator()
        )

        let settings = try #require(menu.items.first { $0.title == "Settings…" })

        #expect(settings.action == #selector(MenuBarCoordinator.openSettings))
        #expect(settings.keyEquivalent == ",")
        #expect(settings.keyEquivalentModifierMask == .command)
        #expect(settings.isEnabled)
    }

    @Test
    func settingsWindowShowsItsPanesAndDropsTheirContentOnClose() throws {
        let coordinator = try makeCoordinator()

        coordinator.openSettings()

        #expect(coordinator.settingsWindow.paneTitles == ["General", "Accounts", "Menu Bar", "Usage Bars", "Tools", "Token Usage"])
        coordinator.settingsWindow.window?.close()
        #expect(!coordinator.settingsWindow.isShown)
    }

    @Test
    func settingsWindowStateFollowsWhatTheMenuShows() throws {
        let state = SettingsWindowState()

        state.update(from: makeState(
            activeAccount: makeAccount(name: "Active"),
            loginItemState: .requiresApproval,
            providerUsage: [
                ProviderUsageState(provider: .claude, status: .current(providerSnapshot(.claude))),
                ProviderUsageState(provider: .cursor, status: .notConnected),
            ]
        ))

        #expect(state.shownTools == [.claude, .codex])
        #expect(state.toolSections.map(\.provider) == [.claude, .codex])
        #expect(state.loginItemState == .requiresApproval)
        #expect(state.canShowMenuBarText)

        state.update(from: makeState(activeAccount: makeAccount(name: "Active")))

        #expect(state.shownTools == [.codex])
        #expect(!state.canShowMenuBarText)
    }

    @Test
    func turningOnTokenUsageFromSettingsAddsItsCard() throws {
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        coordinator.setTokenUsageDisplay(.graphWithBreakdownOnHover)

        #expect(coordinator.menuState().tokenUsage != nil)
        #expect(statusItem.menu?.items.contains { $0.title == "Token Usage" } == true)
    }

    @Test
    func breakdownOnHoverMovesTheBreakdownIntoTheCardsSideMenu() throws {
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        coordinator.setTokenUsageDisplay(.graphWithBreakdownOnHover)
        let onHover = try #require(statusItem.menu?.items.first { $0.title == "Token Usage" })
        #expect(onHover.submenu?.items.map(\.title) == ["Breakdown"])
        #expect(onHover.submenu?.items.first?.view != nil)

        coordinator.setTokenUsageDisplay(.graphAndBreakdown)
        let both = try #require(statusItem.menu?.items.first { $0.title == "Token Usage" })
        #expect(both.submenu == nil)
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
    func coordinatorTogglesLaunchAtLoginFromDisabledToEnabled() throws {
        let loginItemController = LoginItemControllerProbe(currentState: .disabled)
        let alertPresenter = AlertPresenterProbe()
        alertPresenter.confirmationResponse = true
        let coordinator = try makeCoordinatorWithStatusItem(
            alertPresenter: alertPresenter,
            loginItemController: loginItemController
        ).0

        coordinator.setLaunchAtLogin(true)

        #expect(alertPresenter.confirmationRequests.last?.messageText == "Launch rusage at Login?")
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

        coordinator.setLaunchAtLogin(true)

        #expect(alertPresenter.confirmationRequests.last?.messageText == "Launch rusage at Login?")
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

        coordinator.setLaunchAtLogin(false)

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

        coordinator.setLaunchAtLogin(true)

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

        coordinator.setLaunchAtLogin(true)

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

        coordinator.setLaunchAtLogin(true)

        #expect(loginItemController.setEnabledCalls.isEmpty)
        #expect(alertPresenter.confirmationRequests.last?.messageText == "Launch rusage at Login?")
        #expect(loginItemController.currentState == .disabled)
        #expect(alertPresenter.infoRequests.last?.informativeText == "Could not update Launch at Login. Open System Settings and try again.")
    }

    @Test
    func openingMenuKeepsTheSameMenuInstanceAttachedToStatusItem() throws {
        let builder = MenuBarMenuBuilder()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now))
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
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now))
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
            configureTokenUsage: { $0.isEnabled = true }
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
    func tokenUsageCardLeavesOutCodexWhenTheMenuHidesIt() async throws {
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

        // No saved Codex account, so the menu shows no Codex card and the Token Usage card leaves Codex out too.
        #expect(coordinator.menuState().toolSections.isEmpty)
        #expect(liveCard.card.tools.isEmpty)
        #expect(!liveCard.card.hasData)
    }

    @Test
    func tokenUsageProgressWhileMenuClosedDefersMenuRebuildUntilNextOpen() async throws {
        let builder = MenuBarMenuBuilder()
        let provider = TokenUsageMenuProviderProbe()
        let loginItemController = LoginItemControllerProbe()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem(
            loginItemController: loginItemController,
            tokenUsageProvider: provider,
            configureTokenUsage: { $0.isEnabled = true }
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
            "Settings…", "", "Diagnostics…", "About", "",
            "Quit",
        ])
        #expect(!menu.items.contains { $0.title == "Settings" })
        #expect(menu.items.filter { $0.view is MenuCardItemView }.map(\.title) == ["Claude", "Codex", "Cursor"])
        #expect(menu.items.filter { $0.view is MenuCardItemView }.allSatisfy { $0.submenu != nil })
        #expect(menu.items.last?.keyEquivalent == "q")
    }

    @Test
    func firstRunMenuStartsAtSettings() throws {
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

        #expect(menu.items.map(\.title) == ["Settings…", "", "Diagnostics…", "About", "", "Quit"])
    }

    @Test
    func codexSideMenuShowsTheAccountAndItsResetsWhileTokenUsageFollowsTheToolCards() throws {
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
                tokenUsageEnabled: true,
                tokenUsageCard: makeTokenUsageCard(loadState: .loading(nil))
            ),
            target: try makeCoordinator()
        )

        let side = try #require(menu.items.first { $0.title == "Codex" }?.submenu)

        #expect(side.items.map(\.title) == ["alex@example.com", "", "Use a Reset…", "Expires 5 Nov", "Expires 20 Nov"])
        let codexIndex = try #require(menu.items.firstIndex { $0.title == "Codex" })
        let tokenUsageIndex = try #require(menu.items.firstIndex { $0.title == "Token Usage" })
        let settingsIndex = try #require(menu.items.firstIndex { $0.title == "Settings…" })
        #expect(codexIndex < tokenUsageIndex && tokenUsageIndex < settingsIndex)
        #expect(menu.items[tokenUsageIndex].view != nil && menu.items[tokenUsageIndex].submenu == nil)
        #expect(side.items[0].state == .on && !side.items[0].isEnabled && side.items[0].submenu == nil)
        #expect(side.items[3].isEnabled == false && side.items[3].indentationLevel == 1)
        #expect(providerAction(side.items[2]) == .useResetCredit)
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

        #expect(menu.items.map(\.title) == ["Claude", "Allow Keychain Access…", "", "Codex", "", "Settings…", "", "Diagnostics…", "About", "", "Quit"])
        #expect(providerAction(menu.items[1]) == .allowKeychainAccess)
        #expect(side.items.map(\.title) == ["a•••x@example.com"])
    }

    @Test
    func aSignedOutClaudeOffersRUsagesOwnSignInUnderTheCardOnly() throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(
                activeAccount: nil,
                providerUsage: [ProviderUsageState(provider: .claude, status: .unavailable(.signInExpired, lastSnapshot: nil), ownSignIn: .signedOut)]
            ),
            target: try makeCoordinator()
        )

        let side = try #require(menu.items.first?.submenu)

        #expect(Array(menu.items.map(\.title).prefix(4)) == ["Claude", "Sign in with Claude…", "", "Settings…"])
        #expect(providerAction(menu.items[1]) == .signIn)
        #expect(!side.items.contains { providerAction($0) == .signIn })
    }

    @Test
    func claudeReadingClaudeCodesSignInShowsOnlyItsEmailInTheSideMenu() throws {
        var usage = providerSnapshot(.claude)
        usage.accountEmail = "alex@example.com"
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(activeAccount: nil, providerUsage: [ProviderUsageState(provider: .claude, status: .current(usage), ownSignIn: .signedOut)]),
            target: try makeCoordinator()
        )

        let side = try #require(menu.items.first?.submenu)

        #expect(Array(menu.items.map(\.title).prefix(3)) == ["Claude", "", "Settings…"])
        #expect(side.items.map(\.title) == ["alex@example.com"])
    }

    @Test
    func claudeSignedInWithRUsageShowsItsEmail() throws {
        var usage = providerSnapshot(.claude)
        usage.accountEmail = "alex@example.com"
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(activeAccount: nil, providerUsage: [ProviderUsageState(provider: .claude, status: .current(usage), ownSignIn: .signedIn)]),
            target: try makeCoordinator()
        )

        let side = try #require(menu.items.first?.submenu)

        #expect(Array(menu.items.map(\.title).prefix(3)) == ["Claude", "", "Settings…"])
        #expect(side.items.map(\.title) == ["alex@example.com"])
    }

    @Test(arguments: [UsageProvider.claude, .cursor])
    func aSignedOutToolOffersNoSignIn(provider: UsageProvider) throws {
        let menu = MenuBarMenuBuilder().makeMenu(
            state: makeState(activeAccount: nil, providerUsage: [ProviderUsageState(provider: provider, status: .unavailable(.signedOut, lastSnapshot: nil))]),
            target: try makeCoordinator()
        )

        #expect(Array(menu.items.map(\.title).prefix(3)) == [provider.copy.sectionTitle, "", "Settings…"])
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

        #expect(menu.items.map(\.title) == ["Claude", "", "Codex", "", "Settings…", "", "Diagnostics…", "About", "", "Quit"])
    }

    @Test
    func turningOffClaudeModelLimitsInSettingsHidesTheFableThisWeekMeter() throws {
        let coordinator = try makeCoordinator()
        func claudeCard() throws -> NSMenuItem {
            let menu = MenuBarMenuBuilder().makeMenu(
                state: claudeState(modelNames: ["Fable"], showsModelLimits: coordinator.menuState().showsModelLimits),
                target: coordinator
            )
            return try #require(menu.items.first)
        }

        let before = try claudeCard()
        coordinator.setShowsModelLimits(false)
        let after = try claudeCard()

        #expect(!coordinator.menuState().showsModelLimits)
        #expect(try #require(after.view).frame.height < (try #require(before.view).frame.height))
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
        configureTokenUsage: (inout TokenUsageSettings) -> Void = { _ in }
    ) throws -> (MenuBarCoordinator, NSStatusItem) {
        let authFile = makeCodexAuthFile()
        let accountsController = AccountsController(
            authFile: authFile,
            accountStatusClient: DisabledAccountStatusClient(),
            signInWorkflow: CodexSignInWorkflow(
                authFile: authFile,
                isolatedLoginClient: IsolatedCodexLoginProbe(authData: Data()),
                codexAppProcessClient: CodexAppProcessProbe()
            )
        )
        let suiteName = "MenuBarMenuBuilderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsModel(userDefaults: defaults)
        configureTokenUsage(&settings.tokenUsage)
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
        sessionAccentColor: NSColor? = nil,
        hasCustomUsageColors: Bool = false,
        usagePercentMode: UsagePercentMode = .used,
        loginItemState: LoginItemState = .disabled,
        revealStatusItemTitleShortcut: RUsage.KeyboardShortcut? = .defaultRevealStatusItemTitle,
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
            refreshIntervalMinutes: 5,
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
                TokenUsageCardModel(card: $0, settings: SettingsModel(userDefaults: UserDefaults(suiteName: "token-usage-\(UUID().uuidString)")!))
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
        loadState: TokenUsageMenuLoadState,
        shownTools: [TokenUsageTool] = TokenUsageTool.allCases
    ) -> TokenUsageMenuCard {
        TokenUsageMenuCard.make(
            period: period,
            loadState: loadState,
            shownTools: shownTools,
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
