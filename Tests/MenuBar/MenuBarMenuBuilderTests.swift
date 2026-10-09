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
    func realPresentersCancelInteractivePromptsWhenSuppressed() async {
        let alertPresenter = SystemAlertPresenter(suppressesInteractivePrompts: true)
        let panelPresenter = SystemPanelPresenter(suppressesInteractivePrompts: true)

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
        alertPresenter.presentInfo(
            MenuBarInfoAlertRequest(
                messageText: "CodexPill Error",
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

        #expect(textValue == nil)
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
    func tokenUsageCardVisibleWhenEnabledWithSelectedPeriodCopy() throws {
        let state = makeState(
            activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
            inactiveAccounts: [makeAccount(name: "Other", usage: makeUsage(resettingAfter: .now))],
            tokenUsageEnabled: true,
            tokenUsagePeriod: .last30Days,
            tokenUsageChartStyle: .heatStrip,
            tokenUsageCard: makeTokenUsageCard(
                period: .last30Days,
                style: .heatStrip,
                loadState: loadedTokenUsageData([
                    dailyUsage(daysAgo: 1, totalTokens: 1_200),
                    dailyUsage(daysAgo: 0, totalTokens: 3_400)
                ])
            )
        )

        let tokenUsage = try #require(state.tokenUsageCard?.accessibilitySummary)

        #expect(tokenUsage.contains("Token Usage"))
        #expect(tokenUsage.contains("Last 30 days"))
        #expect(tokenUsage.contains("Today: 3,400 tokens"))
        #expect(tokenUsage.contains("Last 30 days: 4,600 tokens"))
        #expect(tokenUsage.contains("Peak day:"))
        #expect(tokenUsage.contains("May 20: 3,400 tokens"))
    }

    @Test
    func tokenUsageCardUsesCompactTokenFormattingForLargeTotals() {
        let card = makeTokenUsageCard(
            period: .last30Days,
            loadState: loadedTokenUsageData([
                dailyUsage(daysAgo: 1, totalTokens: 7_433_881_744),
                dailyUsage(daysAgo: 0, totalTokens: 108_637_804)
            ])
        )

        #expect(card.accessibilitySummary.contains("Today: 108.6M tokens"))
        #expect(card.accessibilitySummary.contains("Last 30 days: 7.5B tokens"))
        #expect(card.accessibilitySummary.contains("Peak day: May 19: 7.4B tokens"))
    }

    @Test
    func tokenUsageCardCanShowAllTimePeakWhenSelected() {
        let card = makeTokenUsageCard(
            period: .last30Days,
            peakScope: .allTime,
            loadState: loadedTokenUsageData(
                [
                    dailyUsage(daysAgo: 1, totalTokens: 7_433_881),
                    dailyUsage(daysAgo: 0, totalTokens: 108_637)
                ],
                allTimePeak: dailyUsage(daysAgo: 120, totalTokens: 9_800_000_000)
            )
        )

        #expect(card.peakDayTitle == "All-time peak")
        #expect(card.accessibilitySummary.contains("All-time peak: Jan 20: 9.8B tokens"))
    }

    @Test
    func tokenUsageCardShowsLoadingNoDataAndErrorStates() {
        let loading = makeTokenUsageCard(loadState: .loading(nil))
        let noData = makeTokenUsageCard(loadState: loadedTokenUsageData([
            dailyUsage(daysAgo: 1, totalTokens: 0),
            dailyUsage(daysAgo: 0, totalTokens: 0)
        ]))
        let unavailable = makeTokenUsageCard(loadState: .unavailable)

        #expect(loading.accessibilitySummary.contains("Scanning local sessions..."))
        #expect(noData.accessibilitySummary.contains("No token usage found yet"))
        #expect(unavailable.accessibilitySummary.contains("Token usage unavailable"))
    }

    @Test
    func tokenUsageLoadingFrameAnimatesMessageAndHighlightWithoutFakeProgress() {
        let firstFrame = TokenUsageLoadingFrame.make(
            at: Date(timeIntervalSince1970: 0),
            itemCount: 30
        )
        let secondFrame = TokenUsageLoadingFrame.make(
            at: Date(timeIntervalSince1970: 0.5),
            itemCount: 30
        )
        let reducedMotionFrame = TokenUsageLoadingFrame.make(
            at: Date(timeIntervalSince1970: 10),
            itemCount: 30,
            reduceMotion: true
        )

        #expect(firstFrame.message == "Scanning local sessions.")
        #expect(secondFrame.message == "Scanning local sessions..")
        #expect(firstFrame.highlightedIndex == 0)
        #expect(secondFrame.highlightedIndex == 1)
        #expect(firstFrame.phase == 0)
        #expect(secondFrame.phase == 0.5)
        #expect(!firstFrame.message.contains("%"))
        #expect(reducedMotionFrame.message == "Scanning local sessions...")
        #expect(reducedMotionFrame.highlightedIndex == 0)
        #expect(reducedMotionFrame.phase == 0)
    }

    @Test
    func tokenUsageLoadingFrameCanShowRealScanProgress() {
        let progress = TokenUsageScanProgress(scannedFiles: 42, totalFiles: 310)
        let frame = TokenUsageLoadingFrame.make(
            at: Date(timeIntervalSince1970: 0),
            itemCount: 30,
            baseMessage: progress.message
        )

        #expect(frame.message == "Scanning 42 of 310 sessions.")
        #expect(!frame.message.contains("%"))
    }

    @Test
    func preferencesMenuIncludesTokenUsageControls() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
                tokenUsageEnabled: true,
                tokenUsagePeriod: .last30Days,
                tokenUsageChartStyle: .sparkline,
                tokenUsageLoadingAnimationStyle: .random,
                tokenUsagePeakScope: .allTime
            ),
            target: coordinator
        )

        let preferencesMenu = try #require(menu.items.first(where: { $0.title == "Preferences" })?.submenu)
        let tokenUsageMenu = try #require(preferencesMenu.items.first(where: { $0.title == "Token Usage" })?.submenu)
        let show = try #require(tokenUsageMenu.items.first(where: { $0.title == "Show Token Usage" }))
        let peakDay = try #require(tokenUsageMenu.items.first(where: { $0.title == "Peak Day" })?.submenu)
        let chartStyle = try #require(tokenUsageMenu.items.first(where: { $0.title == "Chart Style" })?.submenu)
        let loadingAnimation = try #require(tokenUsageMenu.items.first(where: { $0.title == "Loading Animation" })?.submenu)

        #expect(show.state == .on)
        #expect(tokenUsageMenu.items.contains { $0.title == "Period" } == false)
        #expect(peakDay.items.map(\.title) == ["Last 30 Days", "All Time"])
        #expect(peakDay.items.first(where: { $0.title == "All Time" })?.state == .on)
        #expect(chartStyle.items.map(\.title) == ["Daily Bars", "Heat Strip", "Sparkline"])
        #expect(chartStyle.items.first(where: { $0.title == "Sparkline" })?.state == .on)
        #expect(loadingAnimation.items.map(\.title) == ["Waves", "Random"])
        #expect(loadingAnimation.items.first(where: { $0.title == "Random" })?.state == .on)
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
    func menuIncludesDiagnosticReportExportActionNearAbout() throws {
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
    func quitItemReservesIconColumnForStableTextAlignment() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now))),
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
        #expect(report.schemaVersion == 2)
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
    func visibleAccountsUseNativeSubmenusForSwitching() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let business3 = makeAccount(name: "Business 3", usage: makeUsage(resettingAfter: .now))
        let business4 = makeAccount(name: "Business 4", usage: makeUsage(resettingAfter: .now))
        let business2 = makeAccount(name: "Business 2", usage: makeUsage(resettingAfter: .now))
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
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
        let active = makeAccount(name: "Personal", usage: makeUsage(resettingAfter: .now))
        let state = makeState(activeAccount: active)
        let menu = builder.makeMenu(state: state, target: coordinator)

        let accountMenu = try #require(menu.items.first(where: { $0.title == "Account" })?.submenu)
        let addAccount = try #require(accountMenu.items.first(where: { $0.title == "Add Account…" }))
        let rename = try #require(accountMenu.items.first(where: { $0.title == "Rename…" }))
        let remove = try #require(accountMenu.items.first(where: { $0.title == "Remove…" }))

        #expect(accountRowIDs(in: menu).isEmpty)
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
        let active = makeAccount(name: "Personal", usage: makeUsage(resettingAfter: .now))
        let business1 = makeAccount(name: "Business 1", usage: makeUsage(resettingAfter: .now))
        let business2 = makeAccount(name: "Business 2", usage: makeUsage(resettingAfter: .now))
        let state = makeState(
            activeAccount: active,
            inactiveAccounts: [business1, business2]
        )
        let menu = builder.makeMenu(state: state, target: coordinator)

        let activeRow = menu.items.first(where: { $0.submenu?.title == active.name })
        let accountItem = try #require(menu.items.first(where: { $0.title == "Account" }))
        let accountMenu = try #require(accountItem.submenu)
        let rename = try #require(accountMenu.items.first(where: { $0.title == "Rename…" }))
        let remove = try #require(accountMenu.items.first(where: { $0.title == "Remove…" }))
        let addAccount = try #require(accountMenu.items.first(where: { $0.title == "Add Account…" }))

        #expect(Set(accountRowIDs(in: menu)) == [business1.id.uuidString, business2.id.uuidString])
        #expect(activeRow == nil)
        #expect(accountItem.image != nil)
        #expect(addAccount.action == #selector(MenuBarCoordinator.addAccount))
        #expect(menu.items.contains(where: { $0.title == "Add Account…" }) == false)
        #expect(rename.representedObject as? String == active.id.uuidString)
        #expect(remove.representedObject as? String == active.id.uuidString)
    }

    @Test
    func inactiveAccountSubmenuShowsNoEmailFallbackBeforeUsage() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        var account = makeAccount(name: "Business 3", usage: makeUsage(resettingAfter: .now))
        account.email = nil
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
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
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
                inactiveAccounts: [
                    makeAccount(name: "Business 3", usage: makeUsage(resettingAfter: .now)),
                    makeAccount(name: "Business 4", usage: makeUsage(resettingAfter: .now)),
                    makeAccount(name: "Business 2", usage: makeUsage(resettingAfter: .now)),
                    makeAccount(name: "Business 1", usage: makeUsage(resettingAfter: .now))
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
    func activeAccountHostedViewFitsWithinConfiguredMenuWidth() {
        let view = NSHostingView(
            rootView: ActiveAccountMenuContent(
                account: makeAccount(name: "Business 2", usage: makeUsage(resettingAfter: .now)),
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
    func singleActiveAccountDoesNotAddActiveCardDivider() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now))),
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
                activeAccount: makeAccount(name: "Personal", usage: makeUsage(resettingAfter: .now)),
                inactiveAccounts: [
                    makeAccount(name: "Business 1", usage: makeUsage(resettingAfter: .now)),
                    makeAccount(name: "Business 2", usage: makeUsage(resettingAfter: .now))
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
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 100, resetsAt: now.addingTimeInterval((4 * 60 + 59) * 60), durationMinutes: 300),
                secondary: (usedPercent: 78, resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60), durationMinutes: 10_080),
                fetchedAt: now
            )
        )
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Personal", usage: makeUsage(resettingAfter: .now)),
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
            now: now
        )

        #expect(headerWidth == 372)
        #expect(widestLocalRow.view == nil)
        #expect(widestLocalRow.attributedTitle?.string.contains("…") == true)
        #expect(rowWidth > 0)
    }

    @Test
    func statusItemMenuIncludesColorCustomizationAndReset() throws {
        let builder = MenuBarMenuBuilder()
        let coordinator = try makeCoordinator()
        let menu = builder.makeMenu(
            state: makeState(activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now))),
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
            state: makeState(activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now))),
            target: coordinator
        )

        let preferencesMenu = try #require(menu.items.first(where: { $0.title == "Preferences" })?.submenu)
        let usageBarsMenu = try #require(preferencesMenu.items.first(where: { $0.title == "Usage Bars" })?.submenu)
        let usageBarTitles = usageBarsMenu.items.map(\.title)
        let showMarkers = try #require(usageBarsMenu.items.first(where: { $0.title == "Show Pace Markers" }))

        #expect(preferencesMenu.items.map(\.title) == ["Menu Bar Label", "Icon Style", "Usage Bars", "Token Usage", "", "Launch at Login"])
        #expect(preferencesMenu.items[4].isSeparatorItem)
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
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
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
    func openingMenuDoesNotReplaceInactiveAccountRowsDuringOpen() throws {
        let builder = MenuBarMenuBuilder()
        let (coordinator, statusItem) = try makeCoordinatorWithStatusItem()
        let inactive = makeAccount(name: "Business 3", usage: makeUsage(resettingAfter: .now))
        let menu = builder.makeMenu(
            state: makeState(
                activeAccount: makeAccount(name: "Active", usage: makeUsage(resettingAfter: .now)),
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
                tokenUsagePeriod: .last30Days,
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
                tokenUsagePeriod: .last30Days,
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

    private func accountRowIDs(in menu: NSMenu) -> [String] {
        menu.items.compactMap { $0.submenu == nil ? nil : $0.representedObject as? String }
    }

    private func statusItemContentMenu(in menu: NSMenu) -> NSMenu? {
        menu.items
            .first(where: { $0.title == "Preferences" })?
            .submenu?
            .items
            .first(where: { $0.title == "Menu Bar Label" })?
            .submenu
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
        progressAccentColor: NSColor = .controlAccentColor,
        hasCustomProgressAccentColor: Bool = false,
        loginItemState: LoginItemState = .disabled,
        revealStatusItemTitleShortcut: CodexPill.KeyboardShortcut? = .defaultRevealStatusItemTitle,
        tokenUsageEnabled: Bool = false,
        tokenUsagePeriod: CodexTokenUsagePeriod = .last30Days,
        tokenUsageChartStyle: TokenUsageChartStyle = .dailyBars,
        tokenUsageLoadingAnimationStyle: TokenUsageLoadingAnimationStyle = .waves,
        tokenUsagePeakScope: TokenUsagePeakScope = .currentPeriod,
        tokenUsageCard: TokenUsageMenuCard? = nil
    ) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: inactiveAccounts,
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
            loginItemState: loginItemState,
            tokenUsageEnabled: tokenUsageEnabled,
            tokenUsagePeriod: tokenUsagePeriod,
            tokenUsageChartStyle: tokenUsageChartStyle,
            tokenUsageLoadingAnimationStyle: tokenUsageLoadingAnimationStyle,
            tokenUsagePeakScope: tokenUsagePeakScope,
            tokenUsageCard: tokenUsageCard
        )
    }

    private func makeTokenUsageCard(
        period: CodexTokenUsagePeriod = .last30Days,
        style: TokenUsageChartStyle = .dailyBars,
        peakScope: TokenUsagePeakScope = .currentPeriod,
        loadState: TokenUsageMenuLoadState
    ) -> TokenUsageMenuCard {
        TokenUsageMenuCard.make(
            style: style,
            peakScope: peakScope,
            period: period,
            loadState: loadState,
            calendar: Calendar(identifier: .gregorian)
        )
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
